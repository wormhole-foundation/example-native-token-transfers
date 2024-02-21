use anchor_lang::prelude::*;
use core::fmt;
use solana_program::keccak::Hash;
use std::{collections::HashMap, io, marker::PhantomData};

use wormhole_io::{Readable, TypePrefixedPayload, Writeable};

use crate::{chain_id::ChainId, normalized_amount::NormalizedAmount};

// TODO: might make sense to break this up into multiple files

#[derive(Debug, Clone, PartialEq, Eq, AnchorSerialize, AnchorDeserialize, InitSpace)]
pub struct ManagerMessage<A: Space> {
    pub sequence: u64,
    pub sender: [u8; 32],
    pub payload: A,
}

impl<A: Space + AnchorSerialize + fmt::Debug + TypePrefixedPayload> ManagerMessage<A> {
    pub fn keccak256(&self) -> Hash {
        let payload = TypePrefixedPayload::to_vec_payload(self);
        solana_program::keccak::hash(&payload)
    }
}

impl<A: TypePrefixedPayload + Space> TypePrefixedPayload for ManagerMessage<A> {
    const TYPE: Option<u8> = None;
}

impl<A: TypePrefixedPayload + Space> Readable for ManagerMessage<A> {
    const SIZE: Option<usize> = None;

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        let sequence = Readable::read(reader)?;
        let sender = Readable::read(reader)?;
        // TODO: same as below for manager payload
        let _payload_len: u16 = Readable::read(reader)?;
        let payload = A::read_payload(reader)?;

        Ok(Self {
            sequence,
            sender,
            payload,
        })
    }
}

impl<A: TypePrefixedPayload + Space> Writeable for ManagerMessage<A> {
    fn written_size(&self) -> usize {
        u64::SIZE.unwrap()
            + self.sender.len()
            + u16::SIZE.unwrap() // payload length
            + self.payload.written_size()
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let ManagerMessage {
            sequence,
            sender,
            payload,
        } = self;

        sequence.write(writer)?;
        writer.write_all(sender)?;
        let len: u16 = u16::try_from(payload.written_size()).expect("u16 overflow");
        len.write(writer)?;
        // TODO: same as above
        A::write_payload(payload, writer)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, AnchorSerialize, AnchorDeserialize, InitSpace)]
pub struct NativeTokenTransfer {
    pub amount: NormalizedAmount,
    // TODO: is this needed?
    pub source_token: [u8; 32],
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
        let source_token = Readable::read(reader)?;
        let to = Readable::read(reader)?;
        let to_chain = Readable::read(reader)?;

        Ok(Self {
            amount,
            source_token,
            to,
            to_chain,
        })
    }
}

impl Writeable for NativeTokenTransfer {
    fn written_size(&self) -> usize {
        Self::PREFIX.len()
            + NormalizedAmount::SIZE.unwrap()
            + self.source_token.len()
            + self.to.len()
            + ChainId::SIZE.unwrap()
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
        } = self;

        Self::PREFIX.write(writer)?;
        amount.write(writer)?;
        source_token.write(writer)?;
        to.write(writer)?;
        to_chain.write(writer)?;

        Ok(())
    }
}

pub trait Endpoint {
    const PREFIX: [u8; 4];
}

#[account]
#[derive(InitSpace)]
pub struct ValidatedEndpointMessage<A: AnchorDeserialize + AnchorSerialize + Space + Clone> {
    pub from_chain: ChainId,
    pub message: EndpointMessageData<A>,
}

impl<A: AnchorDeserialize + AnchorSerialize + Space + Clone> ValidatedEndpointMessage<A> {
    pub const SEED_PREFIX: &'static [u8] = b"endpoint_message";
}

#[derive(Debug, PartialEq, Eq, InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct EndpointMessageData<A: AnchorDeserialize + AnchorSerialize + Space + Clone> {
    pub source_manager: [u8; 32],
    pub manager_payload: ManagerMessage<A>,
}

#[derive(Eq, PartialEq)]
pub struct EndpointMessage<E: Endpoint, A: AnchorDeserialize + AnchorSerialize + Space + Clone> {
    _phantom: PhantomData<E>,
    // TODO: check sibling registration at the manager level
    pub message_data: EndpointMessageData<A>,
}

impl<E: Endpoint, A: AnchorDeserialize + AnchorSerialize + Space + Clone> std::ops::Deref
    for EndpointMessage<E, A>
{
    type Target = EndpointMessageData<A>;

    fn deref(&self) -> &Self::Target {
        &self.message_data
    }
}

impl<E: Endpoint, A: AnchorDeserialize + AnchorSerialize + Space + Clone> std::ops::DerefMut
    for EndpointMessage<E, A>
{
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.message_data
    }
}

impl<E, A: fmt::Debug> fmt::Debug for EndpointMessage<E, A>
where
    E: Endpoint,
    A: AnchorDeserialize + AnchorSerialize + Space + Clone,
{
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EndpointMessage")
            .field("manager_payload", &self.manager_payload)
            .finish()
    }
}

