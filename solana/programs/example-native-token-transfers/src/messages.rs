use anchor_lang::prelude::*;
use std::io;

use wormhole_io::{Readable, TypePrefixedPayload, Writeable};

use crate::{chain_id::ChainId, normalized_amount::NormalizedAmount};

// TODO: might make sense to break this up into multiple files

#[derive(Debug, Clone, PartialEq, Eq, AnchorSerialize, AnchorDeserialize)]
pub struct ManagerMessage<A> {
    pub chain_id: ChainId,
    pub sequence: u64,
    pub sender: [u8; 32],
    pub payload: A,
}

impl<A: TypePrefixedPayload> TypePrefixedPayload for ManagerMessage<A> {
    const TYPE: Option<u8> = None;
}

impl<A: TypePrefixedPayload> Readable for ManagerMessage<A> {
    const SIZE: Option<usize> = None;

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        let chain_id = Readable::read(reader)?;
        let sequence = Readable::read(reader)?;
        let sender = Readable::read(reader)?;
        let payload = A::read_payload(reader)?;

        Ok(Self {
            chain_id,
            sequence,
            sender,
            payload,
        })
    }
}

impl<A: TypePrefixedPayload> Writeable for ManagerMessage<A> {
    fn written_size(&self) -> usize {
        ChainId::SIZE.unwrap()
            + u64::SIZE.unwrap()
            + self.sender.len()
            + self.payload.written_size()
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let ManagerMessage {
            chain_id,
            sequence,
            sender,
            payload,
        } = self;

        chain_id.write(writer)?;
        sequence.write(writer)?;
        writer.write_all(sender)?;
        A::write_payload(payload, writer)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, AnchorSerialize, AnchorDeserialize)]
pub struct NativeTokenTransfer {
    pub amount: NormalizedAmount,
    // TODO: shouldn't we put this in the outer message?
    pub to_chain: ChainId,
    pub to: [u8; 32],
}

impl NativeTokenTransfer {
    const PREFIX: [u8; 4] = [0x99, 0x4E, 0x54, 0x54];
}

impl TypePrefixedPayload for NativeTokenTransfer {
    const TYPE: Option<u8> = None;
}

impl Readable for NativeTokenTransfer {
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
        let to_chain = Readable::read(reader)?;
        let to = Readable::read(reader)?;

        Ok(Self {
            amount,
            to,
            to_chain,
        })
    }
}

impl Writeable for NativeTokenTransfer {
    fn written_size(&self) -> usize {
        Self::PREFIX.len()
            + NormalizedAmount::SIZE.unwrap()
            + u16::SIZE.unwrap() // payload length
            + self.to.len()
            + ChainId::SIZE.unwrap()
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let NativeTokenTransfer {
            amount,
            to,
            to_chain,
        } = self;

        Self::PREFIX.write(writer)?;
        amount.write(writer)?;
        writer.write_all(to)?;
        to_chain.write(writer)?;

        Ok(())
    }
}
