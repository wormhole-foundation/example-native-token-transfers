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
    #[msg("InvalidEndpointSibling")]
    InvalidEndpointSibling,
    #[msg("InvalidManagerSibling")]
    InvalidManagerSibling,
    #[msg("TransferAlreadyRedeemed")]
    TransferAlreadyRedeemed,
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
    #[msg("DisabledEndpoint")]
    DisabledEndpoint,
    #[msg("InvalidDeployer")]
    InvalidDeployer,
}
