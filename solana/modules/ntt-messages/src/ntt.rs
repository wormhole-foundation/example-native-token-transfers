#[cfg(feature = "anchor")]
use anchor_lang::prelude::*;

use std::io;

use wormhole_io::{Readable, TypePrefixedPayload, Writeable};

use crate::{chain_id::ChainId, trimmed_amount::TrimmedAmount};

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(
    feature = "anchor",
    derive(AnchorSerialize, AnchorDeserialize, InitSpace)
)]
pub struct NativeTokenTransfer {
    pub amount: TrimmedAmount,
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
            + TrimmedAmount::SIZE.unwrap()
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
