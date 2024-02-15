use anchor_lang::prelude::*;

use crate::{chain_id::ChainId, config::Config, endpoints::accounts::sibling::EndpointSibling};

#[derive(Accounts)]
#[instruction(args: SetEndpointSiblingArgs)]
pub struct SetEndpointSibling<'info> {
    #[account(
        has_one = owner,
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,

    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init,
        space = 8 + EndpointSibling::INIT_SPACE,
        payer = payer,
        seeds = [EndpointSibling::SEED_PREFIX, args.chain_id.id.to_be_bytes().as_ref()],
        bump
    )]
    pub sibling: Account<'info, EndpointSibling>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct SetEndpointSiblingArgs {
    pub chain_id: ChainId,
    pub address: [u8; 32],
}

pub fn set_endpoint_sibling(
    ctx: Context<SetEndpointSibling>,
    args: SetEndpointSiblingArgs,
) -> Result<()> {
    ctx.accounts.sibling.set_inner(EndpointSibling {
        bump: ctx.bumps.sibling,
        address: args.address,
    });

    Ok(())
}
