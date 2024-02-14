use anchor_lang::prelude::*;
use anchor_spl::token_interface;

use crate::{config::*, error::NTTError, queue::inbox::InboxItem};

#[derive(Accounts)]
pub struct ReleaseInbound<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: NotPausedConfig<'info>,

    #[account(
        mut,
        constraint = !inbox_item.released @ NTTError::TransferAlreadyRedeemed,
    )]
    pub inbox_item: Account<'info, InboxItem>,

    #[account(
        mut,
        associated_token::authority = inbox_item.recipient_address,
        associated_token::mint = mint
    )]
    pub recipient: InterfaceAccount<'info, token_interface::TokenAccount>,

    #[account(
        seeds = [b"token_authority"],
        bump,
    )]
    pub token_authority: AccountInfo<'info>,

    #[account(
        mut,
        address = config.mint,
    )]
    /// CHECK: the mint address matches the config
    pub mint: InterfaceAccount<'info, token_interface::Mint>,

    pub token_program: Interface<'info, token_interface::TokenInterface>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct ReleaseInboundArgs {
    pub revert_on_delay: bool,
}

// Burn/mint

#[derive(Accounts)]
pub struct ReleaseInboundMint<'info> {
    common: ReleaseInbound<'info>,
}

/// Release an inbound transfer and mint the tokens to the recipient.
/// When `revert_on_error` is true, the transaction will revert if the
/// release timestamp has not been reached. When `revert_on_error` is false, the
/// transaction succeeds, but the minting is not performed.
/// Setting this flag to `false` is useful when bundling this instruction
/// together with [`crate::instructions::redeem`] in a transaction, so that the minting
/// is attempted optimistically.
pub fn release_inbound_mint(
    ctx: Context<ReleaseInboundMint>,
    args: ReleaseInboundArgs,
) -> Result<()> {
    let inbox_item = &mut ctx.accounts.common.inbox_item;

    let released = inbox_item.try_release()?;

    if !released {
        if args.revert_on_delay {
            return Err(NTTError::ReleaseTimestampNotReached.into());
        } else {
            return Ok(());
        }
    }

    assert!(inbox_item.released);
    match ctx.accounts.common.config.mode {
        Mode::Burning => token_interface::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.common.token_program.to_account_info(),
                token_interface::MintTo {
                    mint: ctx.accounts.common.mint.to_account_info(),
                    to: ctx.accounts.common.recipient.to_account_info(),
                    authority: ctx.accounts.common.token_authority.clone(),
                },
                &[&[b"token_authority", &[ctx.bumps.common.token_authority]]],
            ),
            inbox_item
                .amount
                .denormalize(ctx.accounts.common.mint.decimals),
        ),
        Mode::Locking => Err(NTTError::InvalidMode.into()),
    }
}

// Lock/unlock

#[derive(Accounts)]
pub struct ReleaseInboundUnlock<'info> {
    common: ReleaseInbound<'info>,

    /// CHECK: the token program checks if this indeed the right authority for the mint
    #[account(mut)]
    pub custody: InterfaceAccount<'info, token_interface::TokenAccount>,
}

/// Release an inbound transfer and unlock the tokens to the recipient.
/// When `revert_on_error` is true, the transaction will revert if the
/// release timestamp has not been reached. When `revert_on_error` is false, the
/// transaction succeeds, but the unlocking is not performed.
/// Setting this flag to `false` is useful when bundling this instruction
/// together with [`crate::instructions::redeem`], so that the unlocking
/// is attempted optimistically.
pub fn release_inbound_unlock(
    ctx: Context<ReleaseInboundUnlock>,
    args: ReleaseInboundArgs,
) -> Result<()> {
    let inbox_item = &mut ctx.accounts.common.inbox_item;

    let released = inbox_item.try_release()?;

    if !released {
        if args.revert_on_delay {
            return Err(NTTError::ReleaseTimestampNotReached.into());
        } else {
            return Ok(());
        }
    }

    assert!(inbox_item.released);
    match ctx.accounts.common.config.mode {
        Mode::Burning => Err(NTTError::InvalidMode.into()),
        Mode::Locking => token_interface::transfer_checked(
            CpiContext::new_with_signer(
                ctx.accounts.common.token_program.to_account_info(),
                token_interface::TransferChecked {
                    from: ctx.accounts.custody.to_account_info(),
                    to: ctx.accounts.common.recipient.to_account_info(),
                    authority: ctx.accounts.common.token_authority.clone(),
                    mint: ctx.accounts.common.mint.to_account_info(),
                },
                &[&[b"token_authority", &[ctx.bumps.common.token_authority]]],
            ),
            inbox_item
                .amount
                .denormalize(ctx.accounts.common.mint.decimals),
            ctx.accounts.common.mint.decimals,
        ),
    }
}
