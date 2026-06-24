/// A minimal target contract used to observe that the `SubAccount` performs calls exactly like an
/// account contract: it mutates state and returns values that we assert against.
#[starknet::interface]
pub trait IMockTarget<TContractState> {
    fn set_value(ref self: TContractState, value: felt252);
    fn get_value(self: @TContractState) -> felt252;
    fn add(self: @TContractState, a: felt252, b: felt252) -> felt252;
}

#[starknet::contract]
pub mod MockTarget {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::IMockTarget;

    #[storage]
    struct Storage {
        value: felt252,
    }

    #[abi(embed_v0)]
    impl MockTargetImpl of IMockTarget<ContractState> {
        fn set_value(ref self: ContractState, value: felt252) {
            self.value.write(value);
        }

        fn get_value(self: @ContractState) -> felt252 {
            self.value.read()
        }

        fn add(self: @ContractState, a: felt252, b: felt252) -> felt252 {
            a + b
        }
    }
}

#[cfg(test)]
mod SubAccountTests {
    use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
    use starknet::account::Call;
    use starknet::{ContractAddress, SyscallResultTrait};
    use starkware_utils::contracts::sub_account::{
        ISubAccountDispatcher, ISubAccountDispatcherTrait, ISubAccountSafeDispatcher,
        ISubAccountSafeDispatcherTrait,
    };
    use starkware_utils_testing::test_utils::cheat_caller_address_once;
    use super::{IMockTargetDispatcher, IMockTargetDispatcherTrait};

    const OWNER: ContractAddress = 'OWNER'.try_into().unwrap();
    const OTHER: ContractAddress = 'OTHER'.try_into().unwrap();

    fn deploy_sub_account() -> ISubAccountDispatcher {
        let contract = declare("SubAccount").unwrap_syscall().contract_class();
        // The constructor sets the owner to the deployer (caller), so cheat the caller
        // address of the to-be-deployed contract to OWNER before deploying.
        let contract_address = contract.precalculate_address(@array![]);
        cheat_caller_address_once(:contract_address, caller_address: OWNER);
        let (contract_address, _) = contract.deploy(@array![]).unwrap_syscall();
        ISubAccountDispatcher { contract_address }
    }

    fn deploy_target() -> IMockTargetDispatcher {
        let contract = declare("MockTarget").unwrap_syscall().contract_class();
        let (contract_address, _) = contract.deploy(@array![]).unwrap_syscall();
        IMockTargetDispatcher { contract_address }
    }

    #[test]
    fn test_owner() {
        let sub_account = deploy_sub_account();
        assert!(sub_account.owner() == OWNER);
    }

    #[test]
    fn test_execute_single_call_mutates_state() {
        let sub_account = deploy_sub_account();
        let target = deploy_target();

        let call = Call {
            to: target.contract_address,
            selector: selector!("set_value"),
            calldata: array![42].span(),
        };

        cheat_caller_address_once(
            contract_address: sub_account.contract_address, caller_address: OWNER,
        );
        sub_account.owner_execute(array![call]);

        assert!(target.get_value() == 42);
    }

    #[test]
    fn test_execute_returns_call_results() {
        let sub_account = deploy_sub_account();
        let target = deploy_target();

        let call = Call {
            to: target.contract_address, selector: selector!("add"), calldata: array![3, 4].span(),
        };

        cheat_caller_address_once(
            contract_address: sub_account.contract_address, caller_address: OWNER,
        );
        let mut results = sub_account.owner_execute(array![call]);

        assert!(results.len() == 1);
        let mut ret = *results.at(0);
        assert!(ret.len() == 1);
        assert!(*ret.at(0) == 7);
    }

    #[test]
    fn test_execute_multiple_calls_in_order() {
        let sub_account = deploy_sub_account();
        let target = deploy_target();

        let first = Call {
            to: target.contract_address,
            selector: selector!("set_value"),
            calldata: array![1].span(),
        };
        let second = Call {
            to: target.contract_address,
            selector: selector!("set_value"),
            calldata: array![2].span(),
        };

        cheat_caller_address_once(
            contract_address: sub_account.contract_address, caller_address: OWNER,
        );
        sub_account.owner_execute(array![first, second]);

        // The last call wins, proving calls run sequentially in the given order.
        assert!(target.get_value() == 2);
    }

    #[test]
    fn test_execute_empty_calls() {
        let sub_account = deploy_sub_account();

        cheat_caller_address_once(
            contract_address: sub_account.contract_address, caller_address: OWNER,
        );
        let results = sub_account.owner_execute(array![]);

        assert!(results.len() == 0);
    }

    #[test]
    #[feature("safe_dispatcher")]
    fn test_execute_unauthorized_caller_panics() {
        let sub_account = deploy_sub_account();
        let target = deploy_target();
        let safe_sub_account = ISubAccountSafeDispatcher {
            contract_address: sub_account.contract_address,
        };

        let call = Call {
            to: target.contract_address,
            selector: selector!("set_value"),
            calldata: array![42].span(),
        };

        cheat_caller_address_once(
            contract_address: sub_account.contract_address, caller_address: OTHER,
        );
        match safe_sub_account.owner_execute(array![call]) {
            Result::Ok(_) => panic!(
                "Expected owner_execute to panic for unauthorized caller",
            ),
            Result::Err(panic_data) => { assert!(*panic_data.at(0) == 'SUB_ACCOUNT: NOT OWNER'); },
        }
    }
}
