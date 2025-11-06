pub fn contains<T, +PartialEq<T>, +Drop<T>, +Copy<T>>(span: Span<T>, value: T) -> bool {
    for item in span {
        if *item == value {
            return true;
        }
    }
    false
}
