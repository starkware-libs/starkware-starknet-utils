use starknet::account::Call;

#[starknet::interface]
pub trait ISubAccount<TContractState> {
    /// Executes the given `calls` exactly as an account contract would, and returns the
    /// return value of each call. Only the owner (the deployer) is authorized to call this
    /// entrypoint.
    fn sub_account_execute(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    /// Returns the address authorized to call `sub_account_execute`.
    fn owner(self: @TContractState) -> starknet::ContractAddress;
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
        owner: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.owner.write(get_caller_address());
    }

    #[abi(embed_v0)]
    impl SubAccountImpl of ISubAccount<ContractState> {
        fn sub_account_execute(
            ref self: ContractState, calls: Array<Call>,
        ) -> Array<Span<felt252>> {
            assert(get_caller_address() == self.owner(), 'SUB_ACCOUNT: NOT OWNER');
            execute_calls(calls.span())
        }

        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}
