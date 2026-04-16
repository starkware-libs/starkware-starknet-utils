#[starknet::component]
pub(crate) mod ReplaceabilityComponent {
    use core::num::traits::Zero;
    use core::poseidon;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::class_hash::ClassHash;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::syscalls::{
        get_class_hash_at_syscall, library_call_syscall, replace_class_syscall,
    };
    use starknet::{SyscallResultTrait, get_block_timestamp, get_contract_address};
    use starkware_utils::components::common_roles::CommonRolesComponent;
    use starkware_utils::components::common_roles::CommonRolesComponent::InternalTrait;
    use starkware_utils::components::replaceability::errors::ReplaceErrors;
    use starkware_utils::components::replaceability::interface::{
        EIC_INITIALIZE_SELECTOR, IMPLEMENTATION_EXPIRATION, IReplaceable,
        IReplaceableDispatcherTrait, IReplaceableLibraryDispatcher, ImplementationAdded,
        ImplementationData, ImplementationFinalized, ImplementationRemoved, ImplementationReplaced,
        UPGRADEABILITY_VALIDATION_SUCCESS,
    };


    #[storage]
    pub struct Storage {
        initialized: bool,
        // Delay in seconds before performing an upgrade.
        upgrade_delay: u64,
        // Timestamp by which implementation can be activated.
        impl_activation_time: Map<felt252, u64>,
        // Timestamp until which implementation can be activated.
        impl_expiration_time: Map<felt252, u64>,
        // Is the implementation finalized.
        finalized: bool,
    }

    #[event]
    #[derive(Copy, Drop, PartialEq, starknet::Event)]
    pub enum Event {
        ImplementationAdded: ImplementationAdded,
        ImplementationRemoved: ImplementationRemoved,
        ImplementationReplaced: ImplementationReplaced,
        ImplementationFinalized: ImplementationFinalized,
    }

    // Derives the implementation_data key.
    fn calc_impl_key(implementation_data: ImplementationData) -> felt252 {
        // Hash the implementation_data to obtain a key.
        let mut hash_input = ArrayTrait::new();
        implementation_data.serialize(ref hash_input);
        poseidon::poseidon_hash_span(hash_input.span())
    }

    #[embeddable_as(ReplaceabilityImpl)]
    pub impl Replaceability<
        TContractState,
        +HasComponent<TContractState>,
        impl CommonRoles: CommonRolesComponent::HasComponent<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IReplaceable<ComponentState<TContractState>> {
        fn get_upgrade_delay(self: @ComponentState<TContractState>) -> u64 {
            self.upgrade_delay.read()
        }

        fn get_impl_activation_time(
            self: @ComponentState<TContractState>, implementation_data: ImplementationData,
        ) -> u64 {
            let impl_key = calc_impl_key(:implementation_data);
            self.impl_activation_time.read(impl_key)
        }

        // Schedules a new implementation and validates that it is upgradeable. If the new
        // implementation cannot itself perform a full upgrade cycle (add + replace), the entire
        // transaction reverts. Finalized implementations (`final = true`) skip the validation.
        fn add_new_implementation(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            // The auth check exists in two places. Here it is fail-fast: bail before paying the
            // library_call cost of validation. The check inside `_unsafe` below is the one that
            // actually enforces the role on direct callers and exercises the target's role
            // wiring during the validation dispatch.
            let common_roles = get_dep_component!(@self, CommonRoles);
            common_roles.only_upgrade_governor();

            if (!implementation_data.final) {
                self.invoke_upgradeability_validation(implementation_data.impl_hash);
            }
            self.add_new_implementation_unsafe(implementation_data);
        }

        // Schedules a new implementation without running upgradeability validation. Bypassing
        // this check can permanently brick the contract if the new code lacks a working upgrade
        // path — only use when the target has been validated through some other means.
        fn add_new_implementation_unsafe(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            // Authoritative auth check for direct callers. Also load-bearing during validation:
            // when `validate_upgradeability` dispatches this on the target class, this check is
            // what proves the target's upgrade_governor role is wired correctly.
            let common_roles = get_dep_component!(@self, CommonRoles);
            common_roles.only_upgrade_governor();

            let activation_time = get_block_timestamp() + self.get_upgrade_delay();
            let expiration_time = activation_time + IMPLEMENTATION_EXPIRATION;
            self.set_impl_activation_time(:implementation_data, :activation_time);
            self.set_impl_expiration_time(:implementation_data, :expiration_time);
            self.emit(ImplementationAdded { implementation_data });
        }

