//! Amounts represented in VAAs are capped at 8 decimals. This
//! means that any amount that's given as having more decimals is truncated to 8
//! decimals. On the way out, these amount have to be scaled back to the
//! original decimal amount. This module defines [`TrimmedAmount`], which
//! represents amounts that have been capped at 8 decimals.
//!
//! The functions [`trim`] and [`untrim`] take care of convertion to/from
//! this type given the original amount's decimals.

use std::io;

#[cfg(feature = "anchor")]
use anchor_lang::prelude::*;

use wormhole_io::{Readable, Writeable};

pub const TRIMMED_DECIMALS: u8 = 8;

#[derive(Debug, Clone, Copy)]
#[cfg_attr(
    feature = "anchor",
    derive(AnchorSerialize, AnchorDeserialize, InitSpace)
)]
pub struct TrimmedAmount {
    pub amount: u64,
    pub decimals: u8,
}

impl PartialEq for TrimmedAmount {
    fn eq(&self, other: &Self) -> bool {
        assert_eq!(self.decimals, other.decimals);
        self.amount == other.amount
    }
}

impl Eq for TrimmedAmount {}

impl TrimmedAmount {
    pub fn new(amount: u64, decimals: u8) -> Self {
        Self { amount, decimals }
    }

    pub fn change_decimals(&self, new_decimals: u8) -> Self {
        if new_decimals == self.decimals {
            return *self;
        }
        Self {
            amount: self.untrim(new_decimals),
            decimals: new_decimals,
        }
    }

    fn scale(amount: u64, from_decimals: u8, to_decimals: u8) -> u64 {
        if from_decimals == to_decimals {
            return amount;
        }
        if from_decimals > to_decimals {
            amount / 10u64.pow((from_decimals - to_decimals).into())
        } else {
            amount * 10u64.pow((to_decimals - from_decimals).into())
        }
    }

    pub fn trim(amount: u64, from_decimals: u8, to_decimals: u8) -> TrimmedAmount {
        let to_decimals = TRIMMED_DECIMALS.min(from_decimals).min(to_decimals);
        Self {
            amount: Self::scale(amount, from_decimals, to_decimals),
            decimals: to_decimals,
        }
    }

    pub fn untrim(&self, to_decimals: u8) -> u64 {
        Self::scale(self.amount, self.decimals, to_decimals)
    }

    /// Removes dust from an amount, returning the the amount with the removed
    /// dust (expressed in the original decimals) and the trimmed amount.
    /// The two amounts returned are equivalent, but (potentially) expressed in
    /// different decimals.
    pub fn remove_dust(amount: &mut u64, from_decimals: u8, to_decimals: u8) -> TrimmedAmount {
        let trimmed = Self::trim(*amount, from_decimals, to_decimals);
        *amount = trimmed.untrim(from_decimals);
        trimmed
    }

    pub fn amount(&self) -> u64 {
        self.amount
    }
}

impl Readable for TrimmedAmount {
    const SIZE: Option<usize> = Some(1 + 8);

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        // The fields of this struct are intentionally read in reverse order compared to how they are declared in the
        // `TrimmedAmount` struct. This is consistent with the equivalent code in the EVM NTT implementation.
        let decimals = Readable::read(reader)?;
        let amount = Readable::read(reader)?;
        Ok(Self { amount, decimals })
    }
}

impl Writeable for TrimmedAmount {
    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let TrimmedAmount { amount, decimals } = self;
        // The fields of this struct are intentionally written in reverse order compared to how they are declared in the
        // `TrimmedAmount` struct. This is consistent with the equivalent code in the EVM NTT implementation.
        decimals.write(writer)?;
        amount.write(writer)?;

        Ok(())
    }

    fn written_size(&self) -> usize {
        Self::SIZE.unwrap()
    }
}

#[cfg(test)]
mod test {

    use super::*;

    #[test]
    fn test_trim() {
        assert_eq!(
            TrimmedAmount::trim(100_000_000_000_000_000, 18, 13).amount(),
            10_000_000
        );

        assert_eq!(
            TrimmedAmount::trim(100_000_000_000_000_000, 7, 11).amount(),
            100_000_000_000_000_000
        );

        assert_eq!(
            TrimmedAmount::trim(100_555_555_555_555_555, 18, 9).untrim(18),
            100_555_550_000_000_000
        );

        assert_eq!(
            TrimmedAmount::trim(100_555_555_555_555_555, 18, 1).untrim(18),
            100_000_000_000_000_000
        );

        assert_eq!(
            TrimmedAmount::trim(158434, 6, 3),
            TrimmedAmount {
                amount: 158,
                decimals: 3
            }
        );

        assert_eq!(
            TrimmedAmount {
                amount: 1,
                decimals: 6,
            }
            .untrim(13),
            10000000
        );
    }
}
