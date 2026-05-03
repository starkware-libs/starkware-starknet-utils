#[starknet::component]
pub(crate) mod ReplaceabilityComponent {
    use core::num::traits::Zero;
    use core::poseidon;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
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

        // Schedules a new implementation and validates that it is upgradeable. If the target
        // cannot itself perform a full upgrade cycle (add + replace, in both directions), the
        // entire transaction reverts. Final adds (`implementation_data.final = true`) are
        // rejected with `FINALIZE_IS_UNSAFE` — to finalize, use
        // `add_new_implementation_unsafe` instead.
        fn add_new_implementation(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            assert!(!implementation_data.final, "{}", ReplaceErrors::FINALIZE_IS_UNSAFE);
            self.invoke_upgradeability_validation(implementation_data);
            self.add_new_implementation_unsafe(implementation_data);
        }

        // Schedules a new implementation without running upgradeability validation. Bypassing
        // this check can permanently brick the contract if the new code lacks a working upgrade
        // path — only use when the target has been validated through some other means.
        fn add_new_implementation_unsafe(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            // Authoritative auth check for direct callers. Also load-bearing during
            // validation: step 2's `impl_b_dispatcher.add_new_implementation_unsafe` runs
            // this check on the target class, so a target with broken `upgrade_governor`
            // role wiring fails the dry-run cycle here.
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

        // Dry-run validation of a full upgrade cycle for the user's `implementation_data`.
        // Always panics — `UPGRADEABILITY_VALIDATION_SUCCESS` on success, or the underlying
        // failure otherwise. Callers wrap this in a library_call so the panic reverts every
        // side effect: storage writes, emitted events, and the `replace_class_syscall`s in
        // both `replace_to`s below.
        //
        // Step 1 (A→B): runs the user's add + replace on `self`, exercising the user's EIC
        // and `final` flag through the actual production code path. After step 1 the on-chain
        // class hash is briefly impl_b — the outer panic reverts it.
        //
        // Step 2 (B→A): library-dispatches an add + replace back to impl_a on impl_b. This
        // proves the new class can itself perform an upgrade cycle and catches a target that
        // lacks `add_new_implementation_unsafe` / `replace_to` or has a broken role wiring.
        // Step 2 carries `eic_data: None` and `final: false` — the round trip's purpose is
        // to exercise the upgrade machinery, not run another EIC or burn finalization.
        //
        // Threat model: guards against an upgrade_governor accidentally scheduling a
        // non-upgradeable class. A malicious governor can still brick via
        // `add_new_implementation_unsafe`. A malicious target cannot spoof the success
        // sentinel — the runtime appends `'ENTRYPOINT_FAILED'` per dispatch frame, so a
        // spoofed panic from a step-2 dispatched function fails the exact-array match in
        // `invoke_upgradeability_validation`.
        fn validate_upgradeability(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            // impl_a_hash: current contract class hash.
            let impl_a_hash = get_class_hash_at_syscall(get_contract_address()).unwrap_syscall();

            // impl_b_hash: class hash of user-planned upgrade.
            let impl_b_hash = implementation_data.impl_hash;

            // Step 1 (A→B): complete the user-planned upgrade on `self`. Zero the delay so
            // the add yields `activation_time = block_timestamp`, which satisfies
            // `replace_to`'s `activation_time <= now` check. Relies on the production
            // invariant that `block_timestamp > 0`; tests cheat the timestamp in
            // `deploy_replaceability_mock` to bridge snforge's zero default.
            self.upgrade_delay.write(0);
            self.add_new_implementation_unsafe(implementation_data);
            self.replace_to(implementation_data);

            // Step 2 (B→A): library-dispatch an upgrade back to impl_a using impl_b's own
            // machinery. Re-zero `upgrade_delay` because step 1's EIC is the only legitimate
            // way to modify it, and step 2's timing check requires activation_time <= now.
            self.upgrade_delay.write(0);
            let back2a_impl_data = ImplementationData {
                impl_hash: impl_a_hash, eic_data: Option::None, final: false,
            };
            let impl_b_dispatcher = IReplaceableLibraryDispatcher { class_hash: impl_b_hash };

            impl_b_dispatcher.add_new_implementation_unsafe(implementation_data: back2a_impl_data);
            impl_b_dispatcher.replace_to(implementation_data: back2a_impl_data);
            // Defends against a target whose `replace_to` returns Ok without actually
            // calling `replace_class_syscall` (e.g. a hostile no-op re-implementation). The
            // step-1 equivalent is unnecessary because step 1 runs `self`'s own `replace_to`,
            // which already asserts the syscall succeeded.
            assert!(
                get_class_hash_at_syscall(get_contract_address()).unwrap_syscall() == impl_a_hash,
                "{}",
                ReplaceErrors::FAILED_REPLACE_CLASS_HASH_B2A,
            );

            // Load-bearing: the panic is what reverts every side effect above — the
            // `upgrade_delay` writes, the storage entries from the two adds, the emitted
            // events, and (critically) the `replace_class_syscall`s in both `replace_to`s.
            // A normal return here would leave the contract in step 2's state.
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
        // Runs `validate_upgradeability(impl_data)` via library_call against the contract's
        // current (trusted) class hash — the validation logic comes from this class, not from
        // the untrusted target referenced in `impl_data`.
        //
        // Returns silently on `UPGRADEABILITY_VALIDATION_SUCCESS` (the library call's side
        // effects are reverted by the runtime). Any other panic is propagated, reverting the
        // caller's transaction.
        fn invoke_upgradeability_validation(
            ref self: ComponentState<TContractState>, impl_data: ImplementationData,
        ) {
            let current_class_hash = get_class_hash_at_syscall(get_contract_address())
                .unwrap_syscall();

            let mut calldata = array![];
            impl_data.serialize(ref calldata);
            let result = library_call_syscall(
                class_hash: current_class_hash,
                function_selector: selector!("validate_upgradeability"),
                calldata: calldata.span(),
            );

            // Unreachable in practice — validate_upgradeability always panics.
            let panic_data = result.expect_err('VALIDATION_DID_NOT_PANIC');
            // On success, validate_upgradeability panics with the
            // UPGRADEABILITY_VALIDATION_SUCCESS sentinel; the Starknet runtime then appends
            // 'ENTRYPOINT_FAILED' (the runtime-dictated suffix for any failed entry point)
            // to the panic data. Match the exact 2-element pattern: a target that spoofs
            // the sentinel from its own dispatched function gets an extra runtime suffix
            // and fails this comparison.
            if panic_data != array![UPGRADEABILITY_VALIDATION_SUCCESS, 'ENTRYPOINT_FAILED'] {
                core::panics::panic(panic_data);
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
