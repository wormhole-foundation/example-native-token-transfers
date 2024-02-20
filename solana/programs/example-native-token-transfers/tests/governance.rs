#![feature(type_changing_struct_update)]

use anchor_lang::{prelude::*, InstructionData};
use example_native_token_transfers::{
    config::{Config, Mode},
    instructions::TransferOwnershipArgs,
};
use sdk::accounts::{Governance, Wormhole};
use solana_program::instruction::{Instruction, InstructionError};
use solana_program_test::*;
use solana_sdk::{signer::Signer, transaction::TransactionError};
use wormhole_governance::{
    error::GovernanceError,
    instructions::{GovernanceMessage, OWNER},
};
use wormhole_sdk::{Address, Vaa, GOVERNANCE_EMITTER};

use crate::{
    common::{query::GetAccountDataAnchor, setup::setup, submit::Submittable},
    sdk::instructions::{
        admin::{set_paused, SetPaused},
        post_vaa::post_vaa,
    },
};

pub mod common;
pub mod sdk;

async fn post_governance_vaa<A: Clone + AnchorSerialize>(
    ctx: &mut ProgramTestContext,
    wormhole: &Wormhole,
    gov_message: A,
    emitter_override: Option<Address>,
) -> Pubkey {
    let vaa = Vaa {
        version: 1,
        guardian_set_index: 0,
        signatures: vec![],
        timestamp: 123232,
        nonce: 0,
        emitter_chain: wormhole_sdk::Chain::Solana,
        emitter_address: emitter_override.unwrap_or(GOVERNANCE_EMITTER),
        sequence: 0,
        consistency_level: 0,
        payload: gov_message,
    };

    post_vaa(wormhole, ctx, vaa).await
}

#[tokio::test]
async fn test_governance() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let governance_pda = test_data.governance.governance();

    // step 1. transfer ownership to governance
    let ix = example_native_token_transfers::instruction::TransferOwnership {
        args: TransferOwnershipArgs {
            new_owner: governance_pda,
        },
    };

    let accs = example_native_token_transfers::accounts::TransferOwnership {
        config: test_data.ntt.config(),
        owner: test_data.program_owner.pubkey(),
    };

    Instruction {
        program_id: test_data.ntt.program,
        accounts: accs.to_account_metas(None),
        data: ix.data(),
    }
    .submit_with_signers(&[&test_data.program_owner], &mut ctx)
    .await
    .unwrap();

    // step 2. claim ownership
    let inner_ix_data = example_native_token_transfers::instruction::ClaimOwnership {};
    let inner_ix_accs = example_native_token_transfers::accounts::ClaimOwnership {
        new_owner: OWNER,
        config: test_data.ntt.config(),
    };

    let inner_ix: Instruction = Instruction {
        program_id: test_data.ntt.program,
        accounts: inner_ix_accs.to_account_metas(None),
        data: inner_ix_data.data(),
    };

    wrap_governance(
        &mut ctx,
        &test_data.governance,
        &test_data.ntt.wormhole,
        inner_ix,
        None,
    )
    .await
    .unwrap();

    // step 3. set paused
    wrap_governance(
        &mut ctx,
        &test_data.governance,
        &test_data.ntt.wormhole,
        set_paused(&test_data.ntt, SetPaused { owner: OWNER }, true),
        None,
    )
    .await
    .unwrap();

    let config_account: Config = ctx.get_account_data_anchor(test_data.ntt.config()).await;
    assert!(config_account.paused);
}

#[tokio::test]
async fn test_governance_bad_emitter() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let err = wrap_governance(
        &mut ctx,
        &test_data.governance,
        &test_data.ntt.wormhole,
        set_paused(&test_data.ntt, SetPaused { owner: OWNER }, true),
        Some(Address::default()),
    )
    .await
    .unwrap_err();

    assert_eq!(
        err.unwrap(),
        TransactionError::InstructionError(
            0,
            InstructionError::Custom(GovernanceError::InvalidGovernanceEmitter.into())
        )
    );
}

// TODO: move (some of) this into the governance library
async fn wrap_governance(
    ctx: &mut ProgramTestContext,
    gov_program: &Governance,
    wormhole: &Wormhole,
    ix: Instruction,
    emitter_override: Option<Address>,
) -> core::result::Result<(), BanksClientError> {
    let program = ix.program_id;
    // TODO: LUTs?

    let data = wormhole_governance::instruction::Governance {};

    let gov_message: GovernanceMessage = ix.clone().into();

    let vaa = post_governance_vaa(ctx, wormhole, gov_message, emitter_override).await;

    let gov_accounts = wormhole_governance::accounts::Governance {
        payer: ctx.payer.pubkey(),
        governance: gov_program.governance(),
        vaa,
        program,
    };

    let mut accounts = gov_accounts.to_account_metas(None);

    let remaining_accounts = ix.accounts.iter().map(|acc| AccountMeta {
        is_signer: false,
        ..acc.clone()
    });

    accounts.extend(remaining_accounts);

    let gov_ix = Instruction {
        program_id: gov_program.program,
        accounts,
        data: data.data(),
    };

    gov_ix.submit(ctx).await
}
