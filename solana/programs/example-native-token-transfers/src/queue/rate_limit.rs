use anchor_lang::{prelude::*, solana_program::clock::UnixTimestamp};

use crate::{clock::current_timestamp, normalized_amount::NormalizedAmount};

#[derive(AnchorSerialize, AnchorDeserialize, Clone, InitSpace)]
pub struct RateLimitState {
    /// The maximum capacity of the rate limiter.
    limit: NormalizedAmount,
    /// The capacity of the rate limiter at `last_tx_timestamp`.
    /// The actual current capacity is calculated in `capacity_at`, by
    /// accounting for the time that has passed since `last_tx_timestamp` and
    /// the refill rate.
    capacity_at_last_tx: NormalizedAmount,
    /// The timestamp of the last transaction that counted towards the current
    /// capacity. Transactions that exceeded the capacity do not count, they are
    /// just delayed.
    last_tx_timestamp: i64,
}

/// The result of attempting to consume from a rate limiter.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum RateLimitResult {
    /// If the rate limit is not exceeded, the transfer is immediate,
    /// and the capacity is reduced.
    Consumed,
    /// If the rate limit is exceeded, the transfer is delayed until the
    /// given timestamp.
    Delayed(UnixTimestamp),
}

impl RateLimitState {
    pub fn new(limit: NormalizedAmount) -> Self {
        Self {
            limit,
            capacity_at_last_tx: limit,
            last_tx_timestamp: 0,
        }
    }

    pub const RATE_LIMIT_DURATION: i64 = 60 * 60 * 24; // 24 hours

    /// Returns the capacity of the rate limiter.
    pub fn capacity(&self) -> NormalizedAmount {
        let now = current_timestamp();
        assert!(self.last_tx_timestamp <= now);

        let limit = self.limit.amount() as u128;

        // morally this is
        // capacity = old_capacity + (limit / rate_limit_duration) * time_passed
        //
        // but we instead write it as
        // capacity = old_capacity + (limit * time_passed) / rate_limit_duration
        // as it has better numerical stability.
        //
        // This can overflow u64 (if limit is close to u64 max), so we use u128
        // for the intermediate calculations. Theoretically it could also overflow u128
        // if limit == time_passed == u64 max, but that will take a very long time.

        let NormalizedAmount {
            amount: capacity_at_last_tx,
            decimals,
        } = self.capacity_at_last_tx;

        let calculated_capacity = {
            let time_passed = now - self.last_tx_timestamp;
            capacity_at_last_tx as u128
                + time_passed as u128 * limit / (Self::RATE_LIMIT_DURATION as u128)
        };

        NormalizedAmount::new(calculated_capacity.min(limit) as u64, decimals)
    }

    /// Computes the timestamp at which the given amount can be consumed.
    /// If it fits within the current capacity, the current timestamp is
    /// returned, and the remaining capacity is reduced.
    /// Otherwise, the timestamp at which the capacity will be available is
    /// returned.
    pub fn consume_or_delay(&mut self, amount: NormalizedAmount) -> RateLimitResult {
        let now = current_timestamp();
        let capacity = self.capacity();
        if capacity >= amount {
            self.capacity_at_last_tx = capacity - amount;
            self.last_tx_timestamp = now;
            RateLimitResult::Consumed
        } else {
            RateLimitResult::Delayed(now + Self::RATE_LIMIT_DURATION)
        }
    }

    /// Refills the capacity by the given amount.
    /// This is used to replenish the capacity via backflows.
    pub fn refill(&mut self, amount: NormalizedAmount) {
        self.capacity_at_last_tx = self
            .capacity_at_last_tx
            .saturating_add(amount)
            .min(self.limit);
        self.last_tx_timestamp = current_timestamp();
    }

    pub fn set_limit(&mut self, limit: NormalizedAmount) {
        let old_limit = self.limit;
        let current_capacity = self.capacity();

        self.limit = limit;

        let new_capacity: NormalizedAmount;
        if old_limit > limit {
            // decrease in limit,
            let diff = old_limit - limit;
            new_capacity = current_capacity.saturating_sub(diff);
        } else {
            // increase in limit
            let diff = limit - old_limit;
            new_capacity = current_capacity.saturating_add(diff);
        }

        self.capacity_at_last_tx = new_capacity.min(limit);
        self.last_tx_timestamp = current_timestamp();
    }
}

#[cfg(test)]
mod tests {
    use crate::clock::set_test_timestamp;

    use super::*;

    #[test]
    fn test_rate_limit() {
        let mut rate_limit_state = RateLimitState {
            limit: NormalizedAmount::new(100_000, 8),
            capacity_at_last_tx: NormalizedAmount::new(100_000, 8),
            last_tx_timestamp: current_timestamp(),
        };

        // consume 30k. should be immediate
        let immediately = rate_limit_state.consume_or_delay(NormalizedAmount::new(30_000, 8));

        assert_eq!(immediately, RateLimitResult::Consumed);
        assert_eq!(
            rate_limit_state.capacity(),
            NormalizedAmount::new(70_000, 8)
        );
        assert_eq!(rate_limit_state.limit, NormalizedAmount::new(100_000, 8)); // unchanged
        assert_eq!(rate_limit_state.last_tx_timestamp, current_timestamp());

        // replenish 1/4 of the limit, i.e. 25k
        set_test_timestamp(current_timestamp() + RateLimitState::RATE_LIMIT_DURATION / 4);

        assert_eq!(
            rate_limit_state.capacity(),
            NormalizedAmount::new(70_000 + 25_000, 8)
        );

        // now consume 150k. should be delayed
        let tomorrow = rate_limit_state.consume_or_delay(NormalizedAmount::new(150_000, 8));
        assert_eq!(
            tomorrow,
            RateLimitResult::Delayed(current_timestamp() + RateLimitState::RATE_LIMIT_DURATION)
        );

        // the limit is not changed, since the tx was delayed
        assert_eq!(
            rate_limit_state.capacity(),
            NormalizedAmount::new(70_000 + 25_000, 8)
        );

        // now set the limit to 50k
        rate_limit_state.set_limit(NormalizedAmount::new(50_000, 8));

        // this decreases the capacity by 50k, to 45k
        assert_eq!(
            rate_limit_state.capacity(),
            NormalizedAmount::new(45_000, 8)
        );

        // now set the limit to 100k
        rate_limit_state.set_limit(NormalizedAmount::new(100_000, 8));

        assert_eq!(
            rate_limit_state.capacity(),
            NormalizedAmount::new(95_000, 8)
        );

        // now refill 2k
        rate_limit_state.refill(NormalizedAmount::new(2_000, 8));
        assert_eq!(
            rate_limit_state.capacity(),
            NormalizedAmount::new(97_000, 8)
        );

        // now refill 50k
        rate_limit_state.refill(NormalizedAmount::new(50_000, 8));
        assert_eq!(
            rate_limit_state.capacity(),
            NormalizedAmount::new(100_000, 8)
        );
    }
}
