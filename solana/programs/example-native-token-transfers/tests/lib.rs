#![feature(type_changing_struct_update)]
#![feature(async_fn_in_trait)]
use std::io::Error;

use anchor_lang::{
    prelude::{Clock, Pubkey},
    AccountDeserialize, Id,
};
use anchor_spl::token::{Mint, Token};
use common::account_utils::{add_account_unchecked, AccountLoadable};
use example_native_token_transfers::{
    chain_id::ChainId,
    config::Mode,
    error::NTTError,
    instructions::{InitializeArgs, ReleaseOutboundArgs, SetSiblingArgs, TransferArgs},
    messages::{EndpointMessage, ManagerMessage, NativeTokenTransfer, WormholeEndpoint},
    normalized_amount::NormalizedAmount,
    queue::outbox::OutboxItem,
    sequence::Sequence,
};
use sdk::accounts::Wormhole;
use solana_program_test::*;
use solana_sdk::{
    instruction::{Instruction, InstructionError},
    signature::Keypair,
    signer::Signer,
    signers::Signers,
    system_instruction,
    transaction::{Transaction, TransactionError},
};
use spl_associated_token_account::get_associated_token_address_with_program_id;
use spl_token::instruction::AuthorityType;
use wormhole_anchor_sdk::wormhole::{BridgeData, FeeCollector, PostedVaa};

use crate::sdk::{
    accounts::NTT,
    instructions::{
        admin::{set_sibling, SetSibling},
        initialize::{initialize, Initialize},
        release_outbound::{release_outbound, ReleaseOutbound},
        transfer::{transfer_burn, transfer_lock, Transfer},
    },
};

pub mod common;
// TODO: move this outside of the test module
pub mod sdk;

pub async fn setup() -> Result<ProgramTest, Error> {
    let mut program_test = ProgramTest::default();
    program_test.add_program(
        "example_native_token_transfers",
        example_native_token_transfers::ID,
        None,
    );

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

struct TestData {
    pub ntt: NTT,
    pub program_owner: Keypair,
    pub mint_authority: Keypair,
    pub mint: Pubkey,
    pub user: Keypair,
    pub user_token_account: Pubkey,
}

const MINT_AMOUNT: u64 = 100000;

/// Set up test accounts, and mint MINT_AMOUNT to the user's token account
async fn setup_accounts(ctx: &mut ProgramTestContext) -> TestData {
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
        program_owner,
        mint_authority,
        mint: mint.pubkey(),
        user,
        user_token_account,
    }
}

/// Set up the program for locking mode, and registers a sibling
async fn setup_ntt(ctx: &mut ProgramTestContext, test_data: &TestData, mode: Mode) {
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
            chain_id: 1,
            limit: 10000,
            mode,
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
            chain_id: ChainId { id: 2 },
            address: [7u8; 32],
            limit: 10000,
        },
    )
    .submit_with_signers(&[&test_data.program_owner], ctx)
    .await
    .unwrap();
}

#[tokio::test]
async fn tests() {
    // NOTE: these can't be run concurrently, as they cause deadlocks
    test_transfer_locking().await;
    test_transfer_burning().await;
}

async fn test_transfer_locking() {
    let program_test = setup().await.unwrap();
    let mut ctx = program_test.start_with_context().await;

    let test_data = setup_accounts(&mut ctx).await;
    setup_ntt(&mut ctx, &test_data, Mode::Locking).await;

    test_transfer_helper(&mut ctx, &test_data, Mode::Locking).await;
}

async fn test_transfer_burning() {
    let program_test = setup().await.unwrap();
    let mut ctx = program_test.start_with_context().await;

    let test_data = setup_accounts(&mut ctx).await;
    setup_ntt(&mut ctx, &test_data, Mode::Burning).await;

    test_transfer_helper(&mut ctx, &test_data, Mode::Burning).await;
}

