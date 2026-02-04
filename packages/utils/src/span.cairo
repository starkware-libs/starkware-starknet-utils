use core::dict::Felt252Dict;
use core::num::traits::Zero;

#[generate_trait]
pub impl SpanContainsImpl<T, +PartialEq<T>, +Drop<T>, +Copy<T>> of Contains<T> {
    fn contains(self: Span<T>, value: T) -> bool {
        for item in self {
            if *item == value {
                return true;
            }
        }
        false
    }
}

#[generate_trait]
pub impl SpanFeltsImpl of SpanFeltsTrait {
    fn assert_unique_felts(self: Span<felt252>) {
        let mut buckets: Felt252Dict<usize> = Default::default();
        for felt in self {
            assert!(buckets[*felt].is_zero(), "Duplicate felt found: {}", *felt);
            buckets.insert(*felt, value: 1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_contains() {
        let span = array![1, 2, 3, 4, 5].span();
        assert!(span.contains(3));
        assert!(!span.contains(6));
    }

    #[test]
    fn test_assert_unique_felts() {
        let span: Span<felt252> = array![1, 2, 3, 4, 5].span();
        span.assert_unique_felts();
    }

    #[test]
    #[should_panic(expected: "Duplicate felt found: 2")]
    fn test_assert_unique_felts_duplicate() {
        let span: Span<felt252> = array![1, 2, 3, 4, 5, 2].span();
        span.assert_unique_felts();
    }
}
