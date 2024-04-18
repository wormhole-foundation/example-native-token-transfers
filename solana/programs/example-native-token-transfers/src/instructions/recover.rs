//! This module implements instructions to recover transfers. Only the owner can
//! execute these instructions.
//!
//! Recovery means that the tokens are redeemed, but instead of sending them to
//! the recipient, they are sent to a recovery account. The recovery account is
//! a token account of the appropriate mint.
//!
//! This is useful in case the underlying token implements a blocklisting
//! mechanism (such as OFAC sanctions), and the recipient is blocked, meaning
//! the tokens are irredeemable.
//!
//! In such cases, the owner can recover the transfer by sending them to the
//! recovery address (typically controlled by the owner, though we're not
//! prescriptive about access control of that account).
//! Ideally, it would be nice to attempt to make the transfer to the original
//! recipient, and only allow recovery if that fails. However, solana's runtime does
//! not allow recovering from a failed CPI call, so that is not possible.
//!
//! This feature is opt-in, and hidden behind a feature flag ("owner-recovery").
//! When that flag is set to false, the instructions in this module will revert.

use anchor_lang::prelude::*;
use anchor_spl::token_interface;

use crate::instructions::release_inbound::*;

#[account]
#[derive(InitSpace)]
pub struct RecoveryAccount {
    /// The bump seed for the recovery account
    pub bump: u8,
    /// The token account that will receive the recovered tokens
    pub recovery_address: Pubkey,
}

impl RecoveryAccount {
    pub const SEED: &'static [u8] = b"recovery";
}

#[derive(Accounts)]
pub struct InitializeRecoveryAccount<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: Account<'info, crate::config::Config>,

    #[account(
        constraint = owner.key() == config.owner
    )]
    pub owner: Signer<'info>,

    #[account(
        init,
        payer = payer,
        space = 8 + RecoveryAccount::INIT_SPACE,
        seeds = [RecoveryAccount::SEED],
        bump,
    )]
    pub recovery: Account<'info, RecoveryAccount>,

    #[account(
        token::mint = config.mint,
    )]
    pub recovery_account: InterfaceAccount<'info, token_interface::TokenAccount>,

    system_program: Program<'info, System>,
}

pub fn initialize_recovery_account(ctx: Context<InitializeRecoveryAccount>) -> Result<()> {
    // This is the most important instruction to check the feature flag, as the
    // other instructions cannot be called if the [`RecoveryAccount`] is not
    // initialized anyway.
    ensure_feature_enabled()?;

    ctx.accounts.recovery.set_inner(RecoveryAccount {
        bump: ctx.bumps.recovery,
        recovery_address: ctx.accounts.recovery_account.key(),
    });
    Ok(())
}

#[derive(Accounts)]
pub struct UpdateRecoveryAddress<'info> {
    pub config: Account<'info, crate::config::Config>,

    #[account(
        constraint = owner.key() == config.owner
    )]
    pub owner: Signer<'info>,

    #[account(mut)]
    pub recovery: Account<'info, RecoveryAccount>,

    #[account(
        token::mint = config.mint,
    )]
    pub new_recovery_account: InterfaceAccount<'info, token_interface::TokenAccount>,
}

pub fn update_recovery_address(ctx: Context<UpdateRecoveryAddress>) -> Result<()> {
    ensure_feature_enabled()?;

    ctx.accounts.recovery.recovery_address = ctx.accounts.new_recovery_account.key();
    Ok(())
}

#[derive(Accounts)]
pub struct RecoverMint<'info> {
    pub release_inbound_mint: ReleaseInboundMint<'info>,

    #[account(
        constraint = owner.key() == release_inbound_mint.common.config.owner,
    )]
    pub owner: Signer<'info>,

    pub recovery: Account<'info, RecoveryAccount>,

    #[account(
        mut,
        constraint = recovery_account.key() == recovery.recovery_address,
    )]
    pub recovery_account: InterfaceAccount<'info, token_interface::TokenAccount>,
}

pub fn recover_mint<'info>(
    ctx: Context<'_, '_, '_, 'info, RecoverMint<'info>>,
    args: ReleaseInboundArgs,
) -> Result<()> {
    ensure_feature_enabled()?;

    let accounts = &mut ctx.accounts.release_inbound_mint;
    accounts.common.recipient = ctx.accounts.recovery_account.clone();
    let ctx = Context {
        accounts,
        bumps: ctx.bumps.release_inbound_mint,
        ..ctx
    };
    release_inbound_mint(ctx, args)
}

#[derive(Accounts)]
pub struct RecoverUnlock<'info> {
    pub release_inbound_unlock: ReleaseInboundUnlock<'info>,

    #[account(
        constraint = owner.key() == release_inbound_unlock.common.config.owner,
    )]
    pub owner: Signer<'info>,

    pub recovery: Account<'info, RecoveryAccount>,

    #[account(
        mut,
        constraint = recovery_account.key() == recovery.recovery_address,
    )]
    pub recovery_account: InterfaceAccount<'info, token_interface::TokenAccount>,
}

pub fn recover_unlock<'info>(
    ctx: Context<'_, '_, '_, 'info, RecoverUnlock<'info>>,
    args: ReleaseInboundArgs,
) -> Result<()> {
    ensure_feature_enabled()?;

    let accounts = &mut ctx.accounts.release_inbound_unlock;
    accounts.common.recipient = ctx.accounts.recovery_account.clone();
    let ctx = Context {
        accounts,
        bumps: ctx.bumps.release_inbound_unlock,
        ..ctx
    };
    release_inbound_unlock(ctx, args)
}

fn ensure_feature_enabled() -> Result<()> {
    #[cfg(not(feature = "owner-recovery"))]
    return Err(crate::error::NTTError::FeatureNotEnabled.into());
    #[cfg(feature = "owner-recovery")]
    return Ok(());
}
