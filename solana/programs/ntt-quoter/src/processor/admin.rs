use crate::{
    error::NttQuoterError,
    state::{Instance, RegisteredChain, RegisteredNtt},
};
use anchor_lang::prelude::*;
use wormhole_solana_utils::cpi::bpf_loader_upgradeable as bpf;

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub owner: Signer<'info>,

    #[account(
        init,
        payer = owner,
        space = 8 + Instance::INIT_SPACE,
        seeds = [Instance::SEED_PREFIX],
        bump,
    )]
    pub instance: Account<'info, Instance>,

    #[account(constraint = fee_recipient.key() != Pubkey::default() @
        NttQuoterError::FeeRecipientCannotBeDefault
    )]
    /// CHECK: leave britney alone (should this be just an argument?)
    pub fee_recipient: UncheckedAccount<'info>,

    /// We use the program data to make sure this owner is the upgrade authority (the true owner,
    /// who deployed this program).
    #[account(
        mut,
        seeds = [crate::ID.as_ref()],
        bump,
        seeds::program = bpf::BpfLoaderUpgradeable::id(),
        constraint = program_data.upgrade_authority_address == Some(*owner.key),
    )]
    pub program_data: Account<'info, ProgramData>,

    pub system_program: Program<'info, System>,
}

pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
    let instance = &mut ctx.accounts.instance;
    instance.owner = *ctx.accounts.owner.key;
    instance.fee_recipient = *ctx.accounts.fee_recipient.key;

    Ok(())
}

#[derive(Accounts)]
pub struct SetFeeRecipient<'info> {
    #[account(address = instance.owner)]
    pub owner: Signer<'info>,

    #[account(mut)]
    pub instance: Account<'info, Instance>,

    #[account(constraint = fee_recipient.key() != Pubkey::default() @
        NttQuoterError::FeeRecipientCannotBeDefault
    )]
    /// CHECK: leave britney alone (should this be just an argument?)
    pub fee_recipient: UncheckedAccount<'info>,
}

pub fn set_fee_recipient(ctx: Context<SetFeeRecipient>) -> Result<()> {
    ctx.accounts.instance.fee_recipient = ctx.accounts.fee_recipient.key();
    Ok(())
}

#[derive(Accounts)]
pub struct SetAssistant<'info> {
    #[account(address = instance.owner)]
    pub owner: Signer<'info>,

    #[account(mut)]
    pub instance: Account<'info, Instance>,

    /// CHECK: leave britney alone (should this be just an argument?)
    pub assistant: Option<UncheckedAccount<'info>>,
}

// Allow the redundant closure in arguments to map_or_else
#[allow(clippy::redundant_closure)]
pub fn set_assistant(ctx: Context<SetAssistant>) -> Result<()> {
    ctx.accounts.instance.assistant = ctx
        .accounts
        .assistant
        .as_deref()
        .map_or_else(|| Pubkey::default(), |val| val.key());
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct RegisterChainArgs {
    pub chain_id: u16,
}

#[derive(Accounts)]
#[instruction(args: RegisterChainArgs)]
pub struct RegisterChain<'info> {
    #[account(
        mut,
        constraint = instance.is_authorized(&authority.key()) @ NttQuoterError::NotAuthorized
    )]
    pub authority: Signer<'info>,

    pub instance: Account<'info, Instance>,

    #[account(
        init,
        payer = authority,
        space = 8 + RegisteredChain::INIT_SPACE,
        seeds = [RegisteredChain::SEED_PREFIX, args.chain_id.to_be_bytes().as_ref()],
        bump,
    )]
    pub registered_chain: Account<'info, RegisteredChain>,

    system_program: Program<'info, System>,
}

pub fn register_chain(ctx: Context<RegisterChain>, _args: RegisterChainArgs) -> Result<()> {
    ctx.accounts.registered_chain.bump = ctx.bumps.registered_chain;
    ctx.accounts.registered_chain.base_price = u64::MAX;
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct RegisterNttArgs {
    pub ntt_program_id: Pubkey,
    pub wormhole_transceiver_index: u8,
    pub gas_cost: u32,
}

#[derive(Accounts)]
#[instruction(args: RegisterNttArgs)]
pub struct RegisterNtt<'info> {
    #[account(
        mut,
        constraint = instance.is_authorized(&authority.key()) @ NttQuoterError::NotAuthorized
    )]
    pub authority: Signer<'info>,

    pub instance: Account<'info, Instance>,

    #[account(
        init,
        payer = authority,
        space = 8 + RegisteredNtt::INIT_SPACE,
        seeds = [RegisteredNtt::SEED_PREFIX, args.ntt_program_id.key().as_ref()],
        bump,
    )]
    pub registered_ntt: Account<'info, RegisteredNtt>,

    system_program: Program<'info, System>,
}

pub fn register_ntt(ctx: Context<RegisterNtt>, args: RegisterNttArgs) -> Result<()> {
    ctx.accounts.registered_ntt.bump = ctx.bumps.registered_ntt;
    ctx.accounts.registered_ntt.wormhole_transceiver_index = args.wormhole_transceiver_index;
    ctx.accounts.registered_ntt.gas_cost = args.gas_cost;
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct DeregisterNttArgs {
    pub ntt_program_id: Pubkey,
}

#[derive(Accounts)]
#[instruction(args: DeregisterNttArgs)]
pub struct DeregisterNtt<'info> {
    #[account(
        mut,
        constraint = instance.is_authorized(&authority.key()) @ NttQuoterError::NotAuthorized
    )]
    pub authority: Signer<'info>,

    pub instance: Account<'info, Instance>,

    #[account(
        mut,
        close = authority,
        seeds = [RegisteredNtt::SEED_PREFIX, args.ntt_program_id.key().as_ref()],
        bump = registered_ntt.bump,
    )]
    pub registered_ntt: Account<'info, RegisteredNtt>,

    system_program: Program<'info, System>,
}

pub fn deregister_ntt(_ctx: Context<DeregisterNtt>, _args: DeregisterNttArgs) -> Result<()> {
    Ok(())
}
