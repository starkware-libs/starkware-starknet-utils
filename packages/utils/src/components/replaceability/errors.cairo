use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub(crate) enum ReplaceErrors {
    ALREADY_INITIALIZED,
    FINALIZED,
    FINALIZE_IS_UNSAFE,
    UNKNOWN_IMPLEMENTATION,
    NOT_ENABLED_YET,
    IMPLEMENTATION_EXPIRED,
    EIC_LIB_CALL_FAILED,
    REPLACE_CLASS_HASH_FAILED,
    FAILED_REPLACE_CLASS_HASH_A2B,
    FAILED_REPLACE_CLASS_HASH_B2A,
}

impl DescribableError of Describable<ReplaceErrors> {
    fn describe(self: @ReplaceErrors) -> ByteArray {
        match self {
            ReplaceErrors::ALREADY_INITIALIZED => "ALREADY_INITIALIZED",
            ReplaceErrors::FINALIZED => "FINALIZED",
            ReplaceErrors::FINALIZE_IS_UNSAFE => "FINALIZE_IS_UNSAFE",
            ReplaceErrors::UNKNOWN_IMPLEMENTATION => "UNKNOWN_IMPLEMENTATION",
            ReplaceErrors::NOT_ENABLED_YET => "NOT_ENABLED_YET",
            ReplaceErrors::IMPLEMENTATION_EXPIRED => "IMPLEMENTATION_EXPIRED",
            ReplaceErrors::EIC_LIB_CALL_FAILED => "EIC_LIB_CALL_FAILED",
            ReplaceErrors::REPLACE_CLASS_HASH_FAILED => "REPLACE_CLASS_HASH_FAILED",
            ReplaceErrors::FAILED_REPLACE_CLASS_HASH_A2B => "FAILED_REPLACE_CLASS_HASH_A2B",
            ReplaceErrors::FAILED_REPLACE_CLASS_HASH_B2A => "FAILED_REPLACE_CLASS_HASH_B2A",
        }
    }
}