        fn remove_implementation(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            // The call is restricted to the upgrade governor.
            let common_roles = get_dep_component!(@self, CommonRoles);
            common_roles.only_upgrade_governor();

            // Read implementation activation time.
            let impl_activation_time = self.get_impl_activation_time(:implementation_data);

            if (impl_activation_time.is_non_zero()) {
                self.set_impl_activation_time(:implementation_data, activation_time: 0);
                self.set_impl_expiration_time(:implementation_data, expiration_time: 0);
                self.emit(ImplementationRemoved { implementation_data });
            }
        }

        // Replaces the class hash to a previously-added implementation whose activation time
        // has passed.
        fn replace_to(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            // The call is restricted to the upgrade agent or upgrade governor.
            let common_roles = get_dep_component!(@self, CommonRoles);
            common_roles.only_upgrader();

            // Validate implementation is not finalized.
            assert!(!self.is_finalized(), "{}", ReplaceErrors::FINALIZED);

            let now = get_block_timestamp();
            let impl_activation_time = self.get_impl_activation_time(:implementation_data);
            let impl_expiration_time = self.get_impl_expiration_time(:implementation_data);

            // Zero activation time means that this implementation & init vector combination
            // was not previously added.
            assert!(
                impl_activation_time.is_non_zero(), "{}", ReplaceErrors::UNKNOWN_IMPLEMENTATION,
            );

            assert!(impl_activation_time <= now, "{}", ReplaceErrors::NOT_ENABLED_YET);
            assert!(now <= impl_expiration_time, "{}", ReplaceErrors::IMPLEMENTATION_EXPIRED);
            // We emit now so that finalize emits last (if it does).
            self.emit(ImplementationReplaced { implementation_data });

            // Finalize implementation, if needed.
            if (implementation_data.final) {
                self.finalize();
                self.emit(ImplementationFinalized { impl_hash: implementation_data.impl_hash });
            }

            // Handle EIC.
            if let Option::Some(eic_data) = implementation_data.eic_data {
                // Wrap the calldata as a span, as preparation for the library_call_syscall
                // invocation.
                let mut calldata_wrapper = ArrayTrait::new();
                eic_data.eic_init_data.serialize(ref calldata_wrapper);

                // Invoke the EIC's initialize function as a library call.
                let res = library_call_syscall(
                    class_hash: eic_data.eic_hash,
                    function_selector: EIC_INITIALIZE_SELECTOR,
                    calldata: calldata_wrapper.span(),
                );
                assert!(res.is_ok(), "{}", ReplaceErrors::EIC_LIB_CALL_FAILED);
            }

            // Replace the class hash.
            let result = replace_class_syscall(implementation_data.impl_hash);
            assert!(result.is_ok(), "{}", ReplaceErrors::REPLACE_CLASS_HASH_FAILED);

            // Remove implementation data, as it was consumed.
            self.set_impl_activation_time(:implementation_data, activation_time: 0);
            self.set_impl_expiration_time(:implementation_data, expiration_time: 0);
        }

