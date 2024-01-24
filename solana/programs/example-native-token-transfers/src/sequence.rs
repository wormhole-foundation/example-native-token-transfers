use anchor_lang::prelude::*;

#[account]
#[derive(InitSpace)]
pub struct Sequence {
    pub bump: u8,
    pub sequence: u64,
}

impl Sequence {
    pub const SEED_PREFIX: &'static [u8] = b"sequence";

    pub fn next(&mut self) -> u64 {
        let next = self.sequence;
        self.sequence += 1;
        next
    }
}
