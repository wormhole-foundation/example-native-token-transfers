use honggfuzz::fuzz;
use ntt-messages::*;
 
fn main() {
    loop {
        fuzz!(|data: &[u8]| {
            if data.len() != 3 {return}
            if data[0] != b'h' {return}
            if data[1] != b'e' {return}
            if data[2] != b'y' {return}
            panic!("BOOM")
        });
    }
}
