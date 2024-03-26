use std::fmt::{Display, Formatter};

#[derive(Debug, PartialEq)]
pub enum ScalingError {
    OverflowExponent,
    OverflowScaledAmount,
}

impl std::error::Error for ScalingError {}

impl Display for ScalingError {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        match self {
            ScalingError::OverflowExponent => write!(
                f,
                "Overflow: scaling factor exponent exceeds the max value of u64"
            ),
            ScalingError::OverflowScaledAmount => {
                write!(f, "Overflow: scaled amount exceeds the max value of u64")
            }
        }
    }
}
