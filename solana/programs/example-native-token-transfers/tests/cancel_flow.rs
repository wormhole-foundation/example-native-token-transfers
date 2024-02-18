#![feature(type_changing_struct_update)]

use anchor_lang::prelude::*;
use common::setup::{TestData, OTHER_CHAIN, OTHER_ENDPOINT, OTHER_MANAGER, THIS_CHAIN};
use example_native_token_transfers::{
    chain_id::ChainId,
    config::Mode,
    endpoints::wormhole::messages::WormholeEndpoint,
    instructions::{RedeemArgs, TransferArgs},
    messages::{EndpointMessage, ManagerMessage, NativeTokenTransfer},
    normalized_amount::NormalizedAmount,
    queue::{inbox::InboxRateLimit, outbox::OutboxRateLimit},
};
use sdk::endpoints::wormhole::instructions::receive_message::ReceiveMessage;
use solana_program_test::*;
use solana_sdk::{signature::Keypair, signer::Signer};
use wormhole_sdk::{Address, Vaa};

use crate::{common::submit::Submittable, sdk::instructions::transfer::transfer};
use crate::{
    common::{query::GetAccountDataAnchor, setup::setup},
    sdk::{
        endpoints::wormhole::instructions::receive_message::receive_message,
        instructions::{
            post_vaa::post_vaa,
            redeem::{redeem, Redeem},
            transfer::Transfer,
        },
    },
};

pub mod common;
pub mod sdk;

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
    chain_id: u16,
    manager_message: ManagerMessage<NativeTokenTransfer>,
) -> Redeem {
    Redeem {
        payer: ctx.payer.pubkey(),
        sibling: test_data.ntt.sibling(chain_id),
        endpoint: test_data.ntt.program,
        endpoint_message: test_data
            .ntt
            .endpoint_message(chain_id, manager_message.sequence),
        inbox_item: test_data.ntt.inbox_item(chain_id, manager_message),
        inbox_rate_limit: test_data.ntt.inbox_rate_limit(chain_id),
        mint: test_data.mint,
    }
}

fn init_receive_message_accs(
    ctx: &mut ProgramTestContext,
    test_data: &TestData,
    vaa: Pubkey,
    chain_id: u16,
    sequence: u64,
) -> ReceiveMessage {
    ReceiveMessage {
        payer: ctx.payer.pubkey(),
        sibling: test_data.ntt.endpoint_sibling(chain_id),
        vaa,
        chain_id,
        sequence,
    }
}

async fn post_transfer_vaa(
    ctx: &mut ProgramTestContext,
    test_data: &TestData,
    sequence: u64,
    amount: u64,
    recipient: &Keypair,
) -> (Pubkey, ManagerMessage<NativeTokenTransfer>) {
    let manager_message = ManagerMessage {
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
    };
    let endpoint_message: EndpointMessage<WormholeEndpoint, NativeTokenTransfer> =
        EndpointMessage::new(OTHER_MANAGER, manager_message.clone());

    let vaa = Vaa {
        version: 1,
        guardian_set_index: 0,
        signatures: vec![],
        timestamp: 123232,
        nonce: 0,
        emitter_chain: OTHER_CHAIN.into(),
        emitter_address: Address(OTHER_ENDPOINT),
        sequence: 0,
        consistency_level: 0,
        payload: endpoint_message,
    };

    let posted_vaa = post_vaa(&test_data.ntt.wormhole, ctx, vaa).await;

    (posted_vaa, manager_message)
}

async fn outbound_capacity(ctx: &mut ProgramTestContext, test_data: &TestData) -> u64 {
    let clock: Clock = ctx.banks_client.get_sysvar().await.unwrap();
    let rate_limit: OutboxRateLimit = ctx
        .get_account_data_anchor(test_data.ntt.outbox_rate_limit())
        .await;

    rate_limit.rate_limit.capacity_at(clock.unix_timestamp)
}

async fn inbound_capacity(ctx: &mut ProgramTestContext, test_data: &TestData) -> u64 {
    let clock: Clock = ctx.banks_client.get_sysvar().await.unwrap();
    let rate_limit: InboxRateLimit = ctx
        .get_account_data_anchor(test_data.ntt.inbox_rate_limit(OTHER_CHAIN))
        .await;

    rate_limit.rate_limit.capacity_at(clock.unix_timestamp)
}

#[tokio::test]
async fn test_cancel() {
    let recipient = Keypair::new();
    let (mut ctx, test_data) = setup(Mode::Locking).await;

    let (vaa0, msg0) = post_transfer_vaa(&mut ctx, &test_data, 0, 1000, &recipient).await;
    let (vaa1, msg1) = post_transfer_vaa(&mut ctx, &test_data, 1, 2000, &recipient).await;

    let inbound_limit_before = inbound_capacity(&mut ctx, &test_data).await;
    let outbound_limit_before = outbound_capacity(&mut ctx, &test_data).await;

    receive_message(
        &test_data.ntt,
        init_receive_message_accs(&mut ctx, &test_data, vaa0, OTHER_CHAIN, 0),
    )
    .submit(&mut ctx)
    .await
    .unwrap();

    redeem(
        &test_data.ntt,
        init_redeem_accs(&mut ctx, &test_data, OTHER_CHAIN, msg0),
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

    receive_message(
        &test_data.ntt,
        init_receive_message_accs(&mut ctx, &test_data, vaa1, OTHER_CHAIN, 1),
    )
    .submit(&mut ctx)
    .await
    .unwrap();

    redeem(
        &test_data.ntt,
        init_redeem_accs(&mut ctx, &test_data, OTHER_CHAIN, msg1),
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
