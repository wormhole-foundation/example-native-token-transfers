use anchor_lang::prelude::*;

pub mod chain_id;
pub mod clock;
pub mod config;
pub mod error;
pub mod instructions;
pub mod messages;
pub mod normalized_amount;
pub mod queue;
pub mod sequence;
pub mod sibling;

use instructions::*;

declare_id!("CjjU6T8ZowfYmK3bDrb5k8TdTSQxCMnhZz1xFXUwUYsn");

#[program]
pub mod example_native_token_transfers {

    use super::*;

    pub fn initialize(ctx: Context<Initialize>, args: InitializeArgs) -> Result<()> {
        instructions::initialize(ctx, args)
    }

    pub fn transfer(ctx: Context<Transfer>, args: TransferArgs) -> Result<()> {
        instructions::transfer(ctx, args)
    }

    pub fn release_outbound(
        ctx: Context<ReleaseOutbound>,
        args: ReleaseOutboundArgs,
    ) -> Result<()> {
        instructions::release_outbound(ctx, args)
    }

    pub fn redeem(ctx: Context<Redeem>, args: RedeemArgs) -> Result<()> {
        instructions::redeem(ctx, args)
    }

    pub fn release_inbound(ctx: Context<ReleaseInbound>, args: ReleaseInboundArgs) -> Result<()> {
        instructions::release_inbound(ctx, args)
    }

    pub fn transfer_ownership(
        ctx: Context<TransferOwnership>,
        args: TransferOwnershipArgs,
    ) -> Result<()> {
        instructions::transfer_ownership(ctx, args)
    }

    pub fn claim_ownership(ctx: Context<ClaimOwnership>) -> Result<()> {
        instructions::claim_ownership(ctx)
    }

    pub fn set_sibling(ctx: Context<SetSibling>, args: SetSiblingArgs) -> Result<()> {
        instructions::set_sibling(ctx, args)
    }

    pub fn set_outbound_limit(
        ctx: Context<SetOutboundLimit>,
        args: SetOutboundLimitArgs,
    ) -> Result<()> {
        instructions::set_outbound_limit(ctx, args)
    }

    pub fn set_inbound_limit(
        ctx: Context<SetInboundLimit>,
        args: SetInboundLimitArgs,
    ) -> Result<()> {
        instructions::set_inbound_limit(ctx, args)
    }
}
