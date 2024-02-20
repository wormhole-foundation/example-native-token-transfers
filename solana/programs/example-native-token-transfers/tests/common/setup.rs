use std::path::PathBuf;

use anchor_lang::prelude::{Error, Id, Pubkey};
use anchor_spl::token::{Mint, Token};
use example_native_token_transfers::{
    chain_id::ChainId,
    config::Mode,
    endpoints::wormhole::SetEndpointSiblingArgs,
    instructions::{InitializeArgs, SetSiblingArgs},
};
use solana_program::{bpf_loader_upgradeable::UpgradeableLoaderState, rent::Rent};
use solana_program_runtime::{
    invoke_context::ProcessInstructionWithContext,
    log_collector::log::{trace, warn},
};
use solana_program_test::{find_file, read_file, ProgramTest, ProgramTestContext};
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
    let program_owner = Keypair::new();
    let mut program_test = setup_programs(program_owner.pubkey()).await.unwrap();

    for (pubkey, account) in accounts {
        program_test.add_account(*pubkey, account.clone());
    }

    let mut ctx = program_test.start_with_context().await;

    let test_data = setup_accounts(&mut ctx, program_owner).await;
    setup_ntt(&mut ctx, &test_data, mode).await;

    (ctx, test_data)
}

pub async fn setup(mode: Mode) -> (ProgramTestContext, TestData) {
    setup_with_extra_accounts(mode, &[]).await
}

fn prefer_bpf() -> bool {
    std::env::var("BPF_OUT_DIR").is_ok() || std::env::var("SBF_OUT_DIR").is_ok()
}

pub async fn setup_programs(program_owner: Pubkey) -> Result<ProgramTest, Error> {
    let mut program_test = ProgramTest::default();
    add_program_upgradeable(
        &mut program_test,
        "example_native_token_transfers",
        example_native_token_transfers::ID,
        None,
        Some(program_owner),
    );

    add_program_upgradeable(
        &mut program_test,
        "wormhole_governance",
        wormhole_governance::ID,
        None,
        None,
    );

    add_program_upgradeable(
        &mut program_test,
        "mainnet_core_bridge",
        wormhole_anchor_sdk::wormhole::program::ID,
        None,
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
            deployer: test_data.program_owner.pubkey(),
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

pub async fn setup_accounts(ctx: &mut ProgramTestContext, program_owner: Keypair) -> TestData {
    // create mint
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

// TODO: upstream this to solana-program-test

/// Add a SBF program to the test environment. (copied from solana_program_test
/// `add_program`, but the owner is bpf_loader_upgradeable)
///
/// `program_name` will also be used to locate the SBF shared object in the current or fixtures
/// directory.
///
/// If `process_instruction` is provided, the natively built-program may be used instead of the
/// SBF shared object depending on the `BPF_OUT_DIR` environment variable.
pub fn add_program_upgradeable(
    program_test: &mut ProgramTest,
    program_name: &str,
    program_id: Pubkey,
    process_instruction: Option<ProcessInstructionWithContext>,
    upgrade_authority_address: Option<Pubkey>,
) {
    let add_bpf = |this: &mut ProgramTest, program_file: PathBuf| {
        let elf = read_file(program_file);

        let (programdata_address, _) = Pubkey::find_program_address(
            &[program_id.as_ref()],
            &solana_sdk::bpf_loader_upgradeable::id(),
        );
        let mut program_data = bincode::serialize(&UpgradeableLoaderState::ProgramData {
            slot: 0,
            upgrade_authority_address: upgrade_authority_address.or(Some(Pubkey::default())),
        })
        .unwrap();
        program_data.extend_from_slice(&elf);

        this.add_account(
            programdata_address,
            Account {
                lamports: Rent::default().minimum_balance(program_data.len()).max(1),
                data: program_data,
                owner: solana_sdk::bpf_loader_upgradeable::id(),
                executable: false,
                rent_epoch: 0,
            },
        );

        let data = bincode::serialize(&UpgradeableLoaderState::Program {
            programdata_address,
        })
        .unwrap();

        this.add_account(
            program_id,
            Account {
                lamports: Rent::default().minimum_balance(data.len()).max(1),
                data,
                owner: solana_sdk::bpf_loader_upgradeable::id(),
                executable: true,
                rent_epoch: 0,
            },
        );
    };

    let warn_invalid_program_name = || {
        let valid_program_names = default_shared_object_dirs()
            .iter()
            .filter_map(|dir| dir.read_dir().ok())
            .flat_map(|read_dir| {
                read_dir.filter_map(|entry| {
                    let path = entry.ok()?.path();
                    if !path.is_file() {
                        return None;
                    }
                    match path.extension()?.to_str()? {
                        "so" => Some(path.file_stem()?.to_os_string()),
                        _ => None,
                    }
                })
            })
            .collect::<Vec<_>>();

        if valid_program_names.is_empty() {
            // This should be unreachable as `test-bpf` should guarantee at least one shared
            // object exists somewhere.
            warn!("No SBF shared objects found.");
            return;
        }

        warn!(
            "Possible bogus program name. Ensure the program name ({}) \
                matches one of the following recognizable program names:",
            program_name,
        );
        for name in valid_program_names {
            warn!(" - {}", name.to_str().unwrap());
        }
    };

    let program_file = find_file(&format!("{program_name}.so"));
    match (prefer_bpf(), program_file, process_instruction) {
        // If SBF is preferred (i.e., `test-sbf` is invoked) and a BPF shared object exists,
        // use that as the program data.
        (true, Some(file), _) => add_bpf(program_test, file),

        // If SBF is not required (i.e., we were invoked with `test`), use the provided
        // processor function as is.
        //
        // TODO: figure out why tests hang if a processor panics when running native code.
        (false, _, Some(process)) => {
            program_test.add_builtin_program(program_name, program_id, process)
        }

        // Invalid: `test-sbf` invocation with no matching SBF shared object.
        (true, None, _) => {
            warn_invalid_program_name();
            panic!("Program file data not available for {program_name} ({program_id})");
        }

        // Invalid: regular `test` invocation without a processor.
        (false, _, None) => {
            panic!("Program processor not available for {program_name} ({program_id})");
        }
    }
}

fn default_shared_object_dirs() -> Vec<PathBuf> {
    let mut search_path = vec![];
    if let Ok(bpf_out_dir) = std::env::var("BPF_OUT_DIR") {
        search_path.push(PathBuf::from(bpf_out_dir));
    } else if let Ok(bpf_out_dir) = std::env::var("SBF_OUT_DIR") {
        search_path.push(PathBuf::from(bpf_out_dir));
    }
    search_path.push(PathBuf::from("tests/fixtures"));
    if let Ok(dir) = std::env::current_dir() {
        search_path.push(dir);
    }
    trace!("SBF .so search path: {:?}", search_path);
    search_path
}
