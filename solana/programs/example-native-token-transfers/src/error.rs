use anchor_lang::prelude::error_code;

#[error_code]
// TODO(csongor): rename
pub enum NTTError {
    #[msg("CantReleaseYet")]
    CantReleaseYet,
    #[msg("InvalidPendingOwner")]
    InvalidPendingOwner,
    #[msg("InvalidChainId")]
    InvalidChainId,
    #[msg("InvalidRecipientAddress")]
    InvalidRecipientAddress,
    #[msg("InvalidTransceiverPeer")]
    InvalidTransceiverPeer,
    #[msg("InvalidNttManagerPeer")]
    InvalidNttManagerPeer,
    #[msg("InvalidRecipientNttManager")]
    InvalidRecipientNttManager,
    #[msg("TransferAlreadyRedeemed")]
    TransferAlreadyRedeemed,
    #[msg("TransferCannotBeRedeemed")]
    TransferCannotBeRedeemed,
    #[msg("TransferNotApproved")]
    TransferNotApproved,
    #[msg("MessageAlreadySent")]
    MessageAlreadySent,
    #[msg("InvalidMode")]
    InvalidMode,
    #[msg("InvalidMintAuthority")]
    InvalidMintAuthority,
    #[msg("TransferExceedsRateLimit")]
    TransferExceedsRateLimit,
    #[msg("Paused")]
    Paused,
    #[msg("DisabledTransceiver")]
    DisabledTransceiver,
    #[msg("InvalidDeployer")]
    InvalidDeployer,
    #[msg("BadAmountAfterTransfer")]
    BadAmountAfterTransfer,
    #[msg("BadAmountAfterBurn")]
    BadAmountAfterBurn,
    #[msg("ZeroThreshold")]
    ZeroThreshold,
}
