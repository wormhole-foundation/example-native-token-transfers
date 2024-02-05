use anchor_lang::{prelude::*, solana_program::clock};

use crate::{chain_id::ChainId, error::NTTError, normalized_amount::NormalizedAmount};

use super::rate_limit::RateLimitState;

#[account]
#[derive(InitSpace)]
// TODO: generalise this to arbitrary outbound messages (via a generic parameter in place of amount and recipient info)
pub struct OutboxItem {
    pub bump: u8,
    pub sequence: u64,
    pub amount: NormalizedAmount,
    pub recipient_chain: ChainId,
    // TODO: revise max length?
    #[max_len(120)]
    pub recipient_address: Vec<u8>,
    pub release_timestamp: i64,
    // TODO: change this to a bitmap to store which endpoints have released the
    // transfer? (multi endpoint)
    pub released: bool,
}

impl OutboxItem {
    pub const SEED_PREFIX: &'static [u8] = b"outbox_item";

    pub fn release(&mut self) -> Result<()> {
        let now = clock::Clock::get()?.unix_timestamp;
        if self.release_timestamp > now {
            return Err(NTTError::ReleaseTimestampNotReached.into());
        }

        if self.released {
            return Err(NTTError::MessageAlreadySent.into());
        }

        self.released = true;

        Ok(())
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
