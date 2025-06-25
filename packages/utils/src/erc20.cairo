// Make the module be available in the starknet-contract target.
#[cfg(target: 'test')]
pub(crate) mod erc20_mocks;
pub mod erc20_utils;
