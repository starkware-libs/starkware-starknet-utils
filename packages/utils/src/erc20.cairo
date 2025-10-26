// Make the module be available in the starknet-contract target.
pub mod erc20_errors;
#[cfg(target: 'test')]
pub mod erc20_mocks;
pub mod erc20_utils;
