use anchor_lang::prelude::{Error, Id, Pubkey};
use anchor_spl::token::{Mint, Token};
use example_native_token_transfers::{
    chain_id::ChainId,
    config::Mode,
    endpoints::wormhole::SetEndpointSiblingArgs,
    instructions::{InitializeArgs, SetSiblingArgs},
};
use solana_program_test::{ProgramTest, ProgramTestContext};
use solana_sdk::{
    account::Account, signature::Keypair, signer::Signer, system_instruction,
    transaction::Transaction,
};
use spl_associated_token_account::get_associated_token_address_with_program_id;
use spl_token::instruction::AuthorityType;
use wormhole_anchor_sdk::wormhole::{BridgeData, FeeCollector};

use crate::sdk::{
    accounts::{Governance, Wormhole, NTT},
    endpoints::wormhole::instructions::admin::{set_endpoint_sibling, SetEndpointSibling},
    instructions::{
        admin::{register_endpoint, set_sibling, RegisterEndpoint, SetSibling},
        initialize::{initialize, Initialize},
    },
};

use super::{
    account_json_utils::{add_account_unchecked, AccountLoadable},
    submit::Submittable,
};

// TODO: maybe make these configurable? I think it's fine like this:
// the mint amount is more than the limits, so we can test the rate limits
pub const MINT_AMOUNT: u64 = 100000;
pub const OUTBOUND_LIMIT: u64 = 10000;
pub const INBOUND_LIMIT: u64 = 50000;

pub const OTHER_ENDPOINT: [u8; 32] = [7u8; 32];
pub const OTHER_MANAGER: [u8; 32] = [9u8; 32];

pub const THIS_CHAIN: u16 = 1;
pub const OTHER_CHAIN: u16 = 2;

pub struct TestData {
    pub ntt: NTT,
    pub governance: Governance,
    pub program_owner: Keypair,
    pub mint_authority: Keypair,
    pub mint: Pubkey,
    pub user: Keypair,
    pub user_token_account: Pubkey,
}

pub async fn setup_with_extra_accounts(
    mode: Mode,
    accounts: &[(Pubkey, Account)],
) -> (ProgramTestContext, TestData) {
    let mut program_test = setup_programs().await.unwrap();

    for (pubkey, account) in accounts {
        program_test.add_account(*pubkey, account.clone());
    }

    let mut ctx = program_test.start_with_context().await;

    let test_data = setup_accounts(&mut ctx).await;
    setup_ntt(&mut ctx, &test_data, mode).await;

    (ctx, test_data)
}

pub async fn setup(mode: Mode) -> (ProgramTestContext, TestData) {
    setup_with_extra_accounts(mode, &[]).await
}

pub async fn setup_programs() -> Result<ProgramTest, Error> {
    let mut program_test = ProgramTest::default();
    program_test.add_program(
        "example_native_token_transfers",
        example_native_token_transfers::ID,
        None,
    );

    program_test.add_program("wormhole_governance", wormhole_governance::ID, None);

    program_test.add_program(
        "mainnet_core_bridge",
        wormhole_anchor_sdk::wormhole::program::ID,
        None,
    );

    BridgeData::add_account(
        &mut program_test,
        "../../tests/accounts/mainnet/core_bridge_config.json",
    )?;

    FeeCollector::add_account(
        &mut program_test,
        "../../tests/accounts/mainnet/core_bridge_fee_collector.json",
    )?;

    // TODO: GuardianSet struct is not exposed in the wormhole sdk
    add_account_unchecked(
        &mut program_test,
        "../../tests/accounts/mainnet/guardian_set_0.json",
    )?;

    Ok(program_test)
}

