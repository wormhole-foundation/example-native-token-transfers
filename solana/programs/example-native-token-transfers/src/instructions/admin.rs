use anchor_lang::prelude::*;
use anchor_spl::token_interface;

use crate::{
    chain_id::ChainId,
    config::Config,
    normalized_amount::NormalizedAmount,
    queue::{inbox::InboundRateLimit, outbox::OutboxRateLimit},
    sibling::Sibling,
};

// * Transfer ownership

#[derive(Accounts)]
pub struct TransferOwnership<'info> {
    #[account(
        has_one = owner,
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct TransferOwnershipArgs {
    pub new_owner: Pubkey,
}

pub fn transfer_ownership(
    ctx: Context<TransferOwnership>,
    args: TransferOwnershipArgs,
) -> Result<()> {
    ctx.accounts.config.pending_owner = Some(args.new_owner);
    Ok(())
}

// * Claim ownership

#[derive(Accounts)]
pub struct ClaimOwnership<'info> {
    #[account(
        mut,
        constraint = config.pending_owner == Some(new_owner.key())
    )]
    pub config: Account<'info, Config>,

    pub new_owner: Signer<'info>,
}

pub fn claim_ownership(ctx: Context<ClaimOwnership>) -> Result<()> {
    ctx.accounts.config.pending_owner = None;
    ctx.accounts.config.owner = ctx.accounts.new_owner.key();
    Ok(())
}

// * Set siblings
// TODO: update siblings? should that be a separate instruction? take timestamp
// for modification? (for total ordering)

#[derive(Accounts)]
#[instruction(args: SetSiblingArgs)]
pub struct SetSibling<'info> {
    #[account(
        has_one = owner,
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,

    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init,
        space = 8 + Sibling::INIT_SPACE,
        payer = payer,
        seeds = [Sibling::SEED_PREFIX, args.chain_id.id.to_be_bytes().as_ref()],
        bump
    )]
    pub sibling: Account<'info, Sibling>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct SetSiblingArgs {
    pub chain_id: ChainId,
    pub address: [u8; 32],
}

pub fn set_sibling(ctx: Context<SetSibling>, args: SetSiblingArgs) -> Result<()> {
    ctx.accounts.sibling.set_inner(Sibling {
        bump: ctx.bumps.sibling,
        address: args.address,
    });
    Ok(())
}

// * Limit rate adjustment
#[derive(Accounts)]
pub struct SetOutboundLimit<'info> {
    #[account(
        constraint = config.owner == owner.key()
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,

    #[account(mut)]
    pub rate_limit: Account<'info, OutboxRateLimit>,

    #[account(
        constraint = mint.key() == config.mint
    )]
    pub mint: InterfaceAccount<'info, token_interface::Mint>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct SetOutboundLimitArgs {
    pub limit: u64,
}

pub fn set_outbound_limit(
    ctx: Context<SetOutboundLimit>,
    args: SetOutboundLimitArgs,
) -> Result<()> {
    let limit = NormalizedAmount::normalize(args.limit, ctx.accounts.mint.decimals);
    ctx.accounts.rate_limit.set_limit(limit);
    Ok(())
}

#[derive(Accounts)]
#[instruction(args: SetInboundLimitArgs)]
pub struct SetInboundLimit<'info> {
    #[account(
        constraint = config.owner == owner.key()
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,

    #[account(
        mut,
        seeds = [
            InboundRateLimit::SEED_PREFIX,
            args.chain_id.id.to_be_bytes().as_ref()
        ],
        bump = rate_limit.bump
    )]
    pub rate_limit: Account<'info, InboundRateLimit>,

    #[account(
        constraint = mint.key() == config.mint
    )]
    pub mint: InterfaceAccount<'info, token_interface::Mint>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct SetInboundLimitArgs {
    pub limit: u64,
    pub chain_id: ChainId,
}

pub fn set_inbound_limit(ctx: Context<SetInboundLimit>, args: SetInboundLimitArgs) -> Result<()> {
    let limit = NormalizedAmount::normalize(args.limit, ctx.accounts.mint.decimals);
    ctx.accounts.rate_limit.set_limit(limit);
    Ok(())
}

// * Pausing
#[derive(Accounts)]
pub struct SetPaused<'info> {
    #[account(
        has_one = owner,
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,
}

pub fn set_paused(ctx: Context<SetPaused>, paused: bool) -> Result<()> {
    ctx.accounts.config.paused = paused;
    Ok(())
}
