use std::ops::{Deref, DerefMut};

use anchor_lang::prelude::*;

use crate::{bitmap::Bitmap, chain_id::ChainId};

#[account]
#[derive(InitSpace)]
pub struct Config {
    pub bump: u8,
    /// Owner of the program.
    pub owner: Pubkey,
    /// Pending next owner (before claiming ownership).
    pub pending_owner: Option<Pubkey>,
    /// Mint address of the token managed by this program.
    pub mint: Pubkey,
    /// Address of the token program (token or token22). This could always be queried
    /// from the [`mint`] account's owner, but storing it here avoids an indirection
    /// on the client side.
    pub token_program: Pubkey,
    /// The mode that this program is running in. This is used to determine
    /// whether the program is burning tokens or locking tokens.
    pub mode: Mode,
    /// The chain id of the chain that this program is running on. We don't
    /// hardcode this so that the program is deployable on any potential SVM
    /// forks.
    pub chain_id: ChainId,
    /// The next endpoint id to use when registering an endpoint.
    pub next_endpoint_id: u8,
    /// The number of endpoints that must attest to a transfer before it is
    /// accepted.
    pub threshold: u8,
    /// Bitmap of enabled endpoints
    pub enabled_endpoints: Bitmap,
    /// Pause the program. This is useful for upgrades and other maintenance.
    pub paused: bool,
}

impl Config {
    pub const SEED_PREFIX: &'static [u8] = b"config";
}

#[derive(Accounts)]
pub struct NotPausedConfig<'info> {
    #[account(
        constraint = !config.paused @ crate::error::NTTError::Paused,
    )]
    config: Account<'info, Config>,
}

impl<'info> Deref for NotPausedConfig<'info> {
    type Target = Config;

    fn deref(&self) -> &Self::Target {
        &self.config
    }
}

impl<'info> DerefMut for NotPausedConfig<'info> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.config
    }
}

#[derive(AnchorSerialize, AnchorDeserialize, InitSpace, Clone, PartialEq, Eq, Copy)]
pub enum Mode {
    Burning,
    Locking,
}
