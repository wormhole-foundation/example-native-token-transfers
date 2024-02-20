use anchor_lang::prelude::*;

declare_id!("7kK9JyavhgE5G8oErMziHeBzZiAu3J64oLMbNf8FpG4S");

pub mod error;
pub mod instructions;

use instructions::*;

#[program]
pub mod wormhole_governance {
    use super::*;

    pub fn governance<'info>(ctx: Context<'_, '_, '_, 'info, Governance<'info>>) -> Result<()> {
        instructions::governance(ctx)
    }
}