async fn test_transfer_helper(ctx: &mut ProgramTestContext, test_data: &TestData, mode: Mode) {
    let outbox_item = Keypair::new();

    let clock: Clock = ctx.banks_client.get_sysvar().await.unwrap();

    let sequence: Sequence = ctx
        .banks_client
        .get_account_data_anchor(test_data.ntt.sequence())
        .await
        .unwrap();

    let transfer = Transfer {
        payer: ctx.payer.pubkey(),
        mint: test_data.mint,
        from: test_data.user_token_account,
        from_authority: test_data.user.pubkey(),
        outbox_item: outbox_item.pubkey(),
    };

    let args = TransferArgs {
        amount: 100,
        recipient_chain: ChainId { id: 2 },
        recipient_address: [1u8; 32],
        should_queue: false,
    };

    match mode {
        Mode::Burning => transfer_burn(&test_data.ntt, transfer, args)
            .submit_with_signers(&[&test_data.user, &outbox_item], ctx)
            .await
            .unwrap(),
        Mode::Locking => transfer_lock(&test_data.ntt, transfer, args)
            .submit_with_signers(&[&test_data.user, &outbox_item], ctx)
            .await
            .unwrap(),
    }

    let outbox_item_account: OutboxItem = ctx
        .banks_client
        .get_account_data_anchor(outbox_item.pubkey())
        .await
        .unwrap();

    assert_eq!(
        outbox_item_account,
        OutboxItem {
            sequence: 0,
            amount: NormalizedAmount {
                amount: 10,
                decimals: 8
            },
            sender: test_data.user_token_account,
            recipient_chain: ChainId { id: 2 },
            recipient_address: [1u8; 32],
            release_timestamp: clock.unix_timestamp,
            released: false
        }
    );

    release_outbound(
        &test_data.ntt,
        ReleaseOutbound {
            payer: ctx.payer.pubkey(),
            outbox_item: outbox_item.pubkey(),
        },
        ReleaseOutboundArgs {
            revert_on_delay: true,
        },
    )
    .submit(ctx)
    .await
    .unwrap();

    let outbox_item_account_after: OutboxItem = ctx
        .banks_client
        .get_account_data_anchor(outbox_item.pubkey())
        .await
        .unwrap();

    // make sure the outbox item is now released, but nothing else has changed
    assert_eq!(
        OutboxItem {
            released: true,
            ..outbox_item_account
        },
        outbox_item_account_after,
    );

    // make sure we can't send again
    let err = release_outbound(
        &test_data.ntt,
        ReleaseOutbound {
            payer: ctx.payer.pubkey(),
            outbox_item: outbox_item.pubkey(),
        },
        ReleaseOutboundArgs {
            revert_on_delay: true,
        },
    )
    .submit(ctx)
    .await
    .unwrap_err();

    assert_eq!(
        err.unwrap(),
        TransactionError::InstructionError(
            0,
            InstructionError::Custom(NTTError::MessageAlreadySent.into())
        )
    );

    let wh_message = test_data.ntt.wormhole_message(&outbox_item.pubkey());

    // NOTE: technically this is not a PostedVAA but a PostedMessage, but the
    // sdk does not export that type, so we parse it as a PostedVAA instead.
    // They are identical modulo the discriminator, which we just skip by using
    // the unchecked deserialiser.
    // TODO: update the sdk to export PostedMessage
    let msg: PostedVaa<EndpointMessage<WormholeEndpoint, NativeTokenTransfer>> = ctx
        .banks_client
        .get_account_data_anchor_unchecked(wh_message)
        .await
        .unwrap();

    let endpoint_message = msg.data();

    assert_eq!(
        endpoint_message,
        &EndpointMessage::new(ManagerMessage {
            chain_id: ChainId { id: 1 },
            sequence: sequence.sequence,
            source_manager: example_native_token_transfers::ID.to_bytes(),
            sender: test_data.user_token_account.to_bytes(),
            payload: NativeTokenTransfer {
                amount: NormalizedAmount {
                    amount: 10,
                    decimals: 8
                },
                source_token: test_data.mint.to_bytes(),
                to: [1u8; 32],
                to_chain: ChainId { id: 2 },
            }
        })
    );

    let next_sequence: Sequence = ctx
        .banks_client
        .get_account_data_anchor(test_data.ntt.sequence())
        .await
        .unwrap();
    assert_eq!(next_sequence.sequence, sequence.sequence + 1);
}

/////////// Utils

trait GetAccountDataAnchor {
    async fn get_account_data_anchor<T: AccountDeserialize>(
        &mut self,
        pubkey: Pubkey,
    ) -> Result<T, BanksClientError>;

    async fn get_account_data_anchor_unchecked<T: AccountDeserialize>(
        &mut self,
        pubkey: Pubkey,
    ) -> Result<T, BanksClientError>;
}

impl GetAccountDataAnchor for BanksClient {
    async fn get_account_data_anchor<T: AccountDeserialize>(
        &mut self,
        pubkey: Pubkey,
    ) -> Result<T, BanksClientError> {
        let data = self.get_account(pubkey).await?.unwrap();
        Ok(T::try_deserialize(&mut data.data.as_ref()).unwrap())
    }

    async fn get_account_data_anchor_unchecked<T: AccountDeserialize>(
        &mut self,
        pubkey: Pubkey,
    ) -> Result<T, BanksClientError> {
        let data = self.get_account(pubkey).await?.unwrap();
        Ok(T::try_deserialize_unchecked(&mut data.data.as_ref()).unwrap())
    }
}

trait Submittable {
    async fn submit(self, ctx: &mut ProgramTestContext) -> Result<(), BanksClientError>
    where
        Self: Sized,
    {
        let no_signers: &[&Keypair] = &[];
        self.submit_with_signers(no_signers, ctx).await
    }
    async fn submit_with_signers<T: Signers + ?Sized>(
        self,
        signers: &T,
        ctx: &mut ProgramTestContext,
    ) -> Result<(), BanksClientError>;
}

impl Submittable for Instruction {
    async fn submit_with_signers<T: Signers + ?Sized>(
        self,
        signers: &T,
        ctx: &mut ProgramTestContext,
    ) -> Result<(), BanksClientError> {
        let blockhash = ctx.banks_client.get_latest_blockhash().await.unwrap();

        let mut transaction = Transaction::new_with_payer(&[self], Some(&ctx.payer.pubkey()));
        transaction.partial_sign(&[&ctx.payer], blockhash);
        transaction.partial_sign(signers, blockhash);

        ctx.banks_client.process_transaction(transaction).await
    }
}

impl Submittable for Transaction {
    async fn submit_with_signers<T: Signers + ?Sized>(
        mut self,
        signers: &T,
        ctx: &mut ProgramTestContext,
    ) -> Result<(), BanksClientError> {
        let blockhash = ctx.banks_client.get_latest_blockhash().await.unwrap();

        self.partial_sign(&[&ctx.payer], blockhash);
        self.partial_sign(signers, blockhash);
        ctx.banks_client.process_transaction(self).await
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
