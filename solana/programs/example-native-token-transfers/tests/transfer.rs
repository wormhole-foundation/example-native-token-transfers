#![feature(type_changing_struct_update)]
#![feature(async_fn_in_trait)]

use anchor_lang::prelude::{Clock, Pubkey};
use anchor_spl::token::{Mint, TokenAccount};
use common::setup::TestData;
use example_native_token_transfers::{
    bitmap::Bitmap,
    chain_id::ChainId,
    config::Mode,
    endpoints::wormhole::messages::WormholeEndpoint,
    error::NTTError,
    instructions::{ReleaseOutboundArgs, TransferArgs},
    messages::{EndpointMessage, ManagerMessage, NativeTokenTransfer},
    normalized_amount::NormalizedAmount,
    queue::outbox::{OutboxItem, OutboxRateLimit},
    sequence::Sequence,
};
use solana_program_test::*;
use solana_sdk::{
    instruction::InstructionError, signature::Keypair, signer::Signer,
    transaction::TransactionError,
};
use wormhole_anchor_sdk::wormhole::PostedVaa;

use crate::{
    common::submit::Submittable,
    sdk::instructions::{
        admin::{set_paused, SetPaused},
        transfer::transfer,
    },
};
use crate::{
    common::{query::GetAccountDataAnchor, setup::OUTBOUND_LIMIT},
    sdk::instructions::{
        release_outbound::{release_outbound, ReleaseOutbound},
        transfer::Transfer,
    },
};

pub mod common;
pub mod sdk;

use crate::common::setup::setup;

// TODO: some more tests
// - unregistered sibling can't transfer
// - can't transfer more than balance
// - wrong inbox accounts
// - paused contracts

/// Helper function for setting up transfer accounts and args.
/// It sets the accounts up properly, so for negative testing we just modify the
/// result.
fn init_accs_args(
    ctx: &mut ProgramTestContext,
    test_data: &TestData,
    outbox_item: Pubkey,
    amount: u64,
    should_queue: bool,
) -> (Transfer, TransferArgs) {
    let accs = Transfer {
        payer: ctx.payer.pubkey(),
        mint: test_data.mint,
        from: test_data.user_token_account,
        from_authority: test_data.user.pubkey(),
        outbox_item,
    };

    let args = TransferArgs {
        amount,
        recipient_chain: ChainId { id: 2 },
        recipient_address: [1u8; 32],
        should_queue,
    };

    (accs, args)
}

#[tokio::test]
pub async fn test_transfer_locking() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;
    test_transfer(&mut ctx, &test_data, Mode::Locking).await;
}

#[tokio::test]
pub async fn test_transfer_burning() {
    let (mut ctx, test_data) = setup(Mode::Burning).await;
    test_transfer(&mut ctx, &test_data, Mode::Burning).await;
}

