use std::ops::{Deref, DerefMut};

use anchor_lang::prelude::*;

use crate::{clock::current_timestamp, error::NTTError, normalized_amount::NormalizedAmount};

use super::rate_limit::RateLimitState;

#[account]
#[derive(InitSpace)]
// TODO: generalise this to arbitrary inbound messages (via a generic parameter in place of amount and recipient info)
pub struct InboxItem {
    pub bump: u8,
    pub amount: NormalizedAmount,
    pub recipient_address: Pubkey,
    pub release_timestamp: i64,
    pub released: bool,
}

impl InboxItem {
    pub const SEED_PREFIX: &'static [u8] = b"inbox_item";

    /// Attempt to release the transfer.
    /// Returns true if the transfer was released, false if it was not yet time to release it.
    pub fn try_release(&mut self) -> Result<bool> {
        let now = current_timestamp();

        if self.release_timestamp > now {
            return Ok(false)
        }

        if self.released {
            return Err(NTTError::TransferAlreadyRedeemed.into());
        }

        self.released = true;

        Ok(true)
    }
}

/// Inbound rate limit per chain.
/// SECURITY: must check the PDA (since there are multiple PDAs, namely one for each chain.)
#[account]
#[derive(InitSpace)]
pub struct InboundRateLimit {
    pub bump: u8,
    pub rate_limit: RateLimitState,
}

impl InboundRateLimit {
    pub const SEED_PREFIX: &'static [u8] = b"inbox_rate_limit";
}

impl Deref for InboundRateLimit {
    type Target = RateLimitState;
    fn deref(&self) -> &Self::Target {
        &self.rate_limit
    }
}

impl DerefMut for InboundRateLimit {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.rate_limit
    }
}
