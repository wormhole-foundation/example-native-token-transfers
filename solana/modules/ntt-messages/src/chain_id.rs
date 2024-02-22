use std::io;

#[cfg(feature = "anchor")]
use anchor_lang::prelude::*;

use wormhole_io::{Readable, Writeable};

#[derive(Clone, Debug, PartialEq, Eq, Copy)]
#[cfg_attr(
    feature = "anchor",
    derive(AnchorSerialize, AnchorDeserialize, InitSpace)
)]
pub struct ChainId {
    pub id: u16,
}

impl Readable for ChainId {
    const SIZE: Option<usize> = u16::SIZE;

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        let id = Readable::read(reader)?;

        Ok(Self { id })
    }
}

impl Writeable for ChainId {
    fn written_size(&self) -> usize {
        <u16 as Readable>::SIZE.unwrap()
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let ChainId { id } = self;
        id.write(writer)
    }
}
