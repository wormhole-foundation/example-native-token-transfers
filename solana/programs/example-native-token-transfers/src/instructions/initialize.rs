use anchor_lang::prelude::*;
use anchor_spl::{associated_token::AssociatedToken, token_interface};

use crate::{
    chain_id::ChainId,
    error::NTTError,
    normalized_amount::NormalizedAmount,
    queue::{outbox::OutboxRateLimit, rate_limit::RateLimitState},
    sequence::Sequence,
};

// TODO: upgradeability
#[derive(Accounts)]
#[instruction(args: InitializeArgs)]
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

    #[account(
        constraint =
            args.mode == crate::config::Mode::Locking
            || mint.mint_authority.unwrap() == token_authority.key()
            @ NTTError::InvalidMintAuthority,
    )]
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

    #[account(
        seeds = [b"token_authority"],
        bump,
    )]
    pub token_authority: AccountInfo<'info>,

    #[account(
        init,
        payer = payer,
        associated_token::mint = mint,
        associated_token::authority = token_authority,
    )]
    /// The custody account that holds tokens in locking mode.
    /// NOTE: the account is unconditionally initialized, but not used in
    /// burning mode.
    pub custody: InterfaceAccount<'info, token_interface::TokenAccount>,

    /// CHECK: checked to be the appropriate token progrem when initialising the
    /// associated token account for the given mint.
    pub token_program: Interface<'info, token_interface::TokenInterface>,
    pub associated_token_program: Program<'info, AssociatedToken>,

    system_program: Program<'info, System>,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct InitializeArgs {
    pub chain_id: u16,
    pub limit: u64,
    pub mode: crate::config::Mode,
}

pub fn initialize(ctx: Context<Initialize>, args: InitializeArgs) -> Result<()> {
    ctx.accounts.config.set_inner(crate::config::Config {
        bump: ctx.bumps.config,
        mint: ctx.accounts.mint.key(),
        token_program: ctx.accounts.token_program.key(),
        mode: args.mode,
        chain_id: ChainId { id: args.chain_id },
        owner: ctx.accounts.owner.key(),
        pending_owner: None,
        paused: false,
        next_endpoint_id: 0,
        // NOTE: can't be changed for now
        threshold: 1,
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