        // Dry-run validation that the target class can perform a full upgrade cycle (add +
        // replace). Always panics — `UPGRADEABILITY_VALIDATION_SUCCESS` on success, or the
        // underlying failure otherwise. Callers wrap this in a library_call so the panic
        // reverts all side effects.
        //
        // Both stages are dispatched to the target class explicitly so this function tests the
        // target's own `add_new_implementation_unsafe` and `replace_to` — `_unsafe` is used
        // for the add stage to avoid re-invoking validation (recursion).
        //
        // Coverage is partial: validation only exercises the (add + replace) path with
        // `eic_data: None` and `final: false`. Targets that require EIC initialization, or
        // whose `remove_implementation` is broken, are not covered.
        //
        // Threat model: this guards against an upgrade_governor accidentally scheduling a
        // non-upgradeable class. It is not a defense against a malicious governor.
        fn validate_upgradeability(ref self: ComponentState<TContractState>, impl_hash: ClassHash) {
            let implementation_data = ImplementationData {
                impl_hash, eic_data: Option::None, final: false,
            };
            let dispatcher = IReplaceableLibraryDispatcher { class_hash: impl_hash };

            // Zero the delay so the dispatched add yields `activation_time = block_timestamp`,
            // which then satisfies `replace_to`'s `activation_time <= now` check. Relies on the
            // production invariant that `block_timestamp > 0`; tests cheat the timestamp in
            // `deploy_replaceability_mock` to bridge snforge's zero default.
            self.upgrade_delay.write(0);
            dispatcher.add_new_implementation_unsafe(:implementation_data);
            dispatcher.replace_to(:implementation_data);

            // Load-bearing: the panic is what reverts `upgrade_delay.write(0)` above and the
            // dispatchers' side effects. A normal return here would silently zero the delay.
            core::panic_with_felt252(UPGRADEABILITY_VALIDATION_SUCCESS);
        }
    }
    #[generate_trait]
    pub impl InternalReplaceabilityImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalReplaceabilityTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, upgrade_delay: u64) {
            assert!(!self.initialized.read(), "{}", ReplaceErrors::ALREADY_INITIALIZED);
            self.upgrade_delay.write(upgrade_delay);
            self.initialized.write(true);
        }
    }

    #[generate_trait]
    impl PrivateReplaceabilityImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of PrivateReplaceabilityTrait<TContractState> {
        // Runs `validate_upgradeability` against `new_class_hash` via library_call. Must be
        // called while the contract's active class hash is still trusted (i.e., before the
        // class replacement happens) — the validation logic itself comes from this active
        // class, not the untrusted target.
        //
        // Returns silently on `UPGRADABILITY_VALIDATION_SUCCESS` (the library call's side
        // effects are reverted by the runtime). Any other panic is propagated, reverting the
        // caller's transaction.
        fn invoke_upgradeability_validation(
            ref self: ComponentState<TContractState>, new_class_hash: ClassHash,
        ) {
            let current_class_hash = get_class_hash_at_syscall(get_contract_address())
                .unwrap_syscall();

            let mut calldata = array![];
            new_class_hash.serialize(ref calldata);
            let result = library_call_syscall(
                class_hash: current_class_hash,
                function_selector: selector!("validate_upgradeability"),
                calldata: calldata.span(),
            );

            match result {
                Result::Ok(_) => core::panic_with_felt252('VALIDATION_DID_NOT_PANIC'),
                Result::Err(panic_data) => {
                    // The runtime appends 'ENTRYPOINT_FAILED' to panic data from a failed entry
                    // point, so match on element 0 rather than the whole array.
                    if panic_data.is_empty()
                        || *panic_data.at(0) != UPGRADEABILITY_VALIDATION_SUCCESS {
                        core::panics::panic(panic_data);
                    }
                },
            }
        }

        fn is_finalized(self: @ComponentState<TContractState>) -> bool {
            self.finalized.read()
        }

        fn finalize(ref self: ComponentState<TContractState>) {
            self.finalized.write(true);
        }

        fn set_impl_activation_time(
            ref self: ComponentState<TContractState>,
            implementation_data: ImplementationData,
            activation_time: u64,
        ) {
            let impl_key = calc_impl_key(:implementation_data);
            self.impl_activation_time.write(impl_key, activation_time);
        }

        fn get_impl_expiration_time(
            self: @ComponentState<TContractState>, implementation_data: ImplementationData,
        ) -> u64 {
            let impl_key = calc_impl_key(:implementation_data);
            self.impl_expiration_time.read(impl_key)
        }

        fn set_impl_expiration_time(
            ref self: ComponentState<TContractState>,
            implementation_data: ImplementationData,
            expiration_time: u64,
        ) {
            let impl_key = calc_impl_key(:implementation_data);
            self.impl_expiration_time.write(impl_key, expiration_time);
        }
    }
}
