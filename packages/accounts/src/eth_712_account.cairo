// SPDX-License-Identifier: Apache-2.0
// Copy & Extends OpenZeppelin Contracts for Cairo v2.0.0 (presets/src/account.cairo)

/// StarknetEth712Account
///
/// Account contract that supports ISRC6, ISRC9_V2 (Execute from outside v2) and ISRC5.
/// Initialized with an Ethereum address; transactions are validated using EIP-712
/// and signed with Secp256k1, allowing signing from a remote chain's wallet
/// and execution on Starknet.

#[starknet::contract(account)]
pub mod StarknetEth712Account {
    use core::num::traits::Zero;
    use openzeppelin::interfaces::accounts::{ISRC6, ISRC6_ID};
    use openzeppelin::interfaces::src9::{ISRC9_V2, ISRC9_V2_ID, OutsideExecution};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use openzeppelin::utils::execution::{execute_calls, execute_single_call};
    use starknet::account::Call;
    use starknet::secp256_trait::Signature;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::syscalls::replace_class_syscall;
    use starknet::{ClassHash, EthAddress, SyscallResultTrait};
    use starkware_accounts::eth_712_utils::{
        Transaction, TransactionMetadata, assert_valid_owner, extract_signature,
        extract_signature_flexible, get_call_set_hash, get_outside_execution_hash,
        get_transaction_hash, is_tx_version_valid, is_valid_eth_signature, resource_bounds_as_felts,
    };
    use starkware_accounts::interface::{
        IAccount712Admin, ICUSTOM_SIGNATURE_VALIDATION_ID, ICustomSignatureValidation,
        IEICDispatcherTrait, IEICLibraryDispatcher, Upgraded,
    };

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub src5: SRC5Component::Storage,
        pub SRC9_nonces: Map<felt252, bool>,
        pub eth_address: EthAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        Upgraded: Upgraded,
    }

    // ================================
    // Account Entrypoints (ISRC6)
    // ================================

    #[abi(embed_v0)]
    impl ISRC6Impl of ISRC6<ContractState> {
        fn __validate__(self: @ContractState, calls: Array<Call>) -> felt252 {
            let tx_info = starknet::get_tx_info().unbox();
            let (signature, evm_chain_id) = extract_signature(tx_info.signature);

            let transaction = Transaction {
                calls: calls.span(),
                metadata: @TransactionMetadata {
                    version: tx_info.version,
                    chain_id: tx_info.chain_id,
                    execution_resources: resource_bounds_as_felts(tx_info.resource_bounds),
                    tip: tx_info.tip.into(),
                    nonce: tx_info.nonce,
                },
            };
            let msg_hash = get_transaction_hash(@transaction, chain_id: evm_chain_id);
            assert(
                is_valid_eth_signature(:msg_hash, :signature, eth_address: self.eth_address.read()),
                'INVALID_SIGNATURE',
            );
            starknet::VALIDATED
        }

        fn __execute__(self: @ContractState, calls: Array<Call>) {
            assert(starknet::get_caller_address().is_zero(), 'INVALID_CALLER');
            assert(is_tx_version_valid(), 'INVALID_TX_VERSION');
            for call in calls.span() {
                execute_single_call(call);
            }
        }

        fn is_valid_signature(
            self: @ContractState, hash: felt252, signature: Array<felt252>,
        ) -> felt252 {
            let sig = extract_signature_flexible(signature.span());
            if is_valid_eth_signature(hash.into(), sig, self.eth_address.read()) {
                starknet::VALIDATED
            } else {
                0
            }
        }
    }

    // ================================
    // Custom Signature Validation
    // ================================

    #[abi(embed_v0)]
    impl CustomSignatureValidationImpl of ICustomSignatureValidation<ContractState> {
        /// Validates owner signature over the EIP-712 `CallSet { calls }` message.
        /// Independent of the tx's metadata (version/resource-bounds/nonce etc.).
        /// Returns `VALIDATED` for a valid 6-felt signature and 0 for an invalid one.
        /// Reverts on a malformed signature.
        fn is_custom_signature_valid(
            self: @ContractState, calls: Span<Call>, signature: Span<felt252>,
        ) -> felt252 {
            let (signature, evm_chain_id) = extract_signature(signature);
            let msg_hash = get_call_set_hash(calls, chain_id: evm_chain_id);
            if is_valid_eth_signature(:msg_hash, :signature, eth_address: self.eth_address.read()) {
                starknet::VALIDATED
            } else {
                0
            }
        }
    }

    // ================================
    // Admin Implementation
    // ================================

    #[abi(embed_v0)]
    impl AdminImpl of IAccount712Admin<ContractState> {
        fn initialize(ref self: ContractState, eth_address: EthAddress, signature: Signature) {
            assert(self.eth_address.read().is_zero(), 'ALREADY_INITIALIZED');
            assert_valid_owner(:eth_address, :signature);
            self.eth_address.write(eth_address);

            // Register 'execute_from_outside_v2' interface, as paymaster requires this.
            self.src5.register_interface(ISRC9_V2_ID);
            // Register Account interface (ISRC6) so that we can receive 721/1155 tokens.
            self.src5.register_interface(ISRC6_ID);
            // Register the custom-signature-validation.
            // Custom Validation is an opt-in, callers need to detect that the account supports it.
            self.src5.register_interface(ICUSTOM_SIGNATURE_VALIDATION_ID);
        }

        fn upgrade(
            ref self: ContractState,
            new_class_hash: ClassHash,
            eic_data: Option<(ClassHash, Span<felt252>)>,
        ) {
            self.assert_only_self();
            if let Some((class_hash, eic_init_data)) = eic_data {
                IEICLibraryDispatcher { class_hash }.eic_initialize(eic_init_data);
            }
            replace_class_syscall(new_class_hash).unwrap_syscall();
            self.emit(Upgraded { class_hash: new_class_hash });
        }
    }

    #[abi(embed_v0)]
    impl ISRC9_V2Impl of ISRC9_V2<ContractState> {
        fn execute_from_outside_v2(
            ref self: ContractState, outside_execution: OutsideExecution, signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            let OutsideExecution {
                caller, nonce, execute_after, execute_before, calls,
            } = outside_execution;

            // 1. Validate the caller.
            //    It must be either the one specified in the outside execution,
            //    unless 'ANY_CALLER' is specified.
            if caller.into() != 'ANY_CALLER' {
                assert(starknet::get_caller_address() == caller, 'INVALID_CALLER');
            }

            // 2. Validate the execution time span
            let now = starknet::get_block_timestamp();
            assert(execute_after < now, 'EXECUTED_TOO_EARLY');
            assert(now < execute_before, 'EXECUTED_TOO_LATE');

            // 3. Validate the nonce
            assert(self.is_valid_outside_execution_nonce(nonce), 'DUPLICATE_NONCE');

            // 4. Mark the nonce as used
            self.SRC9_nonces.write(nonce, true);

            // 5. Validate the signature.
            // We pass the EVM Chain ID as the last element of the signature.
            let (signature, evm_chain_id) = extract_signature(:signature);
            let msg_hash = get_outside_execution_hash(@outside_execution, chain_id: evm_chain_id);
            assert(
                is_valid_eth_signature(:msg_hash, :signature, eth_address: self.eth_address.read()),
                'INVALID_SIGNATURE',
            );
            execute_calls(calls)
        }

        fn is_valid_outside_execution_nonce(self: @ContractState, nonce: felt252) -> bool {
            !self.SRC9_nonces.read(nonce)
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        fn assert_only_self(self: @ContractState) {
            let caller = starknet::get_caller_address();
            let self_addr = starknet::get_contract_address();
            assert(self_addr == caller, 'UNAUTHORIZED');
        }
    }
}
