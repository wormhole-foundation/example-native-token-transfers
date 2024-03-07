use anchor_lang::{
    prelude::*,
    system_program::{self, Transfer},
};
use example_native_token_transfers::queue::outbox::OutboxItem;
use solana_program::{native_token::LAMPORTS_PER_SOL, sysvar};

use crate::{
    error::NttQuoterError,
    state::{Instance, RegisteredChain, RelayRequest},
    EVM_GAS_COST, WORMHOLE_TRANSCEIVER_INDEX,
};

#[derive(Accounts)]
pub struct RequestRelay<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(seeds = [Instance::SEED_PREFIX], bump = Instance::BUMP)]
    pub instance: Account<'info, Instance>,

    #[account(mut, address = instance.fee_recipient @ NttQuoterError::InvalidFeeRecipient)]
    /// CHECK: leave britney alone (anchor complains about a missing check despite the address check)
    pub fee_recipient: AccountInfo<'info>,

    #[account(
    seeds = [RegisteredChain::SEED_PREFIX, outbox_item.recipient_chain.id.to_be_bytes().as_ref()],
    bump = registered_chain.bump,
    constraint = registered_chain.base_price != u64::MAX @ NttQuoterError::RelayingToChainDisabled
  )]
    pub registered_chain: Account<'info, RegisteredChain>,

    //TODO eventually drop the released constraint and instead implement release by relayer
    #[account(
    owner = example_native_token_transfers::ID,
    constraint = outbox_item.released.get(WORMHOLE_TRANSCEIVER_INDEX),
  )]
    pub outbox_item: Account<'info, OutboxItem>,

    //TODO should this be init_if_needed?
    //     are there any security considerations here?
    //     init_if_needed would allow for multiple requests, even after it was already delivered
    //     right now requesting a relay for a request is permissionless which would allow
    //       a third party to initiate a relay without gas dropoff for the user (though they
    //       can just use connect and get a gas dropoff to the same wallet that way)
    #[account(
    init,
    payer = payer,
    space = 8 + RelayRequest::INIT_SPACE,
    seeds = [RelayRequest::SEED_PREFIX, outbox_item.key().as_ref()],
    bump,
  )]
    pub relay_request: Account<'info, RelayRequest>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct RequestRelayArgs {
    pub gas_dropoff: u64, //NativeAmount,
    pub max_fee: u64,     //SolAmount,
}

const GWEI: u64 = u64::pow(10, 9);

fn mul_div(scalar: u64, numerator: u64, denominator: u64) -> u64 {
    ((scalar as u128) * (numerator as u128) / (denominator as u128))
        .try_into()
        .unwrap()
}

//TODO built-in u128 division likely still wastes a ton of compute units
//     might be more efficient to use f64 or ruint crate
pub fn request_relay(ctx: Context<RequestRelay>, args: RequestRelayArgs) -> Result<()> {
    let accs = ctx.accounts;

    require_gt!(
        args.gas_dropoff,
        accs.registered_chain.max_gas_dropoff,
        NttQuoterError::ExceedsMaxGasDropoff
    );

    let total_fee_in_lamports_without_rent = {
        let target_native_in_gwei = args.gas_dropoff
            + if accs.registered_chain.gas_price > 0 {
                //gas_price[wei, 18 decimals] * EVM_GAS_COST / GWEI = target_native[gwei, 9 decimals]
                mul_div(accs.registered_chain.gas_price, EVM_GAS_COST, GWEI)
            } else {
                0
            };

        //usd/target_native[usd, 6 decimals] * target_native[gwei, 9 decimals] = usd[usd, 6 decimals]
        let target_native_in_usd = mul_div(
            accs.registered_chain.native_price,
            target_native_in_gwei,
            GWEI,
        );

        let total_in_usd = target_native_in_usd + accs.registered_chain.base_price;

        if total_in_usd > 0 {
            //total_fee[sol, 9 decimals] = total_usd[usd, 6 decimals] / (sol_price[usd, 6 decimals]
            mul_div(total_in_usd, LAMPORTS_PER_SOL, accs.instance.sol_price)
        } else {
            0
        }
    };

    let rent_in_lamports = sysvar::rent::Rent::get()?.minimum_balance(8 + RelayRequest::INIT_SPACE);
    let total_fee_in_lamports = total_fee_in_lamports_without_rent + rent_in_lamports;

    require_gte!(
        args.max_fee,
        total_fee_in_lamports,
        NttQuoterError::ExceedsUserMaxFee
    );

    msg!("total fee in lamports: {}", total_fee_in_lamports);

    //store the requested gas dropoff
    accs.relay_request.requested_gas_dropoff = args.gas_dropoff;

    //pay the relayer
    if total_fee_in_lamports_without_rent > 0 {
        system_program::transfer(
            CpiContext::new(
                accs.system_program.to_account_info(),
                Transfer {
                    from: accs.payer.to_account_info(),
                    to: accs.fee_recipient.to_account_info(),
                },
            ),
            total_fee_in_lamports_without_rent,
        )?;
    }

    Ok(())
}