/// This tests the happy path of a transfer, with all the relevant account checks.
/// Written as a helper function so both modes can be tested.
async fn test_transfer(ctx: &mut ProgramTestContext, test_data: &TestData, mode: Mode) {
    let outbox_item = Keypair::new();

    let clock: Clock = ctx.banks_client.get_sysvar().await.unwrap();

    let sequence: Sequence = ctx.get_account_data_anchor(test_data.ntt.sequence()).await;

    let (accs, args) = init_accs_args(ctx, test_data, outbox_item.pubkey(), 100, false);

    transfer(&test_data.ntt, accs, args, mode)
        .submit_with_signers(&[&test_data.user, &outbox_item], ctx)
        .await
        .unwrap();

    let outbox_item_account: OutboxItem = ctx.get_account_data_anchor(outbox_item.pubkey()).await;

    assert_eq!(
        outbox_item_account,
        OutboxItem {
            sequence: sequence.sequence,
            amount: NormalizedAmount {
                amount: 10,
                decimals: 8
            },
            sender: test_data.user.pubkey(),
            recipient_chain: ChainId { id: 2 },
            recipient_address: [1u8; 32],
            release_timestamp: clock.unix_timestamp,
            released: Bitmap::new(),
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

    let outbox_item_account_after: OutboxItem =
        ctx.get_account_data_anchor(outbox_item.pubkey()).await;

    // make sure the outbox item is now released, but nothing else has changed
    assert_eq!(
        OutboxItem {
            released: Bitmap::from_value(1),
            ..outbox_item_account
        },
        outbox_item_account_after,
    );

    let wh_message = test_data.ntt.wormhole_message(&outbox_item.pubkey());

    // NOTE: technically this is not a PostedVAA but a PostedMessage, but the
    // sdk does not export that type, so we parse it as a PostedVAA instead.
    // They are identical modulo the discriminator, which we just skip by using
    // the unchecked deserialiser.
    // TODO: update the sdk to export PostedMessage
    let msg: PostedVaa<EndpointMessage<WormholeEndpoint, NativeTokenTransfer>> =
        ctx.get_account_data_anchor_unchecked(wh_message).await;

    let endpoint_message = msg.data();

    assert_eq!(
        endpoint_message,
        &EndpointMessage::new(
            example_native_token_transfers::ID.to_bytes(),
            ManagerMessage {
                sequence: sequence.sequence,
                sender: test_data.user.pubkey().to_bytes(),
                payload: NativeTokenTransfer {
                    amount: NormalizedAmount {
                        amount: 10,
                        decimals: 8
                    },
                    source_token: test_data.mint.to_bytes(),
                    to: [1u8; 32],
                    to_chain: ChainId { id: 2 },
                }
            }
        )
    );

    let next_sequence: Sequence = ctx.get_account_data_anchor(test_data.ntt.sequence()).await;
    assert_eq!(next_sequence.sequence, sequence.sequence + 1);
}

#[tokio::test]
async fn test_burn_mode_burns_tokens() {
    let (mut ctx, test_data) = setup(Mode::Burning).await;

    let outbox_item = Keypair::new();

    let (accs, args) = init_accs_args(&mut ctx, &test_data, outbox_item.pubkey(), 105, false);

    let mint_before: Mint = ctx.get_account_data_anchor(test_data.mint).await;

    let token_account_before: TokenAccount = ctx
        .get_account_data_anchor(test_data.user_token_account)
        .await;

    transfer(&test_data.ntt, accs, args, Mode::Burning)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap();

    let mint_after: Mint = ctx.get_account_data_anchor(test_data.mint).await;

    let token_account_after: TokenAccount = ctx
        .get_account_data_anchor(test_data.user_token_account)
        .await;

    // NOTE: we transfer 105, but only 100 gets burned (token is 9 decimals, and
    // gets normalised to 8)
    // TODO: should we just revert if there's dust?
    assert_eq!(mint_before.supply - 100, mint_after.supply);
    assert_eq!(
        token_account_before.amount - 100,
        token_account_after.amount
    );
}

#[tokio::test]
async fn locking_mode_locks_tokens() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let outbox_item = Keypair::new();

    let (accs, args) = init_accs_args(&mut ctx, &test_data, outbox_item.pubkey(), 105, false);

    let token_account_before: TokenAccount = ctx
        .get_account_data_anchor(test_data.user_token_account)
        .await;

    let custody_account_before: TokenAccount = ctx
        .get_account_data_anchor(test_data.ntt.custody(&test_data.mint))
        .await;

    let mint_before: Mint = ctx.get_account_data_anchor(test_data.mint).await;

    transfer(&test_data.ntt, accs, args, Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap();

    let token_account_after: TokenAccount = ctx
        .get_account_data_anchor(test_data.user_token_account)
        .await;

    let custody_account_after: TokenAccount = ctx
        .get_account_data_anchor(test_data.ntt.custody(&test_data.mint))
        .await;

    let mint_after: Mint = ctx.get_account_data_anchor(test_data.mint).await;

    // NOTE: we transfer 105, but only 100 gets locked (token is 9 decimals, and
    // gets normalised to 8)

    assert_eq!(
        token_account_before.amount - 100,
        token_account_after.amount
    );

    assert_eq!(
        custody_account_before.amount + 100,
        custody_account_after.amount
    );

    assert_eq!(mint_before.supply, mint_after.supply);
}

#[tokio::test]
async fn test_rate_limit() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let outbox_item = Keypair::new();
    let clock: Clock = ctx.banks_client.get_sysvar().await.unwrap();

    let (accs, args) = init_accs_args(&mut ctx, &test_data, outbox_item.pubkey(), 100, false);

    let outbound_limit_before: OutboxRateLimit = ctx
        .get_account_data_anchor(test_data.ntt.outbox_rate_limit())
        .await;

    transfer(&test_data.ntt, accs, args, Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap();

    let outbound_limit_after: OutboxRateLimit = ctx
        .get_account_data_anchor(test_data.ntt.outbox_rate_limit())
        .await;

    assert_eq!(NormalizedAmount::normalize(100, 9).amount, 10);

    assert_eq!(
        outbound_limit_before.capacity_at(clock.unix_timestamp)
            - NormalizedAmount::normalize(100, 9),
        outbound_limit_after.capacity_at(clock.unix_timestamp)
    );
}

#[tokio::test]
async fn test_transfer_wrong_mode() {
    let (mut ctx, test_data) = setup(Mode::Burning).await;
    let outbox_item = Keypair::new();

    let (accs, args) = init_accs_args(&mut ctx, &test_data, outbox_item.pubkey(), 100, false);

    // make sure we can't transfer in the wrong mode
    let err = transfer(&test_data.ntt, accs.clone(), args.clone(), Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap_err();

    assert_eq!(
        err.unwrap(),
        TransactionError::InstructionError(
            0,
            InstructionError::Custom(NTTError::InvalidMode.into())
        )
    );
}

async fn assert_queued(ctx: &mut ProgramTestContext, outbox_item: Pubkey) {
    let outbox_item_account: OutboxItem = ctx.get_account_data_anchor(outbox_item).await;

    let clock: Clock = ctx.banks_client.get_sysvar().await.unwrap();

    assert!(!outbox_item_account.released.get(0));
    assert!(outbox_item_account.release_timestamp > clock.unix_timestamp);
}

#[tokio::test]
async fn test_large_tx_queue() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let outbox_item = Keypair::new();

    let too_much = OUTBOUND_LIMIT + 1000;
    let should_queue = true;
    let (accs, args) = init_accs_args(
        &mut ctx,
        &test_data,
        outbox_item.pubkey(),
        too_much,
        should_queue,
    );

    let outbound_limit_before: OutboxRateLimit = ctx
        .get_account_data_anchor(test_data.ntt.outbox_rate_limit())
        .await;

    transfer(&test_data.ntt, accs, args, Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap();

    let outbound_limit_after: OutboxRateLimit = ctx
        .get_account_data_anchor(test_data.ntt.outbox_rate_limit())
        .await;

    assert_queued(&mut ctx, outbox_item.pubkey()).await;

    // queued transfers don't change the rate limit
    assert_eq!(outbound_limit_before, outbound_limit_after);
}

#[tokio::test]
async fn test_cant_transfer_when_paused() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let outbox_item = Keypair::new();

    let (accs, args) = init_accs_args(&mut ctx, &test_data, outbox_item.pubkey(), 100, false);

    set_paused(
        &test_data.ntt,
        SetPaused {
            owner: test_data.program_owner.pubkey(),
        },
        true,
    )
    .submit_with_signers(&[&test_data.program_owner], &mut ctx)
    .await
    .unwrap();

    let err = transfer(&test_data.ntt, accs.clone(), args.clone(), Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap_err();

    assert_eq!(
        err.unwrap(),
        TransactionError::InstructionError(0, InstructionError::Custom(NTTError::Paused.into()))
    );

    // make sure we can unpause
    set_paused(
        &test_data.ntt,
        SetPaused {
            owner: test_data.program_owner.pubkey(),
        },
        false,
    )
    .submit_with_signers(&[&test_data.program_owner], &mut ctx)
    .await
    .unwrap();

    transfer(&test_data.ntt, accs, args, Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap();
}

#[tokio::test]
async fn test_large_tx_no_queue() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let outbox_item = Keypair::new();

    let too_much = OUTBOUND_LIMIT + 1000;
    let should_queue = false;
    let (accs, args) = init_accs_args(
        &mut ctx,
        &test_data,
        outbox_item.pubkey(),
        too_much,
        should_queue,
    );

    let err = transfer(&test_data.ntt, accs, args, Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap_err();

    assert_eq!(
        err.unwrap(),
        TransactionError::InstructionError(
            0,
            InstructionError::Custom(NTTError::TransferExceedsRateLimit.into())
        )
    );
}

#[tokio::test]
async fn test_cant_release_queued() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let outbox_item = Keypair::new();

    let too_much = OUTBOUND_LIMIT + 1000;
    let (accs, args) = init_accs_args(&mut ctx, &test_data, outbox_item.pubkey(), too_much, true);

    transfer(&test_data.ntt, accs, args, Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap();

    assert_queued(&mut ctx, outbox_item.pubkey()).await;

    // check that 'revert_on_delay = true' returns correct error
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
    .submit(&mut ctx)
    .await
    .unwrap_err();

    assert_eq!(
        err.unwrap(),
        TransactionError::InstructionError(
            0,
            InstructionError::Custom(NTTError::CantReleaseYet.into())
        )
    );

    // check that 'revert_on_delay = false' succeeds but does not release
    release_outbound(
        &test_data.ntt,
        ReleaseOutbound {
            payer: ctx.payer.pubkey(),
            outbox_item: outbox_item.pubkey(),
        },
        ReleaseOutboundArgs {
            revert_on_delay: false,
        },
    )
    .submit(&mut ctx)
    .await
    .unwrap();

    assert_queued(&mut ctx, outbox_item.pubkey()).await;

    // just to be safe, let's make sure the wormhole message account wasn't initialised
    let wh_message = test_data.ntt.wormhole_message(&outbox_item.pubkey());
    assert!(ctx
        .banks_client
        .get_account(wh_message)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn test_cant_release_twice() {
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let outbox_item = Keypair::new();

    let (accs, args) = init_accs_args(&mut ctx, &test_data, outbox_item.pubkey(), 100, false);

    transfer(&test_data.ntt, accs, args, Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap();

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
    .submit(&mut ctx)
    .await
    .unwrap();

    // make sure we can't release again
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
    .submit(&mut ctx)
    .await
    .unwrap_err();

    assert_eq!(
        err.unwrap(),
        TransactionError::InstructionError(
            0,
            InstructionError::Custom(NTTError::MessageAlreadySent.into())
        )
    );
}
