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
         ScalingError::OverflowExponent => write!(f, "File not found"),
         ScalingError::OverflowScaledAmount => write!(f, "Permission denied"),
        }
    }
}

