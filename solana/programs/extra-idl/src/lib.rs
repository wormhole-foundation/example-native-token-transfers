use anchor_lang::prelude::*;
use example_native_token_transfers::queue::inbox::TokenTransfer;
use ntt_messages::ntt::NativeTokenTransfer;

declare_id!("1izrS2eLspuoshBa4od3zPQz9aWJxT4DzKMK2wm9sGS");

#[account]
pub struct Types {
    pub token_transfer: TokenTransfer,
    pub native_token_transfer: NativeTokenTransfer,
}

#[program]
pub mod extra_idl {
    use super::*;

    pub fn types(_ctx: Context<Acc>) -> Result<()> {
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Acc<'info> {
    pub types: Account<'info, Types>,
}
