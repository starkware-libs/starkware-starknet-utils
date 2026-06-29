//! Shared helpers for the integration tests.

use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::account::Call;
use starknet::{ContractAddress, SyscallResultTrait};
use crate::mocks::IMockCounterDispatcher;

/// Converts a `felt252` literal into a `ContractAddress` (e.g. `addr(0)` is the zero address).
pub fn addr(felt: felt252) -> ContractAddress {
    felt.try_into().unwrap()
}

/// Deploys a `MockCounter` and returns its dispatcher (address via `.contract_address`).
pub fn deploy_counter() -> IMockCounterDispatcher {
    let contract = declare("MockCounter").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap_syscall();
    IMockCounterDispatcher { contract_address: address }
}

/// Builds a `Call` invoking `increment()` on the given counter address.
pub fn increment_call(counter_address: ContractAddress) -> Call {
    Call { to: counter_address, selector: selector!("increment"), calldata: array![].span() }
}
