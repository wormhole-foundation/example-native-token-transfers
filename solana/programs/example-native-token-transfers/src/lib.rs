use anchor_lang::prelude::*;

// TODO: is there a more elegant way of checking that these 3 features are mutually exclusive?

#[cfg(all(feature = "mainnet", feature = "solana-devnet"))]
compile_error!("Cannot enable both mainnet and solana-devnet features at the same time");

#[cfg(all(feature = "mainnet", feature = "tilt-devnet"))]
compile_error!("Cannot enable both mainnet and tilt-devnet features at the same time");

#[cfg(all(feature = "solana-devnet", feature = "tilt-devnet"))]
compile_error!("Cannot enable both solana-devnet and tilt-devnet features at the same time");

pub mod bitmap;
pub mod clock;
pub mod config;
pub mod error;
pub mod instructions;
pub mod messages;
pub mod peer;
pub mod queue;
pub mod registered_transceiver;
pub mod transceivers;

use transceivers::wormhole::instructions::*;

use instructions::*;

cfg_if::cfg_if! {
    if #[cfg(feature = "tilt-devnet2")] {
        declare_id!("NTTManager222222222222222222222222222222222");
    } else if #[cfg(feature = "tilt-devnet")] {
        declare_id!("NTTManager111111111111111111111111111111111");
    } else {
        declare_id!("nttiK1SepaQt6sZ4WGW5whvc9tEnGXGxuKeptcQPCcS");
    }
}

const TOKEN_AUTHORITY_SEED: &[u8] = b"token_authority";

#[program]
pub mod example_native_token_transfers {

    use super::*;

    pub fn initialize(ctx: Context<Initialize>, args: InitializeArgs) -> Result<()> {
        instructions::initialize(ctx, args)
    }

    pub fn transfer_burn(ctx: Context<TransferBurn>, args: TransferArgs) -> Result<()> {
        instructions::transfer_burn(ctx, args)
    }

    pub fn transfer_lock(ctx: Context<TransferLock>, args: TransferArgs) -> Result<()> {
        instructions::transfer_lock(ctx, args)
    }

    pub fn redeem(ctx: Context<Redeem>, args: RedeemArgs) -> Result<()> {
        instructions::redeem(ctx, args)
    }

    pub fn release_inbound_mint(
        ctx: Context<ReleaseInboundMint>,
        args: ReleaseInboundArgs,
    ) -> Result<()> {
        instructions::release_inbound_mint(ctx, args)
    }

    pub fn release_inbound_unlock(
        ctx: Context<ReleaseInboundUnlock>,
        args: ReleaseInboundArgs,
    ) -> Result<()> {
        instructions::release_inbound_unlock(ctx, args)
    }

    pub fn transfer_ownership(ctx: Context<TransferOwnership>) -> Result<()> {
        instructions::transfer_ownership(ctx)
    }

    pub fn claim_ownership(ctx: Context<ClaimOwnership>) -> Result<()> {
        instructions::claim_ownership(ctx)
    }

    pub fn set_paused(ctx: Context<SetPaused>, pause: bool) -> Result<()> {
        instructions::set_paused(ctx, pause)
    }

    pub fn set_peer(ctx: Context<SetPeer>, args: SetPeerArgs) -> Result<()> {
        instructions::set_peer(ctx, args)
    }

    pub fn register_transceiver(ctx: Context<RegisterTransceiver>) -> Result<()> {
        instructions::register_transceiver(ctx)
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

    // standalone transceiver stuff

    pub fn set_wormhole_peer(
        ctx: Context<SetTransceiverPeer>,
        args: SetTransceiverPeerArgs,
    ) -> Result<()> {
        transceivers::wormhole::instructions::set_transceiver_peer(ctx, args)
    }

    pub fn receive_wormhole_message(ctx: Context<ReceiveMessage>) -> Result<()> {
        transceivers::wormhole::instructions::receive_message(ctx)
    }

    pub fn release_wormhole_outbound(
        ctx: Context<ReleaseOutbound>,
        args: ReleaseOutboundArgs,
    ) -> Result<()> {
        transceivers::wormhole::instructions::release_outbound(ctx, args)
    }

    pub fn broadcast_wormhole_id(ctx: Context<BroadcastId>) -> Result<()> {
        transceivers::wormhole::instructions::broadcast_id(ctx)
    }

    pub fn broadcast_wormhole_peer(
        ctx: Context<BroadcastPeer>,
        args: BroadcastPeerArgs,
    ) -> Result<()> {
        transceivers::wormhole::instructions::broadcast_peer(ctx, args)
    }
}
