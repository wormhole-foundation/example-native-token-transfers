use anchor_lang::prelude::*;

#[account]
#[derive(InitSpace)]
/// A sibling on another chain. Stored in a PDA seeded by the chain id.
pub struct EndpointSibling {
    pub bump: u8,
    // TODO: variable address length?
    pub address: [u8; 32],
}

impl EndpointSibling {
    pub const SEED_PREFIX: &'static [u8] = b"endpoint_sibling";
}
