use std::ops::{Deref, DerefMut};

use anchor_lang::prelude::*;
use ntt_messages::{chain_id::ChainId, mode::Mode};

use crate::bitmap::Bitmap;

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
    /// The next transceiver id to use when registering an transceiver.
    pub next_transceiver_id: u8,
    /// The number of transceivers that must attest to a transfer before it is
    /// accepted.
    pub threshold: u8,
    /// Bitmap of enabled transceivers
    pub enabled_transceivers: Bitmap,
    /// Pause the program. This is useful for upgrades and other maintenance.
    pub paused: bool,
    /// The custody account that holds tokens in locking mode.
    pub custody: Pubkey,
}

impl Config {
    pub const SEED_PREFIX: &'static [u8] = b"config";
}

pub mod accounts {
    pub use super::__client_accounts_not_paused_config::NotPausedConfig;
}

pub trait Pausable: Clone + AccountDeserialize + AccountSerialize + Owner {
    fn is_paused(&self) -> bool;
}

impl Pausable for Config {
    fn is_paused(&self) -> bool {
        self.paused
    }
}

pub trait IsConfig: Pausable {
    fn enabled_transceivers(&self) -> Bitmap;
    fn threshold(&self) -> u8;
    fn chain_id(&self) -> ChainId;
}

impl IsConfig for Config {
    fn enabled_transceivers(&self) -> Bitmap {
        self.enabled_transceivers
    }

    fn threshold(&self) -> u8 {
        self.threshold
    }

    fn chain_id(&self) -> ChainId {
        self.chain_id
    }
}

#[cfg(not(feature = "idl-build"))]
pub trait MaybeIdlBuild {}
#[cfg(not(feature = "idl-build"))]
impl<A> MaybeIdlBuild for A {}

#[cfg(feature = "idl-build")]
pub trait MaybeIdlBuild {}
#[cfg(feature = "idl-build")]
impl<A: anchor_lang::IdlBuild> MaybeIdlBuild for A {}

#[derive(Accounts)]
pub struct NotPausedConfig<'info, C: Pausable + MaybeIdlBuild>
{
    #[account(
        constraint = !config.is_paused() @ crate::error::NTTError::Paused,
    )]
    config: Account<'info, C>,
}

impl<'info, C: Pausable + MaybeIdlBuild> Deref for NotPausedConfig<'info, C> {
    type Target = C;

    fn deref(&self) -> &Self::Target {
        &self.config
    }
}

impl<'info, C: Pausable + MaybeIdlBuild> DerefMut for NotPausedConfig<'info, C> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.config
    }
}
