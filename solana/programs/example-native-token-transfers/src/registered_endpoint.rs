use std::ops::{Deref, DerefMut};

use anchor_lang::prelude::*;

#[account]
#[derive(InitSpace)]
pub struct RegisteredEndpoint {
    pub bump: u8,
    pub endpoint_address: Pubkey,
    pub enabled: bool,
}

impl RegisteredEndpoint {
    pub const SEED_PREFIX: &'static [u8] = b"registered_endpoint";
}

#[derive(Accounts)]
pub struct EnabledEndpoint<'info> {
    #[account(
        constraint = endpoint.enabled @ crate::error::NTTError::DisabledEndpoint,
        seeds = [RegisteredEndpoint::SEED_PREFIX, endpoint.endpoint_address.as_ref()],
        bump = endpoint.bump,
    )]
    pub endpoint: Account<'info, RegisteredEndpoint>,
}

impl<'info> Deref for EnabledEndpoint<'info> {
    type Target = Account<'info, RegisteredEndpoint>;

    fn deref(&self) -> &Self::Target {
        &self.endpoint
    }
}

impl<'info> DerefMut for EnabledEndpoint<'info> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.endpoint
    }
}
