use anchor_lang::{prelude::*, solana_program::clock};
use anchor_spl::token::{self, Token};

use crate::{config::Config, error::NTTError, queue::inbound::InboundQueuedTransfer};

#[derive(Accounts)]
pub struct ReleaseInbound<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: Account<'info, Config>,

    #[account(
        mut,
        constraint = !enqueued.released @ NTTError::TransferAlreadyRedeemed,
    )]
    pub enqueued: Account<'info, InboundQueuedTransfer>,

    #[account(
        mut,
        address = enqueued.recipient_address,
    )]
    /// CHECK: the address is checked to match th recipient address in the
    /// queued transfer
    pub recipient: AccountInfo<'info>,

    #[account(
        mut,
        address = config.mint,
    )]
    /// CHECK: the mint address matches the config
    pub mint: AccountInfo<'info>,

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
    let enqueued = &mut ctx.accounts.enqueued;

    let now = clock::Clock::get()?.unix_timestamp;

    if enqueued.release_timestamp > now {
        return Err(NTTError::ReleaseTimestampNotReached.into());
    }

    enqueued.released = true;

    token::mint_to(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            token::MintTo {
                mint: ctx.accounts.mint.clone(),
                to: ctx.accounts.recipient.clone(),
                authority: ctx.accounts.mint_authority.clone(),
            },
            &[&[b"token_minter", &[ctx.bumps["token_minter"]]]],
        ),
        enqueued.amount,
    )
}
