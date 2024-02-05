use anchor_lang::{prelude::*, solana_program::clock};

use wormhole_anchor_sdk::wormhole;
use wormhole_io::TypePrefixedPayload;

use crate::{
    config::Config,
    error::NTTError,
    messages::{ManagerMessage, NativeTokenTransfer},
    queue::outbound::OutboundQueuedTransfer,
};

#[derive(Accounts)]
pub struct ReleaseOutbound<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: Account<'info, Config>,

    #[account(
        mut,
        constraint = !enqueued.released @ NTTError::MessageAlreadySent,
    )]
    pub enqueued: Account<'info, OutboundQueuedTransfer>,

    #[account(
        mut,
        seeds = [b"message", enqueued.sequence.to_be_bytes().as_ref()],
        bump,
    )]
    /// CHECK: initialized and written to by wormhole core bridge
    pub wormhole_message: UncheckedAccount<'info>,

    #[account(
        mut,
        seeds = [b"emitter"],
        bump
    )]
    // TODO: do we want to put anything in here?
    /// CHECK: wormhole uses this as the emitter address
    pub emitter: UncheckedAccount<'info>,

    // wormhole stuff
    #[account(mut)]
    /// CHECK: address will be checked by the wormhole core bridge
    pub wormhole_bridge: Account<'info, wormhole::BridgeData>,

    #[account(mut)]
    /// CHECK: account will be checked by the wormhole core bridge
    pub wormhole_fee_collector: UncheckedAccount<'info>,

    #[account(mut)]
    /// CHECK: account will be checked and maybe initialized by the wormhole core bridge
    pub wormhole_sequence: UncheckedAccount<'info>,

    pub wormhole_program: Program<'info, wormhole::program::Wormhole>,

    pub system_program: Program<'info, System>,

    // legacy
    pub clock: Sysvar<'info, Clock>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct ReleaseOutboundArgs {}

pub fn release_outbound(ctx: Context<ReleaseOutbound>, _args: ReleaseOutboundArgs) -> Result<()> {
    let accs = ctx.accounts;
    let batch_id = 0;

    // TODO: record endpoint position
    accs.enqueued.release()?;

    let message: ManagerMessage<NativeTokenTransfer> = ManagerMessage {
        chain_id: accs.config.chain_id,
        sequence: accs.enqueued.sequence,
        sender: accs.emitter.key().to_bytes().to_vec(),
        payload: NativeTokenTransfer {
            amount: accs.enqueued.amount,
            to: accs.enqueued.recipient_address.clone(),
            to_chain: accs.enqueued.recipient_chain,
        },
    };

    wormhole::post_message(
        CpiContext::new_with_signer(
            accs.wormhole_program.to_account_info(),
            wormhole::PostMessage {
                config: accs.wormhole_bridge.to_account_info(),
                message: accs.wormhole_message.to_account_info(),
                emitter: accs.emitter.to_account_info(),
                sequence: accs.wormhole_sequence.to_account_info(),
                payer: accs.payer.to_account_info(),
                fee_collector: accs.wormhole_fee_collector.to_account_info(),
                clock: accs.clock.to_account_info(),
                rent: accs.rent.to_account_info(),
                system_program: accs.system_program.to_account_info(),
            },
            &[
                &[b"emitter", &[ctx.bumps["emitter"]]],
                &[
                    b"message",
                    accs.enqueued.sequence.to_be_bytes().as_ref(),
                    &[ctx.bumps["wormhole_message"]],
                ],
            ],
        ),
        batch_id,
        TypePrefixedPayload::to_vec_payload(&message),
        wormhole::Finality::Finalized,
    )?;
    Ok(())
}
