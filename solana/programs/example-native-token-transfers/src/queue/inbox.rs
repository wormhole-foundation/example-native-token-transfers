use std::ops::{Deref, DerefMut};

use anchor_lang::prelude::*;

use crate::{
    bitmap::Bitmap, clock::current_timestamp, error::NTTError, normalized_amount::NormalizedAmount,
};

use super::rate_limit::RateLimitState;

#[account]
#[derive(InitSpace)]
// TODO: generalise this to arbitrary inbound messages (via a generic parameter in place of amount and recipient info)
pub struct InboxItem {
    pub init: bool,
    pub bump: u8,
    pub amount: NormalizedAmount,
    pub recipient_address: Pubkey,
    pub votes: Bitmap,
    pub release_status: ReleaseStatus,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug, PartialEq, Eq, InitSpace)]
pub enum ReleaseStatus {
    NotApproved,
    ReleaseAfter(i64),
    Released,
}

impl InboxItem {
    pub const SEED_PREFIX: &'static [u8] = b"inbox_item";

    /// Attempt to release the transfer.
    /// Returns true if the transfer was released, false if it was not yet time to release it.
    pub fn try_release(&mut self) -> Result<bool> {
        let now = current_timestamp();

        match self.release_status {
            ReleaseStatus::NotApproved => Ok(false),
            ReleaseStatus::ReleaseAfter(release_timestamp) => {
                if release_timestamp > now {
                    return Ok(false);
                }
                self.release_status = ReleaseStatus::Released;
                Ok(true)
            }
            ReleaseStatus::Released => Err(NTTError::TransferAlreadyRedeemed.into()),
        }
    }
}

/// Inbound rate limit per chain.
/// SECURITY: must check the PDA (since there are multiple PDAs, namely one for each chain.)
#[account]
#[derive(InitSpace)]
pub struct InboxRateLimit {
    pub bump: u8,
    pub rate_limit: RateLimitState,
}

impl InboxRateLimit {
    pub const SEED_PREFIX: &'static [u8] = b"inbox_rate_limit";
}

impl Deref for InboxRateLimit {
    type Target = RateLimitState;
    fn deref(&self) -> &Self::Target {
        &self.rate_limit
    }
}

impl DerefMut for InboxRateLimit {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.rate_limit
    }
}
