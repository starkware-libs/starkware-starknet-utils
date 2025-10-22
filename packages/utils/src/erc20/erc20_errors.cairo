use starkware_utils::errors::Describable;

#[derive(Drop)]
pub enum Erc20Error {
    INSUFFICIENT_BALANCE,
    INSUFFICIENT_ALLOWANCE,
    TRANSFER_FAILED,
    STRICT_TRANSFER_FAILED,
    STRICT_TRANSFER_FROM_FAILED,
}

impl DescribableErc20Error of Describable<Erc20Error> {
    fn describe(self: @Erc20Error) -> ByteArray {
        match self {
            Erc20Error::INSUFFICIENT_BALANCE => "Insufficient ERC20 balance",
            Erc20Error::INSUFFICIENT_ALLOWANCE => "Insufficient ERC20 allowance",
            Erc20Error::TRANSFER_FAILED => "ERC20 transfer failed",
            Erc20Error::STRICT_TRANSFER_FAILED => "STRICT_TRANSFER_FAILED",
            Erc20Error::STRICT_TRANSFER_FROM_FAILED => "STRICT_TRANSFER_FROM_FAILED",
        }
    }
}
