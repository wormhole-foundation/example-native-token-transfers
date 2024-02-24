use crate::transceiver::Transceiver;

#[derive(PartialEq, Eq, Clone, Debug)]
pub struct WormholeTransceiver {}

impl Transceiver for WormholeTransceiver {
    const PREFIX: [u8; 4] = [0x99, 0x45, 0xFF, 0x10];
}
