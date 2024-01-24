use anchor_lang::prelude::*;

use crate::chain_id::ChainId;

#[account]
#[derive(InitSpace)]
pub struct Config {
    pub bump: u8,
    /// Mint address of the token managed by this program.
    pub mint: Pubkey,
    /// The mode that this program is running in. This is used to determine
    /// whether the program is burning tokens or locking tokens.
    pub mode: Mode,
    /// The chain id of the chain that this program is running on. We don't
    /// hardcode this so that the program is deployable on any potential SVM
    /// forks.
    pub chain_id: ChainId,
}

impl Config {
    pub const SEED_PREFIX: &'static [u8] = b"config";
}

#[derive(AnchorSerialize, AnchorDeserialize, InitSpace, Clone)]
pub enum Mode {
    Burning,
    Locking,
}
