#[cfg(feature = "anchor")]
use anchor_lang::prelude::*;

#[cfg(feature = "anchor")]
pub trait MaybeSpace: Space {}
#[cfg(feature = "anchor")]
impl<A: Space> MaybeSpace for A {}

#[cfg(not(feature = "anchor"))]
pub trait MaybeSpace {}
#[cfg(not(feature = "anchor"))]
impl<A> MaybeSpace for A {}
