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

        // Schedules a new implementation upgrade and validates the implementation upgradeability.
        fn add_new_implementation(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            assert!(!implementation_data.final, "{}", ReplaceErrors::FINALIZE_IS_UNSAFE);
            self.invoke_upgradeability_validation(implementation_data);
            self.add_new_implementation_unsafe(implementation_data);
        }

        // Schedules a new implementation upgrade without validation.
        fn add_new_implementation_unsafe(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
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
            self.emit(ImplementationReplaced { implementation_data });

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

        // Dry-run a full upgrade cycle:
        // 1. User planned upgrade (A->B).
        // 2. From target implementation (B->A).
        // Always panics to revert side-effects:
        // `UPGRADEABILITY_VALIDATION_SUCCESS` on success, or the underlying error otherwise.
        fn validate_upgradeability(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            let current_hash = get_class_hash_at_syscall(get_contract_address()).unwrap_syscall();
            let target_hash = implementation_data.impl_hash;

            // Step 1 (A->B): User planned upgrade.
            // Zero the upgrade delay to allow instant add & replace.
            self.upgrade_delay.write(0);
            self.add_new_implementation_unsafe(implementation_data);
            self.replace_to(implementation_data);
            assert!(
                get_class_hash_at_syscall(get_contract_address()).unwrap_syscall() == target_hash,
                "{}",
                ReplaceErrors::FAILED_REPLACE_CLASS_HASH_A2B,
            );

            // Step 2 (B->A): Upgrade back to impl_a using target class code.
            // Re-zero upgrade delay in case EIC altered it.
            self.upgrade_delay.write(0);
            let back2a_impl_data = ImplementationData {
                impl_hash: current_hash, eic_data: Option::None, final: false,
            };
            let target_impl_dispatcher = IReplaceableLibraryDispatcher { class_hash: target_hash };

            target_impl_dispatcher
                .add_new_implementation_unsafe(implementation_data: back2a_impl_data);
            target_impl_dispatcher.replace_to(implementation_data: back2a_impl_data);
            assert!(
                get_class_hash_at_syscall(get_contract_address()).unwrap_syscall() == current_hash,
                "{}",
                ReplaceErrors::FAILED_REPLACE_CLASS_HASH_B2A,
            );

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
        // Invoke `validate_upgradeability` via library_call on the current class.
        // Returns on the success sentinel; propagates any other panic.
        fn invoke_upgradeability_validation(
            ref self: ComponentState<TContractState>, implementation_data: ImplementationData,
        ) {
            let current_class_hash = get_class_hash_at_syscall(get_contract_address())
                .unwrap_syscall();

            let mut calldata = array![];
            implementation_data.serialize(ref calldata);
            let result = library_call_syscall(
                class_hash: current_class_hash,
                function_selector: selector!("validate_upgradeability"),
                calldata: calldata.span(),
            );

            // validate_upgradeability always panics.
            let panic_data = result.expect_err('VALIDATION_DID_NOT_PANIC');
            // Catch the success sentinel panic, re-throw any other panic.
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
