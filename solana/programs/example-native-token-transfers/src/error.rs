use anchor_lang::prelude::error_code;

#[error_code]
// TODO(csongor): rename
pub enum NTTError {
    #[msg("ReleaseTimestampNotReached")]
    ReleaseTimestampNotReached,
    #[msg("InvalidChainId")]
    InvalidChainId,
    #[msg("InvalidRecipientAddress")]
    InvalidRecipientAddress,
    #[msg("InvalidSibling")]
    InvalidSibling,
    #[msg("TransferAlreadyRedeemed")]
    TransferAlreadyRedeemed,
    #[msg("MessageAlreadySent")]
    MessageAlreadySent,
    #[msg("InvalidMode")]
    InvalidMode,
}
