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
        address = inbox_item.recipient_address,
    )]
    /// CHECK: the address is checked to match the recipient address in the
    /// inbox item
    /// TODO: send to ATA?
    pub recipient: InterfaceAccount<'info, token_interface::TokenAccount>,

    #[account(
        mut,
        address = config.mint,
    )]
    /// CHECK: the mint address matches the config
    pub mint: InterfaceAccount<'info, token_interface::Mint>,

    pub token_program: Interface<'info, token_interface::TokenInterface>,
}

// Burn/mint

#[derive(Accounts)]
pub struct ReleaseInboundMint<'info> {
    common: ReleaseInbound<'info>,

    #[account(
        seeds = [b"token_minter"],
        bump,
    )]
    /// CHECK: the token program checks if this indeed the right authority for the mint
    pub mint_authority: AccountInfo<'info>,
}

pub fn release_inbound_mint(ctx: Context<ReleaseInboundMint>) -> Result<()> {
    let inbox_item = &mut ctx.accounts.common.inbox_item;

    inbox_item.release()?;

    match ctx.accounts.common.config.mode {
        Mode::Burning => token_interface::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.common.token_program.to_account_info(),
                token_interface::MintTo {
                    mint: ctx.accounts.common.mint.to_account_info(),
                    to: ctx.accounts.common.recipient.to_account_info(),
                    authority: ctx.accounts.mint_authority.clone(),
                },
                &[&[b"token_minter", &[ctx.bumps.mint_authority]]],
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

    #[account(
        seeds = [b"custody_authority"],
        bump,
    )]
    pub custody_authority: AccountInfo<'info>,

    /// CHECK: the token program checks if this indeed the right authority for the mint
    #[account(mut)]
    pub custody: InterfaceAccount<'info, token_interface::TokenAccount>,
}

pub fn release_inbound_unlock(ctx: Context<ReleaseInboundUnlock>) -> Result<()> {
    let inbox_item = &mut ctx.accounts.common.inbox_item;

    inbox_item.release()?;

    match ctx.accounts.common.config.mode {
        Mode::Burning => Err(NTTError::InvalidMode.into()),
        Mode::Locking => token_interface::transfer_checked(
            CpiContext::new_with_signer(
                ctx.accounts.common.token_program.to_account_info(),
                token_interface::TransferChecked {
                    from: ctx.accounts.custody.to_account_info(),
                    to: ctx.accounts.common.recipient.to_account_info(),
                    authority: ctx.accounts.custody_authority.clone(),
                    mint: ctx.accounts.common.mint.to_account_info(),
                },
                &[&[b"custody_authority", &[ctx.bumps.custody_authority]]],
            ),
            inbox_item
                .amount
                .denormalize(ctx.accounts.common.mint.decimals),
            ctx.accounts.common.mint.decimals,
        ),
    }
}
