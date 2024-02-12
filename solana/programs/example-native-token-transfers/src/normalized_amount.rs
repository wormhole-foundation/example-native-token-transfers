//! Amounts represented in VAAs are capped at 8 decimals. This
//! means that any amount that's given as having more decimals is truncated to 8
//! decimals. On the way out, these amount have to be scaled back to the
//! original decimal amount. This module defines [`NormalizedAmount`], which
//! represents amounts that have been capped at 8 decimals.
//!
//! The functions [`normalize`] and [`denormalize`] take care of convertion to/from
//! this type given the original amount's decimals.

use std::{io, ops::Sub};

use anchor_lang::prelude::*;
use wormhole_io::{Readable, Writeable};

pub const NORMALIZED_DECIMALS: u8 = 8;

#[derive(
    Debug,
    Clone,
    Copy,
    PartialEq,
    Eq,
    // TODO: manually write this and make sure the decimals are the same
    PartialOrd,
    Ord,
    AnchorSerialize,
    AnchorDeserialize,
    InitSpace,
)]
pub struct NormalizedAmount {
    pub amount: u64,
    pub decimals: u8,
}

impl Sub for NormalizedAmount {
    type Output = Self;

    fn sub(self, rhs: Self) -> Self::Output {
        assert_eq!(self.decimals, rhs.decimals);
        Self {
            amount: self.amount - rhs.amount,
            decimals: self.decimals,
        }
    }
}

impl NormalizedAmount {
    pub fn new(amount: u64, decimals: u8) -> Self {
        Self { amount, decimals }
    }

    pub fn saturating_sub(self, rhs: Self) -> Self {
        assert_eq!(self.decimals, rhs.decimals);
        Self {
            amount: self.amount.saturating_sub(rhs.amount),
            decimals: self.decimals,
        }
    }

    pub fn saturating_add(self, rhs: Self) -> Self {
        assert_eq!(self.decimals, rhs.decimals);
        Self {
            amount: self.amount.saturating_add(rhs.amount),
            decimals: self.decimals,
        }
    }

    fn scaling_factor(orig_decimals: u8, norm_decimals: u8) -> u64 {
        if orig_decimals > norm_decimals {
            10u64.pow((orig_decimals - norm_decimals).into())
        } else {
            1
        }
    }

    pub fn normalize(amount: u64, from_decimals: u8) -> NormalizedAmount {
        let to_decimals = NORMALIZED_DECIMALS.min(from_decimals);
        Self {
            amount: amount / Self::scaling_factor(from_decimals, to_decimals),
            decimals: to_decimals,
        }
    }

    pub fn denormalize(&self, to_decimals: u8) -> u64 {
        self.amount * Self::scaling_factor(to_decimals, self.decimals)
    }

    pub fn amount(&self) -> u64 {
        self.amount
    }
}

impl Readable for NormalizedAmount {
    const SIZE: Option<usize> = Some(1 + 8);

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        let decimals = Readable::read(reader)?;
        let amount = Readable::read(reader)?;
        Ok(Self { amount, decimals })
    }
}

impl Writeable for NormalizedAmount {
    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let NormalizedAmount { amount, decimals } = self;
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
    fn test_normalize() {
        assert_eq!(
            NormalizedAmount::normalize(100_000_000_000_000_000, 18).amount(),
            100_000_00
        );

        assert_eq!(
            NormalizedAmount::normalize(100_000_000_000_000_000, 7).amount(),
            100_000_000_000_000_000
        );

        assert_eq!(
            NormalizedAmount::normalize(100_555_555_555_555_555, 18).denormalize(18),
            100_555_550_000_000_000
        );
    }
}
