use std::num::TryFromIntError;

#[anchor_lang::prelude::error_code]
pub enum NttQuoterError {
    #[msg("Relay fees exceeds specified max")]
    ExceedsUserMaxFee = 0x1,

    #[msg("Requested gas dropoff exceeds max allowed for chain")]
    ExceedsMaxGasDropoff = 0x2,

    #[msg("The specified fee recipient does not match the address in the instance accound")]
    InvalidFeeRecipient = 0x3,

    #[msg("Relaying to the specified chain is disabled")]
    RelayingToChainDisabled = 0x4,

    #[msg("Relaying to the specified chain is disabled")]
    OutboxItemNotReleased = 0x5,

    #[msg("Scaled value exceeds u64::MAX")]
    ScalingOverflow = 0x6,

    #[msg("Cannot divide by zero")]
    DivByZero = 0x7,

    #[msg("The fee recipient cannot be the default address (0x0)")]
    FeeRecipientCannotBeDefault = 0x101,

    #[msg("Must be owner or assistant")]
    NotAuthorized = 0x102,

    #[msg("The price cannot be zero")]
    PriceCannotBeZero = 0x103,
}

impl From<TryFromIntError> for NttQuoterError {
    fn from(_: TryFromIntError) -> Self {
        Self::ScalingOverflow
    }
}
