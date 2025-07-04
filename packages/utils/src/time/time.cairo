use core::traits::Into;
use starkware_utils::constants::{DAY, MAX_U64, WEEK};
use starkware_utils::time::errors::TimeErrors;

pub type Seconds = u64;


pub fn validate_expiration(expiration: Timestamp, err: felt252) {
    assert(Time::now() <= expiration, err);
}

#[derive(Debug, PartialEq, Drop, Serde, Copy, starknet::Store)]
pub struct TimeDelta {
    pub seconds: Seconds,
}
impl TimeDeltaZero of core::num::traits::Zero<TimeDelta> {
    fn zero() -> TimeDelta {
        TimeDelta { seconds: 0 }
    }
    fn is_zero(self: @TimeDelta) -> bool {
        self.seconds.is_zero()
    }
    fn is_non_zero(self: @TimeDelta) -> bool {
        self.seconds.is_non_zero()
    }
}
impl TimeDeltaAdd of Add<TimeDelta> {
    fn add(lhs: TimeDelta, rhs: TimeDelta) -> TimeDelta {
        assert!((MAX_U64 - lhs.seconds) >= rhs.seconds, "{}", TimeErrors::TIMEDELTA_ADD_OVERFLOW);
        TimeDelta { seconds: lhs.seconds + rhs.seconds }
    }
}
impl TimeDeltaSub of Sub<TimeDelta> {
    fn sub(lhs: TimeDelta, rhs: TimeDelta) -> TimeDelta {
        assert!(lhs.seconds >= rhs.seconds, "{}", TimeErrors::TIMEDELTA_SUB_UNDERFLOW);
        TimeDelta { seconds: lhs.seconds - rhs.seconds }
    }
}
impl TimeDeltaIntoSeconds of Into<TimeDelta, Seconds> {
    fn into(self: TimeDelta) -> Seconds {
        self.seconds
    }
}
impl TimeDeltaPartialOrd of PartialOrd<TimeDelta> {
    fn lt(lhs: TimeDelta, rhs: TimeDelta) -> bool {
        lhs.seconds < rhs.seconds
    }
    fn le(lhs: TimeDelta, rhs: TimeDelta) -> bool {
        lhs.seconds <= rhs.seconds
    }
}


#[derive(Debug, PartialEq, Drop, Hash, Serde, Copy, starknet::Store)]
pub struct Timestamp {
    pub seconds: Seconds,
}
impl TimeStampZero of core::num::traits::Zero<Timestamp> {
    fn zero() -> Timestamp nopanic {
        Timestamp { seconds: 0 }
    }
    fn is_zero(self: @Timestamp) -> bool {
        self.seconds.is_zero()
    }
    fn is_non_zero(self: @Timestamp) -> bool {
        self.seconds.is_non_zero()
    }
}
impl TimeAddAssign of core::ops::AddAssign<Timestamp, TimeDelta> {
    fn add_assign(ref self: Timestamp, rhs: TimeDelta) {
        assert!((MAX_U64 - self.seconds) >= rhs.seconds, "{}", TimeErrors::TIMESTAMP_ADD_OVERFLOW);
        self.seconds += rhs.seconds;
    }
}
impl TimeStampPartialOrd of PartialOrd<Timestamp> {
    fn lt(lhs: Timestamp, rhs: Timestamp) -> bool {
        lhs.seconds < rhs.seconds
    }
}
impl TimeStampIntoSeconds of Into<Timestamp, Seconds> {
    fn into(self: Timestamp) -> Seconds nopanic {
        self.seconds
    }
}

#[generate_trait]
pub impl TimeImpl of Time {
    fn seconds(count: u64) -> TimeDelta nopanic {
        TimeDelta { seconds: count }
    }
    fn days(count: u64) -> TimeDelta {
        let count_u128: u128 = count.into();
        assert!(
            (count_u128 * DAY.into()) <= MAX_U64.into(), "{}", TimeErrors::TIMEDELTA_DAYS_OVERFLOW,
        );
        Self::seconds(count: count * DAY)
    }
    fn weeks(count: u64) -> TimeDelta {
        let count_u128: u128 = count.into();
        assert!(
            (count_u128 * WEEK.into()) <= MAX_U64.into(),
            "{}",
            TimeErrors::TIMEDELTA_WEEKS_OVERFLOW,
        );
        Self::seconds(count: count * WEEK)
    }
    fn now() -> Timestamp {
        Timestamp { seconds: starknet::get_block_timestamp() }
    }
    fn add(self: Timestamp, delta: TimeDelta) -> Timestamp {
        let mut value = self;
        value += delta;
        value
    }
    fn sub(self: Timestamp, other: Timestamp) -> TimeDelta {
        assert!(self.seconds >= other.seconds, "{}", TimeErrors::TIMESTAMP_SUB_UNDERFLOW);
        TimeDelta { seconds: self.seconds - other.seconds }
    }
    fn sub_delta(self: Timestamp, other: TimeDelta) -> Timestamp {
        assert!(self.seconds >= other.seconds, "{}", TimeErrors::TIMESTAMP_SUB_DELTA_UNDERFLOW);
        Timestamp { seconds: self.seconds - other.seconds }
    }
    fn div(self: TimeDelta, divider: u64) -> TimeDelta {
        assert!(divider != 0, "{}", TimeErrors::TIMEDELTA_DIV_BY_ZERO);
        TimeDelta { seconds: self.seconds / divider }
    }
}


