use anchor_lang::prelude::*;

use wormhole_anchor_sdk::wormhole;
use wormhole_io::TypePrefixedPayload;

use crate::{
    config::*,
    endpoints::wormhole::messages::WormholeEndpoint,
    error::NTTError,
    messages::{EndpointMessage, ManagerMessage, NativeTokenTransfer},
    queue::outbox::OutboxItem,
    registered_endpoint::*,
};

#[derive(Accounts)]
pub struct ReleaseOutbound<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: NotPausedConfig<'info>,

    #[account(
        mut,
        constraint = !outbox_item.released.get(endpoint.id) @ NTTError::MessageAlreadySent,
    )]
    pub outbox_item: Account<'info, OutboxItem>,

    #[account(
        constraint = endpoint.endpoint_address == crate::ID,
    )]
    pub endpoint: EnabledEndpoint<'info>,

    #[account(
        mut,
        seeds = [b"message", outbox_item.key().as_ref()],
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
pub struct ReleaseOutboundArgs {
    pub revert_on_delay: bool,
}

pub fn release_outbound(ctx: Context<ReleaseOutbound>, args: ReleaseOutboundArgs) -> Result<()> {
    let accs = ctx.accounts;
    let batch_id = 0;

    let released = accs.outbox_item.try_release(accs.endpoint.id)?;

    if !released {
        if args.revert_on_delay {
            return Err(NTTError::CantReleaseYet.into());
        } else {
            return Ok(());
        }
    }

    assert!(accs.outbox_item.released.get(accs.endpoint.id));
    let message: EndpointMessage<WormholeEndpoint, NativeTokenTransfer> = EndpointMessage::new(
        // TODO: should we just put the ntt id here statically?
        accs.outbox_item.to_account_info().owner.to_bytes(),
        ManagerMessage {
            sequence: accs.outbox_item.sequence,
            sender: accs.outbox_item.sender.to_bytes(),
            payload: NativeTokenTransfer {
                amount: accs.outbox_item.amount,
                source_token: accs.config.mint.to_bytes(),
                to: accs.outbox_item.recipient_address.clone(),
                to_chain: accs.outbox_item.recipient_chain,
            },
        },
    );

    if accs.wormhole_bridge.fee() > 0 {
        anchor_lang::system_program::transfer(
            CpiContext::new(
                accs.system_program.to_account_info(),
                anchor_lang::system_program::Transfer {
                    from: accs.payer.to_account_info(),
                    to: accs.wormhole_fee_collector.to_account_info(),
                },
            ),
            accs.wormhole_bridge.fee(),
        )?;
    }

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
                &[b"emitter", &[ctx.bumps.emitter]],
                &[
                    b"message",
                    accs.outbox_item.key().as_ref(),
                    &[ctx.bumps.wormhole_message],
                ],
            ],
        ),
        batch_id,
        TypePrefixedPayload::to_vec_payload(&message),
        wormhole::Finality::Finalized,
    )?;
    Ok(())
}
