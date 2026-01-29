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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_contains() {
        let span = array![1, 2, 3, 4, 5].span();
        assert!(span.contains(3));
        assert!(!span.contains(6));
    }
}
