use anchor_lang::prelude::*;

#[account]
#[derive(InitSpace)]
/// A sibling on another chain. Stored in a PDA seeded by the chain id.
pub struct TransceiverSibling {
    pub bump: u8,
    pub address: [u8; 32],
}

impl TransceiverSibling {
    pub const SEED_PREFIX: &'static [u8] = b"transceiver_sibling";
}
