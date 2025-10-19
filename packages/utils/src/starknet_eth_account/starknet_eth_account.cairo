use core::num::traits::Zero;
use openzeppelin::account::extensions::src9::{ISRC9_V2, OutsideExecution};
use openzeppelin::account::utils::execute_single_call;
use openzeppelin::introspection::src5::SRC5Component;
use starknet::account::Call;
use starknet::eth_address::EthAddress;
use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
use starkware_utils::starknet_eth_account::utils::{
    Transaction, TransactionMetadata, get_outside_execution_hash, get_transaction_hash,
    is_tx_version_valid, is_valid_signature,
};

#[starknet::interface]
trait IAccount<TContractState> {
    fn __execute__(ref self: TContractState, calls: Array<Call>);
    fn __validate__(self: @TContractState, calls: Array<Call>) -> felt252;
    fn get_version(self: @TContractState) -> felt252;
    fn execute_from_outside(
        ref self: TContractState, outside_execution: OutsideExecution, signature: Span<felt252>,
    ) -> Array<Span<felt252>>;
}

#[starknet::contract(account)]
mod StarknetEthAccount {
    use super::*;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        eth_address: EthAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, eth_address: EthAddress) {
        self.eth_address.write(eth_address);
        // TODO: init SRC5?
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(self: @ContractState, calls: Array<Call>) -> felt252 {
            assert!(calls.len() == 1);

            let tx_info = starknet::get_tx_info().unbox();
            let signature = tx_info.signature;

            // TODO: Fix values below.
            let transaction = Transaction {
                calls: calls.span(),
                metadata: @TransactionMetadata {
                    version: 1,
                    chain_id: 1,
                    execution_resources: array![1, 2, 3].span(),
                    tip: 1,
                    nonce: 1,
                },
            };
            let msg_hash = get_transaction_hash(@transaction);
            assert!(
                is_valid_signature(:msg_hash, :signature, eth_address: self.eth_address.read()),
                "Invalid signature",
            );
            starknet::VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) {
            let sender = starknet::get_caller_address();
            assert(sender.is_zero(), 'Invalid caller');
            assert(is_tx_version_valid(), 'Invalid tx version');

            for call in calls.span() {
                execute_single_call(call);
            }
        }

        fn get_version(self: @ContractState) -> felt252 {
            'StarknetEthAccountV0'
        }

        fn execute_from_outside(
            ref self: ContractState, outside_execution: OutsideExecution, signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            self.execute_from_outside_v2(outside_execution, signature)
        }
    }

    #[abi(embed_v0)]
    impl ISRC9_V2Impl of ISRC9_V2<ContractState> {
        fn execute_from_outside_v2(
            ref self: ContractState, outside_execution: OutsideExecution, signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            // TODO: nonce.
            let OutsideExecution {
                calls, caller, nonce: _, execute_after: _, execute_before: _,
            } = outside_execution;

            assert!(
                caller.into() == 'ANY_CALLER' || caller == starknet::get_caller_address(),
                "Invalid caller",
            );
            // TODO: handle execute_after and execute_before.

            // Validate signature.
            let msg_hash = get_outside_execution_hash(@outside_execution);
            assert!(
                is_valid_signature(:msg_hash, :signature, eth_address: self.eth_address.read()),
                "Invalid signature",
            );

            // Execute calls.
            let mut res: Array<Span<felt252>> = array![];
            for call in calls {
                res.append(execute_single_call(call));
            }

            res
        }

        fn is_valid_outside_execution_nonce(self: @ContractState, nonce: felt252) -> bool {
            // TODO: implement.
            true
        }
    }
}
