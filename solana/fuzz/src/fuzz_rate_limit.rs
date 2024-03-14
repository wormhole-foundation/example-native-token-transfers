use honggfuzz::fuzz;
use example_native_token_transfers::queue::rate_limit::RateLimitState;
use example_native_token_transfers::clock::{current_timestamp, set_test_timestamp};

fn main() {
   loop {
      fuzz!(|input: (u64, u64, u64, i64)| {
         let limit = input.0;
         let capacity_at_last_tx = input.1;
         let new_limit = input.2;
         let old_timestamp = input.3;
         //
         // if last_tx_timestamp.is_negative() {
         //    return
         // }
         // if last_tx_timestamp.is_negative() {
         //    return
         // }
      
         // RateLimitState panics if the timestamp passed to it is in the past. Skip this case so
         // we can get to actual bugs
         let nowish = 1709829818;
         if old_timestamp > nowish { return }

         // Sets the value returned by `current_timestamp()` used by RateLimitState
         set_test_timestamp(nowish);

         let mut rls = RateLimitState{
            limit, 
            capacity_at_last_tx, 
            last_tx_timestamp: old_timestamp, // ensure the last tx is in the past
         };
      
         // This function calls `current_timestamp()`, which must never be newer than the timestamp
         // already stored in the RateLimitState
         rls.set_limit(new_limit)
      });
   }
}
