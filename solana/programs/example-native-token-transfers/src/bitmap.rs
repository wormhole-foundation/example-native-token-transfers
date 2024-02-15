use anchor_lang::prelude::*;
use bitmaps::Bitmap as BM;

#[derive(PartialEq, Eq, Clone, Copy, Debug, AnchorDeserialize, AnchorSerialize, InitSpace)]
pub struct Bitmap {
    map: u128,
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

    pub fn count_ones(&self) -> u8 {
        BM::<128>::from_value(self.map).len().try_into().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bitmap() {
        let mut bm = Bitmap::new();
        assert_eq!(bm.count_ones(), 0);
        bm.set(0, true);
        assert_eq!(bm.count_ones(), 1);
        assert_eq!(bm.get(0), true);
        assert_eq!(bm.get(1), false);
        bm.set(1, true);
        assert_eq!(bm.count_ones(), 2);
        assert_eq!(bm.get(0), true);
        assert_eq!(bm.get(1), true);
        bm.set(0, false);
        assert_eq!(bm.count_ones(), 1);
        assert_eq!(bm.get(0), false);
        assert_eq!(bm.get(1), true);
        bm.set(18, true);
        assert_eq!(bm.count_ones(), 2);
    }
}
