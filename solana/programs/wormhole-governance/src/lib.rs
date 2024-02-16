use anchor_lang::prelude::*;

declare_id!("7kK9JyavhgE5G8oErMziHeBzZiAu3J64oLMbNf8FpG4S");

pub mod instructions;
pub mod error;

use instructions::*;

#[program]
pub mod wormhole_governance {
    use super::*;

    pub fn governance<'a, 'b, 'c, 'info>(
        ctx: Context<'a, 'b, 'c, 'info, Governance<'info>>,
    ) -> Result<()> {
        instructions::governance(ctx)
    }
}
