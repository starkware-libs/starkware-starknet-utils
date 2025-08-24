use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub enum TraceErrors {
    UNORDERED_INSERTION,
    EMPTY_TRACE,
    INDEX_OUT_OF_BOUNDS,
    PENULTIMATE_NOT_EXIST,
    ANTEPENULTIMATE_NOT_EXIST,
}

impl DescribableError of Describable<TraceErrors> {
    fn describe(self: @TraceErrors) -> ByteArray {
        match self {
            TraceErrors::UNORDERED_INSERTION => "Unordered insertion",
            TraceErrors::EMPTY_TRACE => "Empty trace",
            TraceErrors::INDEX_OUT_OF_BOUNDS => "Index out of bounds",
            TraceErrors::PENULTIMATE_NOT_EXIST => "Penultimate does not exist",
            TraceErrors::ANTEPENULTIMATE_NOT_EXIST => "Antepenultimate does not exist",
        }
    }
}
