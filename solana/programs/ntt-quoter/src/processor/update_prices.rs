use crate::{
    error::NttQuoterError,
    state::{Instance, RegisteredChain},
};
use anchor_lang::prelude::*;

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct UpdateSolPriceArgs {
    pub sol_price: u64, //UsdPrice (usd/sol [6 decimals])
}

#[derive(Accounts)]
pub struct UpdateSolPrice<'info> {
    #[account(constraint = instance.is_authorized(&authority.key()) @
        NttQuoterError::NotAuthorized
    )]
    pub authority: Signer<'info>,

    #[account(mut)]
    pub instance: Account<'info, Instance>,
}

pub fn update_sol_price(ctx: Context<UpdateSolPrice>, args: UpdateSolPriceArgs) -> Result<()> {
    // `sol_price` is used as a divisor in arithmetic operations so it is invalid for its value to
    // be zero.
    if args.sol_price == 0 {
        return Err(NttQuoterError::PriceCannotBeZero.into());
    }
    ctx.accounts.instance.sol_price = args.sol_price;
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct UpdateChainPricesArgs {
    pub native_price: u64, //UsdPrice (usd/target_native)
    pub gas_price: u64,    //GasPrice (wei)
}

#[derive(Accounts)]
pub struct UpdateChainPrices<'info> {
    #[account(constraint = instance.is_authorized(&authority.key()) @ NttQuoterError::NotAuthorized)]
    pub authority: Signer<'info>,

    pub instance: Account<'info, Instance>,

    #[account(mut)]
    pub registered_chain: Account<'info, RegisteredChain>,
}

pub fn update_chain_prices(
    ctx: Context<UpdateChainPrices>,
    args: UpdateChainPricesArgs,
) -> Result<()> {
    ctx.accounts.registered_chain.native_price = args.native_price;
    ctx.accounts.registered_chain.gas_price = args.gas_price;
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct UpdateChainParamsArgs {
    pub max_gas_dropoff: u64, //NativeAmount (gwei)
    pub base_price: u64,      //UsdPrice
}

#[derive(Accounts)]
pub struct UpdateChainParams<'info> {
    #[account(constraint = instance.is_authorized(&authority.key()) @ NttQuoterError::NotAuthorized)]
    pub authority: Signer<'info>,

    pub instance: Account<'info, Instance>,

    #[account(mut)]
    pub registered_chain: Account<'info, RegisteredChain>,
}

pub fn update_chain_params(
    ctx: Context<UpdateChainParams>,
    args: UpdateChainParamsArgs,
) -> Result<()> {
    ctx.accounts.registered_chain.max_gas_dropoff = args.max_gas_dropoff;
    ctx.accounts.registered_chain.base_price = args.base_price;
    Ok(())
}
