use anchor_lang::prelude::*;

use crate::{error::NTTError, normalized_amount::NormalizedAmount};

use super::rate_limit::RateLimitState;

#[account]
#[derive(InitSpace)]
// TODO: maybe remove the queue from the name? it's not always queued
pub struct InboundQueuedTransfer {
    pub bump: u8,
    pub amount: NormalizedAmount,
    pub recipient_address: Pubkey,
    pub release_timestamp: i64,
    pub released: bool,
}

impl InboundQueuedTransfer {
    pub const SEED_PREFIX: &'static [u8] = b"inbound_queue";

    pub fn release(&mut self) -> Result<()> {
        let now = Clock::get()?.unix_timestamp;

        if self.release_timestamp > now {
            return Err(NTTError::ReleaseTimestampNotReached.into());
        }

        if self.released {
            return Err(NTTError::TransferAlreadyRedeemed.into());
        }

        self.released = true;

        Ok(())
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
    pub const SEED_PREFIX: &'static [u8] = b"inbound_rate_limit";
}
