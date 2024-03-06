use honggfuzz::fuzz;
use ntt_messages::trimmed_amount::TrimmedAmount;
 
fn main() {
    loop {
        fuzz!(|data: &[u8]| {
            // Manually discard data that doesn't fit our inputs.
            if data.len() != 10 { return }

            //  Convert first 8 bytes into a u64.
            let mut bytes = [0; 8];
            bytes.copy_from_slice(&data[0..8]);
            let amount = u64::from_le_bytes(bytes);

            // Use final two bytes as from and to decimals
            let from = data[8];
            let to = data[9];

            let _ = TrimmedAmount::trim(amount, from, to);
        });
    }
}
