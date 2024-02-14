use std::ops::{Deref, DerefMut};

use anchor_lang::prelude::*;

use crate::{
    chain_id::ChainId, clock::current_timestamp, error::NTTError,
    normalized_amount::NormalizedAmount,
};

use super::rate_limit::RateLimitState;

#[account]
#[derive(InitSpace, Debug, PartialEq, Eq)]
// TODO: generalise this to arbitrary outbound messages (via a generic parameter in place of amount and recipient info)
pub struct OutboxItem {
    pub sequence: u64,
    pub amount: NormalizedAmount,
    pub sender: Pubkey,
    pub recipient_chain: ChainId,
    pub recipient_address: [u8; 32],
    pub release_timestamp: i64,
    // TODO: change this to a bitmap to store which endpoints have released the
    // transfer? (multi endpoint)
    pub released: bool,
}

impl OutboxItem {
    /// Attempt to release the transfer.
    /// Returns true if the transfer was released, false if it was not yet time to release it.
    /// TODO: this is duplicated in inbox.rs. factor out?
    pub fn try_release(&mut self) -> Result<bool> {
        let now = current_timestamp();

        if self.release_timestamp > now {
            return Ok(false)
        }

        if self.released {
            return Err(NTTError::MessageAlreadySent.into());
        }

        self.released = true;

        Ok(true)
    }
}

#[account]
#[derive(InitSpace)]
pub struct OutboxRateLimit {
    pub rate_limit: RateLimitState,
}

/// Global rate limit for all outbound transfers to all chains.
/// NOTE: only one of this account can exist, so we don't need to check the PDA.
impl OutboxRateLimit {
    pub const SEED_PREFIX: &'static [u8] = b"outbox_rate_limit";
}

impl Deref for OutboxRateLimit {
    type Target = RateLimitState;

    fn deref(&self) -> &Self::Target {
        &self.rate_limit
    }
}

impl DerefMut for OutboxRateLimit {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.rate_limit
    }
}
