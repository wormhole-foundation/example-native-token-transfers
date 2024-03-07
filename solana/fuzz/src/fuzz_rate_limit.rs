use honggfuzz::fuzz;
use example_native_token_transfers::queue::rate_limit::RateLimitState;

// #[cfg_attr(feature = "arbitrary", derive(arbitrary::Arbitrary))]

fn main() {
    loop {
         fuzz!(|input: (u64, u64)| {
            let (limit, new_limit) = input;
            // let capacity_at_last_tx = input.1;
            // let last_tx_timestamp:i64 = input.2;

            // if last_tx_timestamp.is_negative() {
            //    return
            // }

            let mut rls = RateLimitState::new(limit);
            rls.set_limit(new_limit)
        });
    }
}
