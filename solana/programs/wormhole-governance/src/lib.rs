use anchor_lang::prelude::*;

declare_id!("nGoBXaR89hiCMaGtUmBdqQA2B21LwNTLsv4ZJnWNppj");

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
