use starknet::account::Call;

#[starknet::interface]
pub trait ISubAccount<TContractState> {
    /// Executes the given `calls` exactly as an account contract would, and returns the
    /// return value of each call. Only the controller (set in the constructor) is authorized
    /// to call this entrypoint.
    fn execute(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    /// Returns the address authorized to call `execute`.
    fn controller(self: @TContractState) -> starknet::ContractAddress;
    // TODO: Consider adding ownership transfer entrypoint.
}

#[starknet::contract]
pub mod SubAccount {
    use openzeppelin::utils::execution::execute_calls;
    use starknet::account::Call;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use super::ISubAccount;

    #[storage]
    struct Storage {
        controller: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.controller.write(get_caller_address());
    }

    #[abi(embed_v0)]
    impl SubAccountImpl of ISubAccount<ContractState> {
        fn execute(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert(get_caller_address() == self.controller(), 'SUB_ACCOUNT: NOT CONTROLLER');
            execute_calls(calls.span())
        }

        fn controller(self: @ContractState) -> ContractAddress {
            self.controller.read()
        }
    }
}
