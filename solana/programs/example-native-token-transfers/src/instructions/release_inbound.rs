use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token};

use crate::{config::Config, error::NTTError, queue::inbox::InboxItem};

#[derive(Accounts)]
pub struct ReleaseInbound<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: Account<'info, Config>,

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
    pub recipient: AccountInfo<'info>,

    #[account(
        mut,
        address = config.mint,
    )]
    /// CHECK: the mint address matches the config
    pub mint: Account<'info, anchor_spl::token::Mint>,

    #[account(
        seeds = [b"token_minter"],
        bump,
    )]
    /// CHECK: the token program checks if this indeed the right authority for the mint
    pub mint_authority: AccountInfo<'info>,

    pub token_program: Program<'info, Token>,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct ReleaseInboundArgs {}

pub fn release_inbound(ctx: Context<ReleaseInbound>, _args: ReleaseInboundArgs) -> Result<()> {
    let inbox_item = &mut ctx.accounts.inbox_item;

    inbox_item.release()?;

    token::mint_to(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            token::MintTo {
                mint: ctx.accounts.mint.to_account_info(),
                to: ctx.accounts.recipient.clone(),
                authority: ctx.accounts.mint_authority.clone(),
            },
            &[&[b"token_minter", &[ctx.bumps.mint_authority]]],
        ),
        inbox_item.amount.denormalize(ctx.accounts.mint.decimals),
    )
}
