#[cfg(feature = "anchor")]
use anchor_lang::prelude::*;

use std::io;

use wormhole_io::{Readable, TypePrefixedPayload, Writeable};

use crate::{chain_id::ChainId, trimmed_amount::TrimmedAmount, utils::maybe_space::MaybeSpace};

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(
    feature = "anchor",
    derive(AnchorSerialize, AnchorDeserialize, InitSpace)
)]
pub struct NativeTokenTransfer<A: MaybeSpace> {
    pub amount: TrimmedAmount,
    // TODO: is this needed?
    pub source_token: [u8; 32],
    // TODO: shouldn't we put this in the outer message?
    pub to_chain: ChainId,
    pub to: [u8; 32],
    pub additional_payload: A,
}

impl<A: MaybeSpace> NativeTokenTransfer<A> {
    const PREFIX: [u8; 4] = [0x99, 0x4E, 0x54, 0x54];
}

impl<A: TypePrefixedPayload + MaybeSpace> TypePrefixedPayload for NativeTokenTransfer<A> {
    const TYPE: Option<u8> = None;
}

impl<A: TypePrefixedPayload + MaybeSpace> Readable for NativeTokenTransfer<A> {
    const SIZE: Option<usize> = None;

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        let prefix: [u8; 4] = Readable::read(reader)?;
        if prefix != Self::PREFIX {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid prefix for NativeTokenTransfer",
            ));
        }

        let amount = Readable::read(reader)?;
        let source_token = Readable::read(reader)?;
        let to = Readable::read(reader)?;
        let to_chain = Readable::read(reader)?;

        if A::SIZE != Some(0) {
            // if the size is explicitly zero, this is an empty payload message
            // and the size field should be skipped
            // TODO: ditto todo in transceiver.rs
            let _additional_payload_len: u16 = Readable::read(reader)?;
        }
        let additional_payload = A::read_payload(reader)?;

        Ok(Self {
            amount,
            source_token,
            to,
            to_chain,
            additional_payload,
        })
    }
}

impl<A: TypePrefixedPayload + MaybeSpace> Writeable for NativeTokenTransfer<A> {
    fn written_size(&self) -> usize {
        Self::PREFIX.len()
            + TrimmedAmount::SIZE.unwrap()
            + self.source_token.len()
            + self.to.len()
            + ChainId::SIZE.unwrap()
            + if A::SIZE != Some(0) {
                u16::SIZE.unwrap() + self.additional_payload.written_size()
            } else {
                0
            }
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let NativeTokenTransfer {
            amount,
            source_token,
            to,
            to_chain,
            additional_payload,
        } = self;

        Self::PREFIX.write(writer)?;
        amount.write(writer)?;
        source_token.write(writer)?;
        to.write(writer)?;
        to_chain.write(writer)?;

        if A::SIZE != Some(0) {
            let len: u16 = u16::try_from(additional_payload.written_size()).expect("u16 overflow");
            len.write(writer)?;
            // TODO: ditto todo in transceiver.rs
            A::write_payload(additional_payload, writer)
        } else {
            Ok(())
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(
    feature = "anchor",
    derive(AnchorSerialize, AnchorDeserialize, InitSpace)
)]
pub struct EmptyPayload {}

impl EmptyPayload {
    const PREFIX: [u8; 0] = [];
}

impl TypePrefixedPayload for EmptyPayload {
    const TYPE: Option<u8> = None;
}

impl Readable for EmptyPayload {
    const SIZE: Option<usize> = Some(0);

    fn read<R>(_reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        Ok(Self {})
    }
}

impl Writeable for EmptyPayload {
    fn written_size(&self) -> usize {
        Self::PREFIX.len()
    }

    fn write<W>(&self, _writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        Ok(())
    }
}
