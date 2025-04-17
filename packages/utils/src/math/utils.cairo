use core::num::traits::WideMul;
use core::num::traits::one::One;
use core::num::traits::zero::Zero;

pub fn have_same_sign(x: i64, y: i64) -> bool {
    (x < 0) == (y < 0)
}


/// Converts an array of 8 `u32` values into a single `u256` value.
///
/// This function treats the input array as a sequence of 32-bit words,
/// where the first element of the array represents the most significant
/// 32 bits and the last element represents the least significant 32 bits.
/// The resulting `u256` value is constructed by combining these words
/// in big-endian order.
///
/// # Arguments
/// - `arr` - An array of 8 `u32` values to be converted into a `u256`.
///
/// # Returns
/// - A `u256` value representing the combined value of the input array.
///
/// # Example
/// ```cairo
/// let arr: [u32; 8] = [0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8];
/// let result: u256 = u256_from_u32_array_be(arr);
/// // `result` will now hold the value:
/// // 0x00000001_00000002_00000003_00000004_00000005_00000006_00000007_00000008
/// ```
pub fn u256_from_u32_array_be(arr: [u32; 8]) -> u256 {
    let mut value: u256 = 0;
    // This loop iterates over the elements of `arr.span()` and constructs a single value by
    // combining the elements. The multiplication by `0x100000000` shifts the current value
    // by 32 bits to the left (equivalent to appending 32 zero bits), making space for the
    // next word. This is typically done when reconstructing a larger number from smaller
    // chunks, such as converting an array of 32-bit words into a single 256-bit integer.
    for word in arr.span() {
        value *= 0x100000000;
        value = value + (*word).into();
    }
    value
}

fn u256_reverse_endian(input: u256) -> u256 {
    let low = core::integer::u128_byte_reverse(input.high);
    let high = core::integer::u128_byte_reverse(input.low);
    u256 { low, high }
}

pub fn mul_wide_and_div<
    T,
    impl TWide: WideMul<T, T>,
    +Into<T, TWide::Target>,
    +Zero<T>,
    +Div<TWide::Target>,
    +TryInto<TWide::Target, T>,
    +Drop<T>,
    +Drop<TWide::Target>,
>(
    lhs: T, rhs: T, div: T,
) -> Option<T> {
    let x: TWide::Target = lhs.wide_mul(other: rhs);
    let y: TWide::Target = (x / div.into());
    y.try_into()
}

pub fn mul_wide_and_ceil_div<
    T,
    impl TWide: WideMul<T, T>,
    +Into<T, TWide::Target>,
    +Zero<T>,
    +Div<TWide::Target>,
    +Sub<TWide::Target>,
    +Add<TWide::Target>,
    +One<TWide::Target>,
    +Copy<TWide::Target>,
    +TryInto<TWide::Target, T>,
    +Drop<T>,
    +Drop<TWide::Target>,
>(
    lhs: T, rhs: T, div: T,
) -> Option<T> {
    ceil_of_division(lhs.wide_mul(other: rhs), div.into()).try_into()
}

pub fn ceil_of_division<T, +Sub<T>, +Add<T>, +One<T>, +Div<T>, +Copy<T>, +Drop<T>>(
    dividend: T, divisor: T,
) -> T {
    (dividend + divisor - One::one()) / divisor
}

#[cfg(test)]
mod tests {
    use starkware_utils::constants::{MAX_U128, MAX_U64};
    use super::*;
    const TEST_NUM: u64 = 100000000000;

    #[test]
    fn u64_mul_wide_and_div_test() {
        let num = mul_wide_and_div(lhs: MAX_U64, rhs: MAX_U64, div: MAX_U64).unwrap();
        assert!(num == MAX_U64, "MAX_U64*MAX_U64/MAX_U64 calcaulated wrong");
        let max_u33: u64 = 0x1_FFFF_FFFF; // 2**33 -1
        // The following calculation is (2**33-1)*(2**33+1)/4 == (2**66-1)/4,
        // Which is MAX_U64 (== 2**64-1) when rounded down.
        let num = mul_wide_and_div(lhs: max_u33, rhs: (max_u33 + 2), div: 4).unwrap();
        assert!(num == MAX_U64, "MAX_U33*(MAX_U33+2)/4 calcaulated wrong");
    }

    #[test]
    #[should_panic(expected: 'Option::unwrap failed.')]
    fn u64_mul_wide_and_div_test_panic() {
        mul_wide_and_div(lhs: MAX_U64, rhs: MAX_U64, div: 1).unwrap();
    }

