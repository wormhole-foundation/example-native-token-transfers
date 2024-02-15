use crate::messages::Endpoint;


#[derive(PartialEq, Eq)]
pub struct WormholeEndpoint {}

impl Endpoint for WormholeEndpoint {
    const PREFIX: [u8; 4] = [0x99, 0x45, 0xFF, 0x10];
}
