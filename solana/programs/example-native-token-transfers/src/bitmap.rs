use anchor_lang::prelude::*;
use bitmaps::Bitmap as BM;

#[derive(PartialEq, Eq, Clone, Copy, Debug, AnchorDeserialize, AnchorSerialize, InitSpace)]
pub struct Bitmap {
    map: u128,
}

impl Default for Bitmap {
    fn default() -> Self {
        Self::new()
    }
}

impl Bitmap {
    pub fn new() -> Self {
        Bitmap { map: 0 }
    }

    pub fn from_value(value: u128) -> Self {
        Bitmap { map: value }
    }

    pub fn set(&mut self, index: u8, value: bool) {
        let mut bm = BM::<128>::from_value(self.map);
        bm.set(index as usize, value);
        self.map = *bm.as_value();
    }

    pub fn get(&self, index: u8) -> bool {
        BM::<128>::from_value(self.map).get(index as usize)
    }

    pub fn count_enabled_votes(&self, enabled: Bitmap) -> u8 {
        let bm = BM::<128>::from_value(self.map) & BM::<128>::from_value(enabled.map);
        bm.len() as u8
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bitmap() {
        let mut enabled = Bitmap::from_value(u128::MAX);
        let mut bm = Bitmap::new();
        assert_eq!(bm.count_enabled_votes(enabled), 0);
        bm.set(0, true);
        assert_eq!(bm.count_enabled_votes(enabled), 1);
        assert!(bm.get(0));
        assert!(!bm.get(1));
        bm.set(1, true);
        assert_eq!(bm.count_enabled_votes(enabled), 2);
        assert!(bm.get(0));
        assert!(bm.get(1));
        bm.set(0, false);
        assert_eq!(bm.count_enabled_votes(enabled), 1);
        assert!(!bm.get(0));
        assert!(bm.get(1));
        bm.set(18, true);
        assert_eq!(bm.count_enabled_votes(enabled), 2);

        enabled.set(18, false);
        assert_eq!(bm.count_enabled_votes(enabled), 1);
    }
}
