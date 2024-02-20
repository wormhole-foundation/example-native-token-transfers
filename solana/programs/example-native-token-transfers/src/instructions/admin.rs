use anchor_lang::prelude::*;
use wormhole_solana_utils::cpi::bpf_loader_upgradeable::{self, BpfLoaderUpgradeable};

use crate::{
    chain_id::ChainId,
    config::Config,
    error::NTTError,
    queue::{inbox::InboxRateLimit, outbox::OutboxRateLimit, rate_limit::RateLimitState},
    registered_endpoint::RegisteredEndpoint,
    sibling::ManagerSibling,
};

// * Transfer ownership

#[derive(Accounts)]
pub struct TransferOwnership<'info> {
    #[account(
        mut,
        has_one = owner,
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,

    /// CHECK: This account will be the signer in the [claim_ownership] instruction.
    new_owner: AccountInfo<'info>,

    /// CHECK: Seeds must be \["upgrade-lock"\].
    #[account(
        seeds = [b"upgrade-lock"],
        bump,
    )]
    upgrade_lock: AccountInfo<'info>,

    #[account(
        mut,
        seeds = [crate::ID.as_ref()],
        bump,
        seeds::program = bpf_loader_upgradeable_program,
    )]
    program_data: Account<'info, ProgramData>,

    bpf_loader_upgradeable_program: Program<'info, BpfLoaderUpgradeable>,
}

pub fn transfer_ownership(ctx: Context<TransferOwnership>) -> Result<()> {
    ctx.accounts.config.pending_owner = Some(ctx.accounts.new_owner.key());

    bpf_loader_upgradeable::set_upgrade_authority_checked(
        CpiContext::new_with_signer(
            ctx.accounts
                .bpf_loader_upgradeable_program
                .to_account_info(),
            bpf_loader_upgradeable::SetUpgradeAuthorityChecked {
                program_data: ctx.accounts.program_data.to_account_info(),
                current_authority: ctx.accounts.owner.to_account_info(),
                new_authority: ctx.accounts.upgrade_lock.to_account_info(),
            },
            &[&[b"upgrade-lock", &[ctx.bumps.upgrade_lock]]],
        ),
        &crate::ID,
    )
}

// * Claim ownership

#[derive(Accounts)]
pub struct ClaimOwnership<'info> {
    #[account(
        mut,
        constraint = config.pending_owner == Some(new_owner.key()) @ NTTError::InvalidPendingOwner
    )]
    pub config: Account<'info, Config>,

    /// CHECK: Seeds must be \["upgrade-lock"\].
    #[account(
        seeds = [b"upgrade-lock"],
        bump,
    )]
    upgrade_lock: AccountInfo<'info>,

    pub new_owner: Signer<'info>,

    #[account(
        mut,
        seeds = [crate::ID.as_ref()],
        bump,
        seeds::program = bpf_loader_upgradeable_program,
    )]
    program_data: Account<'info, ProgramData>,

    bpf_loader_upgradeable_program: Program<'info, BpfLoaderUpgradeable>,
}

pub fn claim_ownership(ctx: Context<ClaimOwnership>) -> Result<()> {
    ctx.accounts.config.pending_owner = None;
    ctx.accounts.config.owner = ctx.accounts.new_owner.key();

    bpf_loader_upgradeable::set_upgrade_authority_checked(
        CpiContext::new_with_signer(
            ctx.accounts
                .bpf_loader_upgradeable_program
                .to_account_info(),
            bpf_loader_upgradeable::SetUpgradeAuthorityChecked {
                program_data: ctx.accounts.program_data.to_account_info(),
                current_authority: ctx.accounts.upgrade_lock.to_account_info(),
                new_authority: ctx.accounts.new_owner.to_account_info(),
            },
            &[&[b"upgrade-lock", &[ctx.bumps.upgrade_lock]]],
        ),
        &crate::ID,
    )
}

// * Set siblings
// TODO: update siblings? should that be a separate instruction? take timestamp
// for modification? (for total ordering)

