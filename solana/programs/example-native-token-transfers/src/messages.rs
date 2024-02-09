use anchor_lang::prelude::*;
use core::fmt;
use std::{io, marker::PhantomData, collections::HashMap};

use wormhole_io::{Readable, TypePrefixedPayload, Writeable};

use crate::{chain_id::ChainId, normalized_amount::NormalizedAmount};

// TODO: might make sense to break this up into multiple files

#[derive(Debug, Clone, PartialEq, Eq, AnchorSerialize, AnchorDeserialize)]
pub struct ManagerMessage<A> {
    pub chain_id: ChainId,
    pub sequence: u64,
    // TODO: check sibling registration at the manager level
    pub source_manager: [u8; 32],
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
        let source_manager = Readable::read(reader)?;
        let sender = Readable::read(reader)?;
        let payload = A::read_payload(reader)?;

        Ok(Self {
            chain_id,
            sequence,
            source_manager,
            sender,
            payload,
        })
    }
}

impl<A: TypePrefixedPayload> Writeable for ManagerMessage<A> {
    fn written_size(&self) -> usize {
        ChainId::SIZE.unwrap()
            + u64::SIZE.unwrap()
            + self.source_manager.len()
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
            source_manager,
            sender,
            payload,
        } = self;

        chain_id.write(writer)?;
        sequence.write(writer)?;
        writer.write_all(source_manager)?;
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

pub trait Endpoint {
    const PREFIX: [u8; 4];
}

pub struct WormholeEndpoint {}

impl Endpoint for WormholeEndpoint {
    const PREFIX: [u8; 4] = [0x99, 0x45, 0xFF, 0x10];
}

#[derive(PartialEq, Eq, AnchorSerialize, AnchorDeserialize)]
pub struct EndpointMessage<E: Endpoint, A> {
    _phantom: PhantomData<E>,
    pub manager_payload: ManagerMessage<A>,
}

impl<E, A: fmt::Debug> fmt::Debug for EndpointMessage<E, A>
where
    E: Endpoint,
{
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EndpointMessage")
            .field("manager_payload", &self.manager_payload)
            .finish()
    }
}

impl<E, A: Clone> Clone for EndpointMessage<E, A>
where
    E: Endpoint,
{
    fn clone(&self) -> Self {
        Self {
            _phantom: PhantomData,
            manager_payload: self.manager_payload.clone(),
        }
    }
}

impl<E: Endpoint, A> EndpointMessage<E, A> {
    pub fn new(manager_payload: ManagerMessage<A>) -> Self {
        Self {
            _phantom: PhantomData,
            manager_payload,
        }
    }
}

impl<A: TypePrefixedPayload, E: Endpoint> TypePrefixedPayload for EndpointMessage<E, A> {
    const TYPE: Option<u8> = None;
}

impl<E: Endpoint, A: Readable + TypePrefixedPayload> Readable for EndpointMessage<E, A> {
    const SIZE: Option<usize> = None;

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        let prefix: [u8; 4] = Readable::read(reader)?;
        if prefix != E::PREFIX {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid prefix for EndpointMessage",
            ));
        }
        let manager_payload = ManagerMessage::read(reader)?;

        Ok(EndpointMessage::new(manager_payload))
    }
}

impl<E: Endpoint, A: Writeable + TypePrefixedPayload> Writeable for EndpointMessage<E, A> {
    fn written_size(&self) -> usize {
        self.manager_payload.written_size()
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let EndpointMessage {
            _phantom,
            manager_payload,
        } = self;

        E::PREFIX.write(writer)?;
        manager_payload.write(writer)
    }
}

// This is a hack to get around the fact that the IDL generator doesn't support
// PhantomData. The generator uses the following functions, so we just mix them onto PhantomData.
//
// These types are technically more general than the actual ones, but we can't
// import the actual types from anchor-syn because that crate has a bug where it
// doesn't build against the solana bpf target (due to a missing function).
// Luckily, we don't need to reference those types, as we just want to omit PhantomData from the IDL anyway.
pub trait Hack {
    fn __anchor_private_full_path() -> String;
    fn __anchor_private_insert_idl_defined<A>(_a: &mut HashMap<String, A>);
    fn __anchor_private_gen_idl_type<A>() -> Option<A>;
}

impl<D> Hack for PhantomData<D> {
    fn __anchor_private_full_path() -> String {
        String::new()
    }
    fn __anchor_private_insert_idl_defined<A>(_a: &mut HashMap<String, A>) {}
    fn __anchor_private_gen_idl_type<A>() -> Option<A> {
        None
    }
}
