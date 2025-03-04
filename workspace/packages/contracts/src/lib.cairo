pub mod bool_array;

pub mod components;

pub(crate) mod pow_of_two;

// Make the module be available in the starknet-contract target.
#[cfg(target: 'starknet-contract')]
pub(crate) mod erc20_mocks;

// Consts and other non-component utilities
pub mod errors;

// Make the module be available in a test target.
// Simple #cfg(test) won't work because the module is not
// in the same crate with the actual tests using it.
#[cfg(target: 'test')]
pub mod test_utils;
