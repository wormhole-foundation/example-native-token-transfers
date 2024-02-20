use anchor_lang::prelude::*;

#[account]
#[derive(InitSpace)]
pub struct RegisteredEndpoint {
    pub bump: u8,
    pub id: u8,
    pub endpoint_address: Pubkey,
}

impl RegisteredEndpoint {
    pub const SEED_PREFIX: &'static [u8] = b"registered_endpoint";
}
