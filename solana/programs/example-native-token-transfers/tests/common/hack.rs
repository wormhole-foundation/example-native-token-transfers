use anchor_lang::prelude::*;

#[derive(Debug, Default, AnchorSerialize, AnchorDeserialize, Clone)]
// TODO: copy pasted this struct as the sdk version doesn't have a working
// serializer implementation
pub struct PostedVaaHack<A: AnchorSerialize + AnchorDeserialize> {
    /// Header of the posted VAA
    pub vaa_version: u8,

    /// Level of consistency requested by the emitter
    pub consistency_level: u8,

    /// Time the vaa was submitted
    pub vaa_time: u32,

    /// Account where signatures are stored
    pub vaa_signature_account: Pubkey,

    /// Time the posted message was created
    pub submission_time: u32,

    /// Unique nonce for this message
    pub nonce: u32,

    /// Sequence number of this message
    pub sequence: u64,

    /// Emitter of the message
    pub emitter_chain: u16,

    /// Emitter of the message
    pub emitter_address: [u8; 32],

    /// Message payload
    pub payload: A,
}

impl<A: AnchorSerialize + AnchorDeserialize> AccountSerialize for PostedVaaHack<A> {
    fn try_serialize<W: std::io::Write>(&self, writer: &mut W) -> Result<()> {
        writer.write(b"vaa")?;
        Self::serialize(self, writer)?;
        Ok(())
    }
}