impl<E: Endpoint, A: TypePrefixedPayload> AnchorDeserialize for EndpointMessage<E, A>
where
    A: AnchorDeserialize + AnchorSerialize + Space,
{
    fn deserialize_reader<R: io::Read>(reader: &mut R) -> io::Result<Self> {
        Readable::read(reader)
    }
}

impl<E: Endpoint, A: TypePrefixedPayload> AnchorSerialize for EndpointMessage<E, A>
where
    A: AnchorDeserialize + AnchorSerialize + Space,
{
    fn serialize<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        Writeable::write(self, writer)
    }
}

impl<E, A: Clone> Clone for EndpointMessage<E, A>
where
    E: Endpoint,
    A: AnchorDeserialize + AnchorSerialize + Space,
{
    fn clone(&self) -> Self {
        Self {
            _phantom: PhantomData,
            message_data: EndpointMessageData {
                source_manager: self.source_manager,
                manager_payload: self.manager_payload.clone(),
            },
        }
    }
}

impl<E: Endpoint, A> EndpointMessage<E, A>
where
    A: AnchorDeserialize + AnchorSerialize + Space + Clone,
{
    pub fn new(source_manager: [u8; 32], manager_payload: ManagerMessage<A>) -> Self {
        Self {
            _phantom: PhantomData,
            message_data: EndpointMessageData {
                source_manager,
                manager_payload,
            },
        }
    }
}

impl<A: TypePrefixedPayload, E: Endpoint> TypePrefixedPayload for EndpointMessage<E, A>
where
    A: AnchorDeserialize + AnchorSerialize + Space,
{
    const TYPE: Option<u8> = None;
}

impl<E: Endpoint, A: Readable + TypePrefixedPayload> Readable for EndpointMessage<E, A>
where
    A: AnchorDeserialize + AnchorSerialize + Space,
{
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

        let source_manager = Readable::read(reader)?;
        // TODO: we need a way to easily check that decoding the payload
        // consumes the expected amount of bytes
        let _manager_payload_len: u16 = Readable::read(reader)?;
        let manager_payload = ManagerMessage::read(reader)?;

        Ok(EndpointMessage::new(source_manager, manager_payload))
    }
}

impl<E: Endpoint, A: Writeable + TypePrefixedPayload> Writeable for EndpointMessage<E, A>
where
    A: AnchorDeserialize + AnchorSerialize + Space,
{
    fn written_size(&self) -> usize {
        4 // prefix
        + self.source_manager.len()
        + u16::SIZE.unwrap() // length prefix
        + self.manager_payload.written_size()
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let EndpointMessage {
            _phantom,
            message_data:
                EndpointMessageData {
                    source_manager,
                    manager_payload,
                },
        } = self;

        E::PREFIX.write(writer)?;
        source_manager.write(writer)?;
        let len: u16 = u16::try_from(manager_payload.written_size()).expect("u16 overflow");
        len.write(writer)?;
        // TODO: review this in wormhole-io. The written_size logic is error prone. Instead,
        // a better API would be
        // foo.write_with_prefix_be::<u16>(writer)
        // which writes the length as a big endian u16.
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

impl Hack for ProgramData {
    fn __anchor_private_full_path() -> String {
        String::new()
    }
    fn __anchor_private_insert_idl_defined<A>(_a: &mut HashMap<String, A>) {}
    fn __anchor_private_gen_idl_type<A>() -> Option<A> {
        None
    }
}

#[cfg(test)]
mod test {
    use crate::endpoints::wormhole::messages::WormholeEndpoint;

    use super::*;
    //
    #[test]
    fn test_deserialize_endpoint_message() {
        let data = hex::decode("9945ff10042942fafabe00000000000000000000000000000000000000000000000000000079000000367999a1014667921341234300000000000000000000000000000000000000000000000000004f994e545407000000000012d687beefface00000000000000000000000000000000000000000000000000000000feebcafe000000000000000000000000000000000000000000000000000000000011").unwrap();
        let mut vec = &data[..];
        let message: EndpointMessage<WormholeEndpoint, NativeTokenTransfer> =
            TypePrefixedPayload::read_payload(&mut vec).unwrap();

        let expected = EndpointMessage {
            _phantom: PhantomData::<WormholeEndpoint>,
            message_data: EndpointMessageData {
                source_manager: [
                    0x04, 0x29, 0x42, 0xFA, 0xFA, 0xBE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                ],
                manager_payload: ManagerMessage {
                    sequence: 233968345345,
                    sender: [
                        0x46, 0x67, 0x92, 0x13, 0x41, 0x23, 0x43, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    ],
                    payload: NativeTokenTransfer {
                        amount: NormalizedAmount {
                            amount: 1234567,
                            decimals: 7,
                        },
                        source_token: [
                            0xBE, 0xEF, 0xFA, 0xCE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        ],
                        to_chain: ChainId { id: 17 },
                        to: [
                            0xFE, 0xEB, 0xCA, 0xFE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        ],
                    },
                },
            },
        };
        assert_eq!(message, expected);
        assert_eq!(vec.len(), 0);

        let encoded = TypePrefixedPayload::to_vec_payload(&expected);
        assert_eq!(encoded, data);
    }
}