#[cfg(test)]
mod tests {
    use core::num::traits::zero::Zero;
    use snforge_std::start_cheat_block_timestamp_global;
    use starkware_utils::constants::{DAY, WEEK};
    use super::{MAX_U64, Time, TimeDelta, Timestamp};

    #[test]
    fn test_timedelta_add() {
        let delta1 = Time::days(count: 1);
        let delta2 = Time::days(count: 2);
        let delta3 = delta1 + delta2;
        assert_eq!(delta3.seconds, delta1.seconds + delta2.seconds);
        assert_eq!(delta3.seconds, Time::days(count: 3).seconds);
    }

    #[test]
    fn test_timedelta_sub() {
        let delta1 = Time::days(count: 3);
        let delta2 = Time::days(count: 1);
        let delta3 = delta1 - delta2;
        assert_eq!(delta3.seconds, delta1.seconds - delta2.seconds);
        assert_eq!(delta3.seconds, Time::days(count: 2).seconds);
    }

    #[test]
    fn test_timedelta_zero() {
        let delta = TimeDelta { seconds: 0 };
        assert_eq!(delta, Zero::zero());
    }

    #[test]
    fn test_timedelta_is_zero() {
        let delta = TimeDelta { seconds: 0 };
        assert!(delta.is_zero());
    }

    #[test]
    fn test_timedelta_is_non_zero() {
        let delta = TimeDelta { seconds: 1 };
        assert!(delta.is_non_zero());
    }

    #[test]
    fn test_timedelta_eq() {
        let delta1: TimeDelta = Zero::zero();
        let delta2: TimeDelta = Zero::zero();
        let delta3 = delta1 + Time::days(count: 1);
        assert!(delta1 == delta2);
        assert!(delta1 != delta3);
    }

    #[test]
    fn test_timedelta_into() {
        let delta = Time::days(count: 1);
        assert_eq!(delta.into(), Time::days(count: 1).seconds);
    }

    #[test]
    fn test_timedelta_lt() {
        let delta1 = TimeDelta { seconds: 1 };
        let delta2 = TimeDelta { seconds: 2 };
        assert!(delta1 != delta2);
        assert!(delta1 < delta2);
        assert!(!(delta1 == delta2));
        assert!(!(delta1 > delta2));
    }

    fn test_timedelta_le() {
        let delta1 = TimeDelta { seconds: 1 };
        let delta2 = TimeDelta { seconds: 2 };
        assert!(delta1 != delta2);
        assert!(delta1 <= delta2);
        assert!(!(delta1 >= delta2));
        assert!(!(delta1 == delta2));
        let delta3 = TimeDelta { seconds: 1 };
        assert!(delta1 <= delta3);
        assert!(delta1 >= delta3);
        assert!(!(delta1 != delta3));
        assert!(delta1 == delta3);
    }

    #[test]
    fn test_timestamp_add_assign() {
        let mut time: Timestamp = Zero::zero();
        time += Time::days(count: 1);
        assert_eq!(time.seconds, Zero::zero() + Time::days(count: 1).seconds);
    }

    #[test]
    fn test_timestamp_eq() {
        let time1: Timestamp = Zero::zero();
        let time2: Timestamp = Zero::zero();
        let time3 = time1.add(delta: Time::days(count: 1));
        assert!(time1 == time2);
        assert!(time1 != time3);
    }

    #[test]
    fn test_timestamp_into() {
        let time = Time::days(count: 1);
        assert_eq!(time.into(), Time::days(count: 1).seconds);
    }

    #[test]
    fn test_timestamp_sub() {
        let time1 = Timestamp { seconds: 2 };
        let time2 = Timestamp { seconds: 1 };
        let delta = time1.sub(other: time2);
        assert_eq!(delta, Time::seconds(count: 1));
    }

