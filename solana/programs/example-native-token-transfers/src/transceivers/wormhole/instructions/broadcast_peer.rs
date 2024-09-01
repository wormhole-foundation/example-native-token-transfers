use anchor_lang::prelude::*;
use ntt_messages::{chain_id::ChainId, transceivers::wormhole::WormholeTransceiverRegistration};

use crate::{
    config::*,
    transceivers::{accounts::peer::TransceiverPeer, wormhole::accounts::*},
};

#[derive(Accounts)]
#[instruction(args: BroadcastPeerArgs)]
pub struct BroadcastPeer<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: Account<'info, Config>,

    #[account(
        seeds = [TransceiverPeer::SEED_PREFIX, args.chain_id.to_be_bytes().as_ref()],
        bump
    )]
    pub peer: Account<'info, TransceiverPeer>,

    /// CHECK: initialized and written to by wormhole core bridge
    #[account(mut)]
    pub wormhole_message: Signer<'info>,

    #[account(
        seeds = [b"emitter"],
        bump
    )]
    /// CHECK: The seeds constraint ensures that this is the correct address
    pub emitter: UncheckedAccount<'info>,

    pub wormhole: WormholeAccounts<'info>,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct BroadcastPeerArgs {
    pub chain_id: u16,
}

pub fn broadcast_peer(ctx: Context<BroadcastPeer>, args: BroadcastPeerArgs) -> Result<()> {
    let accs = ctx.accounts;

    let message = WormholeTransceiverRegistration {
        chain_id: ChainId { id: args.chain_id },
        transceiver_address: accs.peer.address,
    };

    // TODO: should we send this as an unreliable message into a PDA?
    post_message(
        &accs.wormhole,
        accs.payer.to_account_info(),
        accs.wormhole_message.to_account_info(),
        accs.emitter.to_account_info(),
        ctx.bumps.emitter,
        &message,
        &[],
    )?;

    Ok(())
}
