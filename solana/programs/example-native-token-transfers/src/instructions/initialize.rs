use anchor_lang::prelude::*;
use anchor_spl::token_interface;

use crate::{
    chain_id::ChainId,
    normalized_amount::NormalizedAmount,
    queue::{outbox::OutboxRateLimit, rate_limit::RateLimitState},
    sequence::Sequence,
};

// TODO: upgradeability
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub owner: Signer<'info>,

    #[account(
        init,
        space = 8 + crate::config::Config::INIT_SPACE,
        payer = payer,
        seeds = [crate::config::Config::SEED_PREFIX],
        bump
    )]
    pub config: Account<'info, crate::config::Config>,

    #[account()]
    pub mint: InterfaceAccount<'info, token_interface::Mint>,

    #[account(
        init,
        payer = payer,
        space = 8 + Sequence::INIT_SPACE,
        seeds = [Sequence::SEED_PREFIX],
        bump,
    )]
    pub seq: Account<'info, Sequence>,

    #[account(
        init,
        payer = payer,
        space = 8 + OutboxRateLimit::INIT_SPACE,
        seeds = [OutboxRateLimit::SEED_PREFIX],
        bump,
    )]
    pub rate_limit: Account<'info, OutboxRateLimit>,

    system_program: Program<'info, System>,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct InitializeArgs {
    pub chain_id: u16,
    pub limit: u64,
}

pub fn initialize(ctx: Context<Initialize>, args: InitializeArgs) -> Result<()> {
    ctx.accounts.config.set_inner(crate::config::Config {
        bump: ctx.bumps.config,
        mint: ctx.accounts.mint.key(),
        mode: crate::config::Mode::Burning,
        chain_id: ChainId { id: args.chain_id },
        owner: ctx.accounts.owner.key(),
        pending_owner: None,
        paused: false,
    });

    ctx.accounts.seq.set_inner(Sequence {
        bump: ctx.bumps.seq,
        sequence: 0,
    });

    let decimals: u8 = ctx.accounts.mint.decimals;

    ctx.accounts.rate_limit.set_inner(OutboxRateLimit {
        rate_limit: RateLimitState::new(NormalizedAmount::normalize(args.limit, decimals)),
    });

    Ok(())
}
