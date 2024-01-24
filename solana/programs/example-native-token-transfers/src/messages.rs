use anchor_lang::prelude::*;
use std::io;

use wormhole_io::{Readable, TypePrefixedPayload, Writeable};

use crate::chain_id::ChainId;

// TODO: might make sense to break this up into multiple files

#[derive(Debug, Clone, PartialEq, Eq, AnchorSerialize, AnchorDeserialize)]
pub struct ManagerMessage<A> {
    pub chain_id: ChainId,
    pub sequence: u64,
    pub sender: Vec<u8>,
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
        let sender_len = u16::read(reader)?;
        let mut sender = vec![0u8; sender_len.into()];
        reader.read_exact(&mut sender)?;
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
            + u8::SIZE.unwrap()
            + u16::SIZE.unwrap() // sender length
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
        (sender.len() as u16).write(writer)?;
        writer.write_all(sender)?;
        A::write_payload(payload, writer)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, AnchorSerialize, AnchorDeserialize)]
pub struct NativeTokenTransfer {
    // TODO: should we use a U256 library here? might be pointless since we're
    // only looking at the least significant 64 bits (last since BE), and
    // requring the rest to be 0
    // TODO: change to NormalizedAmount type
    pub amount: u64,
    pub to: Vec<u8>,
    // TODO: shouldn't we put this in the outer message?
    pub to_chain: ChainId,
}

impl TypePrefixedPayload for NativeTokenTransfer {
    const TYPE: Option<u8> = Some(1);
}

impl Readable for NativeTokenTransfer {
    const SIZE: Option<usize> = None;

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        // read 0s
        let zeros: [u64; 3] = Readable::read(reader)?;
        assert_eq!(zeros, [0, 0, 0]);

        let amount = Readable::read(reader)?;
        let to_len = u16::read(reader)?;
        let mut to = vec![0u8; to_len.into()];
        reader.read_exact(&mut to)?;
        let to_chain = Readable::read(reader)?;

        Ok(Self {
            amount,
            to,
            to_chain,
        })
    }
}

impl Writeable for NativeTokenTransfer {
    fn written_size(&self) -> usize {
        <[u64; 4]>::SIZE.unwrap()
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

        // write 0s
        [0u64; 3].write(writer)?;

        amount.write(writer)?;
        (to.len() as u16).write(writer)?;
        writer.write_all(to)?;
        to_chain.write(writer)
    }
}
