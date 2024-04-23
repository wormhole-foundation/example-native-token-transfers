use anchor_lang::prelude::error_code;

#[error_code]
pub enum GovernanceError {
    #[msg("InvalidGovernanceChain")]
    InvalidGovernanceChain,
    #[msg("InvalidGovernanceEmitter")]
    InvalidGovernanceEmitter,
    #[msg("InvalidGovernanceProgram")]
    InvalidGovernanceProgram,
}
