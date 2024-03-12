use anchor_lang::prelude::*;

use crate::{
  state::{
    Instance,
    RelayRequest,
  },
  error::NttQuoterError,
};

#[derive(Accounts)]
pub struct CloseRelay<'info> {
  #[account(constraint = instance.is_authorized(&authority.key()) @ NttQuoterError::NotAuthorized)]
  pub authority: Signer<'info>,

  #[account(seeds = [Instance::SEED_PREFIX], bump = Instance::BUMP)]
  pub instance: Account<'info, Instance>,

  #[account(mut, address = instance.fee_recipient @ NttQuoterError::InvalidFeeRecipient)]
  /// CHECK: leave britney alone (anchor complains about a missing check despite the address check)
  pub fee_recipient: AccountInfo<'info>,

  #[account(mut, close = fee_recipient)]
  pub relay_request: Account<'info, RelayRequest>,

  pub system_program: Program<'info, System>,
}

pub fn close_relay(_ctx: Context<CloseRelay>) -> Result<()> {
  Ok(())
}
