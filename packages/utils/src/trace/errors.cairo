use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub enum TraceErrors {
    UNORDERED_INSERTION,
    INDEX_OUT_OF_BOUNDS,
}

impl DescribableError of Describable<TraceErrors> {
    fn describe(self: @TraceErrors) -> ByteArray {
        match self {
            TraceErrors::UNORDERED_INSERTION => "Unordered insertion",
            TraceErrors::INDEX_OUT_OF_BOUNDS => "Index out of bounds",
        }
    }
}
