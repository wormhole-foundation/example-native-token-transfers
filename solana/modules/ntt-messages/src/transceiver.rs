use core::fmt;
use std::{io, marker::PhantomData};

#[cfg(feature = "anchor")]
use anchor_lang::prelude::*;

use wormhole_io::{Readable, TypePrefixedPayload, Writeable};

use crate::{manager::ManagerMessage, utils::maybe_space::MaybeSpace};

pub trait Transceiver {
    const PREFIX: [u8; 4];
}

#[derive(Debug, PartialEq, Eq, Clone)]
#[cfg_attr(
    feature = "anchor",
    derive(AnchorSerialize, AnchorDeserialize, InitSpace)
)]
pub struct TransceiverMessageData<A: MaybeSpace> {
    pub source_manager: [u8; 32],
    pub recipient_manager: [u8; 32],
    pub manager_payload: ManagerMessage<A>,
}

#[derive(Eq, PartialEq, Clone, Debug)]
pub struct TransceiverMessage<E: Transceiver, A: MaybeSpace> {
    _phantom: PhantomData<E>,
    // TODO: check sibling registration at the manager level
    pub message_data: TransceiverMessageData<A>,
    pub transceiver_payload: Vec<u8>,
}

impl<E: Transceiver, A: MaybeSpace> std::ops::Deref for TransceiverMessage<E, A> {
    type Target = TransceiverMessageData<A>;

    fn deref(&self) -> &Self::Target {
        &self.message_data
    }
}

impl<E: Transceiver, A: MaybeSpace> std::ops::DerefMut for TransceiverMessage<E, A> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.message_data
    }
}

#[cfg(feature = "anchor")]
impl<E: Transceiver, A: TypePrefixedPayload> AnchorDeserialize for TransceiverMessage<E, A>
where
    A: MaybeSpace,
{
    fn deserialize_reader<R: io::Read>(reader: &mut R) -> io::Result<Self> {
        Readable::read(reader)
    }
}

#[cfg(feature = "anchor")]
impl<E: Transceiver, A: TypePrefixedPayload> AnchorSerialize for TransceiverMessage<E, A>
where
    A: MaybeSpace,
{
    fn serialize<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        Writeable::write(self, writer)
    }
}

impl<E: Transceiver, A> TransceiverMessage<E, A>
where
    A: MaybeSpace,
{
    pub fn new(
        source_manager: [u8; 32],
        recipient_manager: [u8; 32],
        manager_payload: ManagerMessage<A>,
        transceiver_payload: Vec<u8>,
    ) -> Self {
        Self {
            _phantom: PhantomData,
            message_data: TransceiverMessageData {
                source_manager,
                recipient_manager,
                manager_payload,
            },
            transceiver_payload,
        }
    }
}

impl<A: TypePrefixedPayload, E: Transceiver + Clone + fmt::Debug> TypePrefixedPayload
    for TransceiverMessage<E, A>
where
    A: MaybeSpace + Clone,
{
    const TYPE: Option<u8> = None;
}

impl<E: Transceiver, A: TypePrefixedPayload> Readable for TransceiverMessage<E, A>
where
    A: MaybeSpace,
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
                "Invalid prefix for TransceiverMessage",
            ));
        }

        let source_manager = Readable::read(reader)?;
        let recipient_manager = Readable::read(reader)?;
        // TODO: we need a way to easily check that decoding the payload
        // consumes the expected amount of bytes
        let _manager_payload_len: u16 = Readable::read(reader)?;
        let manager_payload = ManagerMessage::read(reader)?;
        let transceiver_payload_len: u16 = Readable::read(reader)?;
        let mut transceiver_payload = vec![0; transceiver_payload_len as usize];
        reader.read_exact(&mut transceiver_payload)?;

        Ok(TransceiverMessage::new(
            source_manager,
            recipient_manager,
            manager_payload,
            transceiver_payload,
        ))
    }
}

impl<E: Transceiver, A: TypePrefixedPayload> Writeable for TransceiverMessage<E, A>
where
    A: MaybeSpace,
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
        let TransceiverMessage {
            _phantom,
            message_data:
                TransceiverMessageData {
                    source_manager,
                    recipient_manager,
                    manager_payload,
                },
            transceiver_payload,
        } = self;

        E::PREFIX.write(writer)?;
        source_manager.write(writer)?;
        recipient_manager.write(writer)?;
        let len: u16 = u16::try_from(manager_payload.written_size()).expect("u16 overflow");
        len.write(writer)?;
        // TODO: review this in wormhole-io. The written_size logic is error prone. Instead,
        // a better API would be
        // foo.write_with_prefix_be::<u16>(writer)
        // which writes the length as a big endian u16.
        manager_payload.write(writer)?;
        let len: u16 = u16::try_from(transceiver_payload.len()).expect("u16 overflow");
        len.write(writer)?;
        writer.write_all(transceiver_payload)?;
        Ok(())
    }
}

#[cfg(test)]
mod test {
    use crate::{
        chain_id::ChainId, normalized_amount::NormalizedAmount, ntt::NativeTokenTransfer,
        transceivers::wormhole::WormholeTransceiver,
    };

    use super::*;
    //
    #[test]
    fn test_deserialize_transceiver_message() {
        let data = hex::decode("9945ff10042942fafabe0000000000000000000000000000000000000000000000000000042942fababe00000000000000000000000000000000000000000000000000000079000000367999a1014667921341234300000000000000000000000000000000000000000000000000004f994e545407000000000012d687beefface00000000000000000000000000000000000000000000000000000000feebcafe0000000000000000000000000000000000000000000000000000000000110000").unwrap();
        let mut vec = &data[..];
        let message: TransceiverMessage<WormholeTransceiver, NativeTokenTransfer> =
            TypePrefixedPayload::read_payload(&mut vec).unwrap();

        let expected = TransceiverMessage {
            _phantom: PhantomData::<WormholeTransceiver>,
            message_data: TransceiverMessageData {
                source_manager: [
                    0x04, 0x29, 0x42, 0xFA, 0xFA, 0xBE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                ],
                recipient_manager: [
                    0x04, 0x29, 0x42, 0xFA, 0xBA, 0xBE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
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
            transceiver_payload: vec![],
        };
        assert_eq!(message, expected);
        assert_eq!(vec.len(), 0);

        let encoded = TypePrefixedPayload::to_vec_payload(&expected);
        assert_eq!(encoded, data);
    }
}