/// Set up test accounts, and mint MINT_AMOUNT to the user's token account
/// Set up the program for locking mode, and registers a sibling
pub async fn setup_ntt(ctx: &mut ProgramTestContext, test_data: &TestData, mode: Mode) {
    if mode == Mode::Burning {
        // we set the mint authority to the ntt contract in burn/mint mode
        spl_token::instruction::set_authority(
            &spl_token::ID,
            &test_data.mint,
            Some(&test_data.ntt.token_authority()),
            AuthorityType::MintTokens,
            &test_data.mint_authority.pubkey(),
            &[],
        )
        .unwrap()
        .submit_with_signers(&[&test_data.mint_authority], ctx)
        .await
        .unwrap();
    }

    initialize(
        &test_data.ntt,
        Initialize {
            payer: ctx.payer.pubkey(),
            owner: test_data.program_owner.pubkey(),
            mint: test_data.mint,
        },
        InitializeArgs {
            // TODO: use sdk
            chain_id: THIS_CHAIN,
            limit: OUTBOUND_LIMIT,
            mode,
        },
    )
    .submit_with_signers(&[&test_data.program_owner], ctx)
    .await
    .unwrap();

    register_endpoint(
        &test_data.ntt,
        RegisterEndpoint {
            payer: ctx.payer.pubkey(),
            owner: test_data.program_owner.pubkey(),
            endpoint: example_native_token_transfers::ID, // standalone manager&endpoint
        },
    )
    .submit_with_signers(&[&test_data.program_owner], ctx)
    .await
    .unwrap();

    set_endpoint_sibling(
        &test_data.ntt,
        SetEndpointSibling {
            payer: ctx.payer.pubkey(),
            owner: test_data.program_owner.pubkey(),
        },
        SetEndpointSiblingArgs {
            chain_id: ChainId { id: OTHER_CHAIN },
            address: OTHER_ENDPOINT,
        },
    )
    .submit_with_signers(&[&test_data.program_owner], ctx)
    .await
    .unwrap();

    set_sibling(
        &test_data.ntt,
        SetSibling {
            payer: ctx.payer.pubkey(),
            owner: test_data.program_owner.pubkey(),
            mint: test_data.mint,
        },
        SetSiblingArgs {
            chain_id: ChainId { id: OTHER_CHAIN },
            address: OTHER_MANAGER,
            limit: INBOUND_LIMIT,
        },
    )
    .submit_with_signers(&[&test_data.program_owner], ctx)
    .await
    .unwrap();
}

pub async fn setup_accounts(ctx: &mut ProgramTestContext) -> TestData {
    // create mint
    let program_owner = Keypair::new();

    let mint = Keypair::new();
    let mint_authority = Keypair::new();

    let user = Keypair::new();
    let payer = ctx.payer.pubkey();

    create_mint(ctx, &mint, &mint_authority.pubkey(), 9)
        .await
        .submit(ctx)
        .await
        .unwrap();

    // create associated token account for user
    let user_token_account =
        get_associated_token_address_with_program_id(&user.pubkey(), &mint.pubkey(), &Token::id());

    spl_associated_token_account::instruction::create_associated_token_account(
        &payer,
        &user.pubkey(),
        &mint.pubkey(),
        &Token::id(),
    )
    .submit(ctx)
    .await
    .unwrap();

    spl_token::instruction::mint_to(
        &Token::id(),
        &mint.pubkey(),
        &user_token_account,
        &mint_authority.pubkey(),
        &[],
        MINT_AMOUNT,
    )
    .unwrap()
    .submit_with_signers(&[&mint_authority], ctx)
    .await
    .unwrap();

    TestData {
        ntt: NTT {
            program: example_native_token_transfers::ID,
            wormhole: Wormhole {
                program: wormhole_anchor_sdk::wormhole::program::ID,
            },
        },
        governance: Governance {
            program: wormhole_governance::ID,
        },
        program_owner,
        mint_authority,
        mint: mint.pubkey(),
        user,
        user_token_account,
    }
}

pub async fn create_mint(
    ctx: &mut ProgramTestContext,
    mint: &Keypair,
    mint_authority: &Pubkey,
    decimals: u8,
) -> Transaction {
    let rent = ctx.banks_client.get_rent().await.unwrap();
    let mint_rent = rent.minimum_balance(Mint::LEN);

    let blockhash = ctx.banks_client.get_latest_blockhash().await.unwrap();

    Transaction::new_signed_with_payer(
        &[
            system_instruction::create_account(
                &ctx.payer.pubkey(),
                &mint.pubkey(),
                mint_rent,
                Mint::LEN as u64,
                &spl_token::ID,
            ),
            spl_token::instruction::initialize_mint2(
                &spl_token::ID,
                &mint.pubkey(),
                mint_authority,
                None,
                decimals,
            )
            .unwrap(),
        ],
        Some(&ctx.payer.pubkey()),
        &[&ctx.payer, mint],
        blockhash,
    )
}