    #[test]
    fn test_timestamp_sub_delta() {
        let time1 = Timestamp { seconds: 2 };
        let delta = Time::seconds(count: 1);
        let time2 = time1.sub_delta(other: delta);
        assert_eq!(time2, Timestamp { seconds: 1 });
    }

    #[test]
    fn test_timestamp_lt() {
        let time1: Timestamp = Zero::zero();
        let time2 = time1.add(delta: Time::days(count: 1));
        assert!(time1 < time2);
    }

    #[test]
    fn test_timestamp_zero() {
        let time: Timestamp = Timestamp { seconds: 0 };
        assert_eq!(time, Zero::zero());
    }

    #[test]
    fn test_timestamp_is_zero() {
        let time: Timestamp = Timestamp { seconds: 0 };
        assert!(time.is_zero());
    }

    #[test]
    fn test_timestamp_is_non_zero() {
        let time: Timestamp = Timestamp { seconds: 1 };
        assert!(time.is_non_zero());
    }

    #[test]
    fn test_time_add() {
        let time: Timestamp = Zero::zero();
        let new_time = time.add(delta: Time::days(count: 1));
        assert_eq!(new_time.seconds, time.seconds + Time::days(count: 1).seconds);
    }

    #[test]
    fn test_time_now() {
        start_cheat_block_timestamp_global(block_timestamp: Time::days(count: 1).seconds);
        let time = Time::now();
        assert_eq!(time.seconds, Time::days(count: 1).seconds);
    }

    #[test]
    fn test_time_seconds() {
        let seconds = 42;
        let time = Time::seconds(count: seconds);
        assert_eq!(time.seconds, seconds);
    }

    #[test]
    fn test_time_days() {
        let time = Time::days(count: 1);
        assert_eq!(time.seconds, DAY);
    }

    #[test]
    #[should_panic(expected: "TimeDelta_add Overflow")]
    fn test_timedelta_add_overflow() {
        let delta1 = TimeDelta { seconds: 1 };
        let delta2 = TimeDelta { seconds: MAX_U64 };
        delta1 + delta2;
    }

    #[test]
    #[should_panic(expected: "TimeDelta_sub Underflow")]
    fn test_timedelta_sub_underflow() {
        let delta1 = TimeDelta { seconds: 1 };
        let delta2 = TimeDelta { seconds: 2 };
        delta1 - delta2;
    }

    #[test]
    #[should_panic(expected: "Timestamp_add Overflow")]
    fn test_timestamp_add_assign_overflow() {
        let mut time = Timestamp { seconds: MAX_U64 };
        time += Time::seconds(count: 1);
    }

    #[test]
    #[should_panic(expected: "Timestamp_add Overflow")]
    fn test_timestamp_add_overflow() {
        let mut time = Timestamp { seconds: MAX_U64 };
        time.add(Time::seconds(count: 1));
    }

    #[test]
    #[should_panic(expected: "Timestamp_sub Underflow")]
    fn test_timestamp_sub_underflow() {
        let time1 = Timestamp { seconds: 1 };
        let time2 = Timestamp { seconds: 2 };
        time1.sub(other: time2);
    }

    #[test]
    #[should_panic(expected: "Timestamp_sub_delta Underflow")]
    fn test_timestamp_sub_delta_underflow() {
        let time1 = Timestamp { seconds: 1 };
        let delta = TimeDelta { seconds: 2 };
        time1.sub_delta(other: delta);
    }

    #[test]
    #[should_panic(expected: "Timedelta overflow: too many days")]
    fn test_days_overflow() {
        Time::days(count: MAX_U64);
    }

    #[test]
    #[should_panic(expected: "Timedelta overflow: too many weeks")]
    fn test_weeks_overflow() {
        Time::weeks(count: MAX_U64);
    }

    #[test]
    #[should_panic(expected: "TimeDelta division by 0")]
    fn test_timedelta_div_by_zero() {
        let delta = TimeDelta { seconds: 1 };
        delta.div(divider: 0);
    }

    #[test]
    fn test_time_weeks() {
        let time = Time::weeks(count: 1);
        assert_eq!(time.seconds, WEEK);
    }

    #[test]
    fn test_timedelta_div() {
        let delta1 = TimeDelta { seconds: 10 };
        let divider = 2;
        let delta2 = delta1.div(:divider);
        assert_eq!(delta2.seconds, delta1.seconds / divider);
        assert_eq!(delta2.seconds, 5);
    }

    #[test]
    fn test_timedelta_div_by_bigger() {
        let delta1 = TimeDelta { seconds: 1 };
        let divider = 2;
        let delta2 = delta1.div(:divider);
        assert_eq!(delta2.seconds, delta1.seconds / divider);
        assert_eq!(delta2.seconds, 0);
    }
}
