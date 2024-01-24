use anchor_lang::prelude::*;

use crate::chain_id::ChainId;

// TODO: upgradeability
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init,
        space = 8 + crate::config::Config::INIT_SPACE,
        payer = payer,
        seeds = [crate::config::Config::SEED_PREFIX],
        bump
    )]
    pub config: Account<'info, crate::config::Config>,

    #[account()]
    pub mint: Account<'info, anchor_spl::token::Mint>,

    system_program: Program<'info, System>,
    // TODO: initialize rate limits
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct InitializeArgs {
    pub chain_id: u16,
}

pub fn initialize(ctx: Context<Initialize>, args: InitializeArgs) -> Result<()> {
    ctx.accounts.config.set_inner(crate::config::Config {
        bump: ctx.bumps["config"],
        mint: ctx.accounts.mint.key(),
        mode: crate::config::Mode::Locking,
        chain_id: ChainId { id: args.chain_id },
    });

    Ok(())
}
