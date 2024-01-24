use std::io;

use anchor_lang::prelude::*;
use wormhole_io::{Readable, Writeable};

#[derive(AnchorSerialize, AnchorDeserialize, InitSpace, Clone, Debug, PartialEq, Eq, Copy)]
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