#[derive(Accounts)]
#[instruction(args: SetSiblingArgs)]
pub struct SetSibling<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub owner: Signer<'info>,

    #[account(
        has_one = owner,
    )]
    pub config: Account<'info, Config>,

    #[account(
        init,
        space = 8 + ManagerSibling::INIT_SPACE,
        payer = payer,
        seeds = [ManagerSibling::SEED_PREFIX, args.chain_id.id.to_be_bytes().as_ref()],
        bump
    )]
    pub sibling: Account<'info, ManagerSibling>,

    #[account(
        init,
        space = 8 + InboxRateLimit::INIT_SPACE,
        payer = payer,
        seeds = [
            InboxRateLimit::SEED_PREFIX,
            args.chain_id.id.to_be_bytes().as_ref()
        ],
        bump,
    )]
    pub inbox_rate_limit: Account<'info, InboxRateLimit>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct SetSiblingArgs {
    pub chain_id: ChainId,
    pub address: [u8; 32],
    pub limit: u64,
}

pub fn set_sibling(ctx: Context<SetSibling>, args: SetSiblingArgs) -> Result<()> {
    ctx.accounts.sibling.set_inner(ManagerSibling {
        bump: ctx.bumps.sibling,
        address: args.address,
    });

    ctx.accounts.inbox_rate_limit.set_inner(InboxRateLimit {
        bump: ctx.bumps.inbox_rate_limit,
        rate_limit: RateLimitState::new(args.limit),
    });
    Ok(())
}

// * Register endpoints

#[derive(Accounts)]
pub struct RegisterEndpoint<'info> {
    #[account(
        mut,
        has_one = owner,
    )]
    pub config: Account<'info, Config>,

    pub owner: Signer<'info>,

    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(executable)]
    pub endpoint: AccountInfo<'info>,

    #[account(
        init,
        space = 8 + RegisteredEndpoint::INIT_SPACE,
        payer = payer,
        seeds = [RegisteredEndpoint::SEED_PREFIX, endpoint.key().as_ref()],
        bump
    )]
    pub registered_endpoint: Account<'info, RegisteredEndpoint>,

    pub system_program: Program<'info, System>,
}

pub fn register_endpoint(ctx: Context<RegisterEndpoint>) -> Result<()> {
    let id = ctx.accounts.config.next_endpoint_id;
    ctx.accounts.config.next_endpoint_id += 1;
    ctx.accounts
        .registered_endpoint
        .set_inner(RegisteredEndpoint {
            bump: ctx.bumps.registered_endpoint,
            id,
            endpoint_address: ctx.accounts.endpoint.key(),
        });

    ctx.accounts.config.enabled_endpoints.set(id, true);
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
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct SetOutboundLimitArgs {
    pub limit: u64,
}

pub fn set_outbound_limit(
    ctx: Context<SetOutboundLimit>,
    args: SetOutboundLimitArgs,
) -> Result<()> {
    ctx.accounts.rate_limit.set_limit(args.limit);
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
            InboxRateLimit::SEED_PREFIX,
            args.chain_id.id.to_be_bytes().as_ref()
        ],
        bump = rate_limit.bump
    )]
    pub rate_limit: Account<'info, InboxRateLimit>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct SetInboundLimitArgs {
    pub limit: u64,
    pub chain_id: ChainId,
}

pub fn set_inbound_limit(ctx: Context<SetInboundLimit>, args: SetInboundLimitArgs) -> Result<()> {
    ctx.accounts.rate_limit.set_limit(args.limit);
    Ok(())
}

// * Pausing
#[derive(Accounts)]
pub struct SetPaused<'info> {
    pub owner: Signer<'info>,

    #[account(
        mut,
        has_one = owner,
    )]
    pub config: Account<'info, Config>,
}

pub fn set_paused(ctx: Context<SetPaused>, paused: bool) -> Result<()> {
    ctx.accounts.config.paused = paused;
    Ok(())
}