    #[test]
    fn u64_mul_wide_and_ceil_div_test() {
        let num = mul_wide_and_ceil_div(lhs: MAX_U64, rhs: MAX_U64, div: MAX_U64).unwrap();
        assert!(num == MAX_U64, "ceil_of_div(MAX_U64*MAX_U64, MAX_U64) calcaulated wrong");
        let num: u64 = mul_wide_and_ceil_div(lhs: TEST_NUM.into() + 1, rhs: 1, div: TEST_NUM.into())
            .unwrap();
        assert!(num == 2, "ceil_of_division((TEST_NUM+1)*1, TEST_NUM) calcaulated wrong");
    }

    #[test]
    #[should_panic(expected: 'Option::unwrap failed.')]
    fn u64_mul_wide_and_ceil_div_test_panic() {
        let max_u33: u64 = 0x1_FFFF_FFFF; // 2**33 -1
        // The following calculation is ceil((2**33-1)*(2**33+1)/4) == ceil((2**66-1)/4),
        // Which is MAX_U64+1 (== 2**64) when rounded up.
        mul_wide_and_ceil_div(lhs: max_u33, rhs: (max_u33 + 2), div: 4).unwrap();
    }

    #[test]
    fn u128_mul_wide_and_div_test() {
        let num = mul_wide_and_div(lhs: MAX_U128, rhs: MAX_U128, div: MAX_U128).unwrap();
        assert!(num == MAX_U128, "MAX_U128*MAX_U128/MAX_U128 calcaulated wrong");
        let max_u65: u128 = 0x1_FFFF_FFFF_FFFF_FFFF;
        let num = mul_wide_and_div(lhs: max_u65, rhs: (max_u65 + 2), div: 4).unwrap();
        assert!(num == MAX_U128, "MAX_U65*(MAX_U65+2)/4 calcaulated wrong");
    }

    #[test]
    #[should_panic(expected: 'Option::unwrap failed.')]
    fn u128_mul_wide_and_div_test_panic() {
        mul_wide_and_div(lhs: MAX_U128, rhs: MAX_U128, div: 1).unwrap();
    }

    #[test]
    fn u128_mul_wide_and_ceil_div_test() {
        let num = mul_wide_and_ceil_div(lhs: MAX_U128, rhs: MAX_U128, div: MAX_U128).unwrap();
        assert!(num == MAX_U128, "ceil_of_div(MAX_U128*MAX_U128, MAX_U128) calcaulated wrong");
        let num: u128 = mul_wide_and_ceil_div(
            lhs: TEST_NUM.into() + 1, rhs: 1, div: TEST_NUM.into(),
        )
            .unwrap();
        assert!(num == 2, "ceil_of_division((TEST_NUM+1)*1, TEST_NUM) calcaulated wrong");
    }

    #[test]
    #[should_panic(expected: 'Option::unwrap failed.')]
    fn u128_mul_wide_and_ceil_div_test_panic() {
        let max_u65: u128 = 0x1_FFFF_FFFF_FFFF_FFFF;
        mul_wide_and_ceil_div(lhs: max_u65, rhs: (max_u65 + 2), div: 4).unwrap();
    }

    #[test]
    fn have_same_sign_test() {
        /// Case 1: Both are positive.
        assert!(have_same_sign(1_i64, 2_i64), "both are positive failed");

        /// Case 2: Both are negative.
        assert!(have_same_sign(-1_i64, -2_i64), "both are negative failed");

        /// Case 3: Both are zero.
        assert!(have_same_sign(0_i64, 0_i64), "both are zero failed");

        /// Case 4: One is positive and the other is negative.
        assert!(
            have_same_sign(1_i64, -2_i64) == false,
            "One is positive and the other is negative failed",
        );
        assert!(
            have_same_sign(-2_i64, 1_i64) == false,
            "One is positive and the other is negative failed",
        );

        /// Case 5: One is positive and the other is zero.
        assert!(have_same_sign(1_i64, 0_i64), "One is positive and the other is zero failed");
        assert!(have_same_sign(0_i64, 1_i64), "One is positive and the other is zero failed");

        /// Case 6: One is negative and the other is zero.
        assert!(
            have_same_sign(-1_i64, 0_i64) == false, "One is negative and the other is zero failed",
        );
        assert!(
            have_same_sign(0_i64, -1_i64) == false, "One is negative and the other is zero failed",
        );
    }
}
