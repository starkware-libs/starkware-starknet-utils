use core::num::traits::Bounded;

pub const MAX_U64: u64 = Bounded::<u64>::MAX;
pub const MAX_U128: u128 = Bounded::<u128>::MAX;

pub const MINUTE: u64 = 60;
pub const HOUR: u64 = 60 * MINUTE;
pub const DAY: u64 = 24 * HOUR;
pub const WEEK: u64 = 7 * DAY;

pub fn NAME() -> ByteArray {
    "NAME"
}
pub fn SYMBOL() -> ByteArray {
    "SYMBOL"
}
