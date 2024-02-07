//! Amounts represented in VAAs are capped at 8 decimals. This
//! means that any amount that's given as having more decimals is truncated to 8
//! decimals. On the way out, these amount have to be scaled back to the
//! original decimal amount. This module defines [`NormalizedAmount`], which
//! represents amounts that have been capped at 8 decimals.
//!
//! The functions [`normalize`] and [`denormalize`] take care of convertion to/from
//! this type given the original amount's decimals.

use std::{
    io,
    ops::{Add, Mul, Sub},
};

use anchor_lang::prelude::*;
use wormhole_io::{Readable, Writeable};

pub const NORMALIZED_DECIMALS: u8 = 8;

#[derive(
    Debug,
    Clone,
    Copy,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    AnchorSerialize,
    AnchorDeserialize,
    InitSpace,
)]
pub struct NormalizedAmount {
    amount: u64,
}

impl Mul for NormalizedAmount {
    type Output = Self;

    fn mul(self, rhs: Self) -> Self::Output {
        Self {
            amount: self.amount * rhs.amount,
        }
    }
}

impl Mul<u64> for NormalizedAmount {
    type Output = Self;

    fn mul(self, rhs: u64) -> Self::Output {
        Self {
            amount: self.amount * rhs,
        }
    }
}

impl Add for NormalizedAmount {
    type Output = Self;

    fn add(self, rhs: Self) -> Self::Output {
        Self {
            amount: self.amount + rhs.amount,
        }
    }
}

impl Sub for NormalizedAmount {
    type Output = Self;

    fn sub(self, rhs: Self) -> Self::Output {
        Self {
            amount: self.amount - rhs.amount,
        }
    }
}

impl NormalizedAmount {
    pub fn new(amount: u64) -> Self {
        Self { amount }
    }

    pub fn saturating_sub(self, rhs: Self) -> Self {
        Self {
            amount: self.amount.saturating_sub(rhs.amount),
        }
    }

    pub fn saturating_add(self, rhs: Self) -> Self {
        Self {
            amount: self.amount.saturating_add(rhs.amount),
        }
    }

    fn scaling_factor(decimals: u8) -> u64 {
        if decimals > NORMALIZED_DECIMALS {
            10u64.pow((decimals - NORMALIZED_DECIMALS).into())
        } else {
            1
        }
    }

    pub fn normalize(amount: u64, decimals: u8) -> NormalizedAmount {
        Self {
            amount: amount / Self::scaling_factor(decimals),
        }
    }

    pub fn denormalize(&self, decimals: u8) -> u64 {
        self.amount * Self::scaling_factor(decimals)
    }

    pub fn amount(&self) -> u64 {
        self.amount
    }
}

impl Readable for NormalizedAmount {
    const SIZE: Option<usize> = Some(8);

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        let amount = Readable::read(reader)?;
        Ok(Self { amount })
    }
}

impl Writeable for NormalizedAmount {
    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let NormalizedAmount { amount } = self;
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
