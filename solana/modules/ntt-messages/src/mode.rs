#[cfg(feature = "anchor")]
use anchor_lang::prelude::*;

use wormhole_io::{Readable, Writeable};

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
#[cfg_attr(
    feature = "anchor",
    derive(AnchorSerialize, AnchorDeserialize, InitSpace)
)]
pub enum Mode {
    Locking,
    Burning,
}

impl std::fmt::Display for Mode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Mode::Burning => write!(f, "Burning"),
            Mode::Locking => write!(f, "Locking"),
        }
    }
}

impl Readable for Mode {
    const SIZE: Option<usize> = Some(1);

    fn read<R>(reader: &mut R) -> std::io::Result<Self>
    where
        Self: Sized,
        R: std::io::Read,
    {
        let b: u8 = u8::read(reader)?;

        match b {
            0 => Ok(Mode::Locking),
            1 => Ok(Mode::Burning),
            _ => Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Invalid mode",
            )),
        }
    }
}

impl Writeable for Mode {
    fn written_size(&self) -> usize {
        Mode::SIZE.unwrap()
    }

    fn write<W>(&self, writer: &mut W) -> std::io::Result<()>
    where
        W: std::io::Write,
    {
        match self {
            Mode::Locking => 0u8.write(writer),
            Mode::Burning => 1u8.write(writer),
        }
    }
}
