use anchor_lang::prelude::*;
use ntt_messages::chain_id::ChainId;

use crate::{config::Config, transceivers::accounts::sibling::TransceiverSibling};

#[derive(Accounts)]
#[instruction(args: SetTransceiverSiblingArgs)]
pub struct SetTransceiverSibling<'info> {
    #[account(
        has_one = owner,
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,

    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init,
        space = 8 + TransceiverSibling::INIT_SPACE,
        payer = payer,
        seeds = [TransceiverSibling::SEED_PREFIX, args.chain_id.id.to_be_bytes().as_ref()],
        bump
    )]
    pub sibling: Account<'info, TransceiverSibling>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct SetTransceiverSiblingArgs {
    pub chain_id: ChainId,
    pub address: [u8; 32],
}

pub fn set_transceiver_sibling(
    ctx: Context<SetTransceiverSibling>,
    args: SetTransceiverSiblingArgs,
) -> Result<()> {
    ctx.accounts.sibling.set_inner(TransceiverSibling {
        bump: ctx.bumps.sibling,
        address: args.address,
    });

    Ok(())
}
