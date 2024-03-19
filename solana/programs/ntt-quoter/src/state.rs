use anchor_lang::prelude::*;

#[account]
#[derive(Debug, InitSpace)]
pub struct Instance {
    pub owner: Pubkey,
    pub assistant: Pubkey,
    pub fee_recipient: Pubkey,
    pub sol_price: u64, //UsdPrice (usd/sol [6 decimals])
                        //future feature:
                        //amount of sol the user has to pay for the relayer to trigger the release of their outbox item
                        //pub release_cost: u64, //SolAmount (lamports)
}

impl Instance {
    pub const SEED_PREFIX: &'static [u8] = b"instance";

    pub fn is_authorized(&self, authority: &Pubkey) -> bool {
        self.owner == *authority || self.assistant == *authority
    }
}

#[account]
#[derive(Debug, InitSpace)]
pub struct RegisteredChain {
    pub bump: u8,
    pub max_gas_dropoff: u64, //NativeAmount (gwei)
    pub base_price: u64,      //UsdPrice
    pub native_price: u64,    //UsdPrice (usd/target_native)
    pub gas_price: u64,       //GasPrice (wei)
}

impl RegisteredChain {
    pub const SEED_PREFIX: &'static [u8] = b"registered_chain";
}

#[account]
#[derive(Debug, InitSpace)]
pub struct RegisteredNtt {
    pub bump: u8,
    pub wormhole_transceiver_index: u8,
    pub gas_cost: u32,
}

impl RegisteredNtt {
    pub const SEED_PREFIX: &'static [u8] = b"registered_ntt";
}

#[account]
#[derive(Debug, InitSpace)]
pub struct RelayRequest {
    pub requested_gas_dropoff: u64, //NativeAmount (gwei)
}

impl RelayRequest {
    pub const SEED_PREFIX: &'static [u8] = b"relay_request";
}
