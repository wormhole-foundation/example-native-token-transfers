#![feature(type_changing_struct_update)]
#![feature(async_fn_in_trait)]

use anchor_lang::{
    prelude::{Clock, Pubkey},
    AccountSerialize,
};
use common::setup::TestData;
use example_native_token_transfers::{
    chain_id::ChainId,
    config::Mode,
    instructions::{RedeemArgs, TransferArgs},
    messages::{EndpointMessage, ManagerMessage, NativeTokenTransfer, WormholeEndpoint},
    normalized_amount::NormalizedAmount,
    queue::{inbox::InboxRateLimit, outbox::OutboxRateLimit},
};
use solana_program_test::*;
use solana_sdk::{account::Account, signature::Keypair, signer::Signer};
use wormhole_io::TypePrefixedPayload;

use crate::{
    common::{hack::PostedVaaHack, query::GetAccountDataAnchor},
    sdk::instructions::{
        redeem::{redeem, Redeem},
        transfer::Transfer,
    },
};
use crate::{
    common::{setup::setup_with_extra_accounts, submit::Submittable},
    sdk::instructions::transfer::transfer,
};

pub mod common;
pub mod sdk;

const THIS_CHAIN: u16 = 1;
const OTHER_CHAIN: u16 = 2;

fn init_transfer_accs_args(
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
        recipient_chain: ChainId { id: OTHER_CHAIN },
        recipient_address: [1u8; 32],
        should_queue,
    };

    (accs, args)
}

fn init_redeem_accs(
    ctx: &mut ProgramTestContext,
    test_data: &TestData,
    vaa: Pubkey,
    chain_id: u16,
    sequence: u64,
) -> Redeem {
    let accs = Redeem {
        payer: ctx.payer.pubkey(),
        sibling: test_data.ntt.sibling(chain_id),
        vaa,
        inbox_item: test_data.ntt.inbox_item(chain_id, sequence),
        inbox_rate_limit: test_data.ntt.inbox_rate_limit(chain_id),
    };

    accs
}

/// helper function to write into vaa accounts.
/// this is mostly to avoid having to go through the process of posting the vaa
/// via the wormhole program
/// TODO: in an ideal world it should be very easy to do that, but the sdk
/// doesn't support posting vaas yet.
/// TODO: in an ideal world, writing into these accounts should be even easier, but
/// the sdk doesn't have a working serializer implementation for the vaa account either
fn make_vaa(sequence: u64, amount: u64, recipient: &Keypair) -> (Pubkey, Account) {
    let vaa = Keypair::new();
    let endpoint_message: EndpointMessage<WormholeEndpoint, NativeTokenTransfer> =
        EndpointMessage::new(
            [5u8; 32],
            ManagerMessage {
                sequence,
                sender: [4u8; 32],
                payload: NativeTokenTransfer {
                    amount: NormalizedAmount {
                        amount,
                        decimals: 9,
                    },
                    source_token: [3u8; 32],
                    to_chain: ChainId { id: THIS_CHAIN },
                    to: recipient.pubkey().to_bytes(),
                },
            },
        );

    let payload = endpoint_message.to_vec_payload();

    let vaa_data = PostedVaaHack {
        vaa_version: 1,
        consistency_level: 32,
        vaa_time: 0,
        vaa_signature_account: Keypair::new().pubkey(),
        submission_time: 0,
        nonce: 0,
        sequence,
        emitter_chain: OTHER_CHAIN,
        emitter_address: [7u8; 32],
        payload,
    };

    let mut serialized = vec![];
    vaa_data.try_serialize(&mut serialized).unwrap();

    let vaa_account: Account = Account {
        lamports: 1000000,
        data: serialized,
        owner: wormhole_anchor_sdk::wormhole::program::id(),
        executable: false,
        rent_epoch: u64::MAX,
    };

    (vaa.pubkey(), vaa_account)
}

async fn outbound_capacity(ctx: &mut ProgramTestContext, test_data: &TestData) -> u64 {
    let clock: Clock = ctx.banks_client.get_sysvar().await.unwrap();
    let rate_limit: OutboxRateLimit = ctx
        .get_account_data_anchor(test_data.ntt.outbox_rate_limit())
        .await;

    rate_limit
        .rate_limit
        .capacity_at(clock.unix_timestamp)
        .denormalize(9)
}

async fn inbound_capacity(ctx: &mut ProgramTestContext, test_data: &TestData) -> u64 {
    let clock: Clock = ctx.banks_client.get_sysvar().await.unwrap();
    let rate_limit: InboxRateLimit = ctx
        .get_account_data_anchor(test_data.ntt.inbox_rate_limit(OTHER_CHAIN))
        .await;

    rate_limit
        .rate_limit
        .capacity_at(clock.unix_timestamp)
        .denormalize(9)
}

#[tokio::test]
async fn test_cancel() {
    let recipient = Keypair::new();
    let (vaa0, vaa_account0) = make_vaa(0, 1000, &recipient);
    let (vaa1, vaa_account1) = make_vaa(1, 2000, &recipient);
    let (mut ctx, test_data) =
        setup_with_extra_accounts(Mode::Locking, &[(vaa0, vaa_account0), (vaa1, vaa_account1)])
            .await;

    let inbound_limit_before = inbound_capacity(&mut ctx, &test_data).await;
    let outbound_limit_before = outbound_capacity(&mut ctx, &test_data).await;

    redeem(
        &test_data.ntt,
        init_redeem_accs(&mut ctx, &test_data, vaa0, 2, 0),
        RedeemArgs {},
    )
    .submit(&mut ctx)
    .await
    .unwrap();

    assert_eq!(
        outbound_limit_before,
        outbound_capacity(&mut ctx, &test_data).await
    );

    assert_eq!(
        inbound_limit_before - 1000,
        inbound_capacity(&mut ctx, &test_data).await
    );

    let outbox_item = Keypair::new();

    let (accs, args) =
        init_transfer_accs_args(&mut ctx, &test_data, outbox_item.pubkey(), 7000, true);

    transfer(&test_data.ntt, accs, args, Mode::Locking)
        .submit_with_signers(&[&test_data.user, &outbox_item], &mut ctx)
        .await
        .unwrap();

    assert_eq!(
        outbound_limit_before - 7000,
        outbound_capacity(&mut ctx, &test_data).await
    );

    // fully replenished
    assert_eq!(
        inbound_limit_before,
        inbound_capacity(&mut ctx, &test_data).await
    );

    redeem(
        &test_data.ntt,
        init_redeem_accs(&mut ctx, &test_data, vaa1, OTHER_CHAIN, 1),
        RedeemArgs {},
    )
    .submit(&mut ctx)
    .await
    .unwrap();

    assert_eq!(
        outbound_limit_before - 5000,
        outbound_capacity(&mut ctx, &test_data).await
    );

    assert_eq!(
        inbound_limit_before - 2000,
        inbound_capacity(&mut ctx, &test_data).await
    );
}
