use starknet::account::Call;

#[starknet::interface]
pub trait IShadowAccount<TContractState> {
    /// Executes the given `calls` exactly as an account contract would, and returns the
    /// return value of each call. Only the owner (the deployer) is authorized to call this
    /// entrypoint.
    fn execute(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    /// Returns the address authorized to call `execute`.
    fn owner(self: @TContractState) -> starknet::ContractAddress;
    // TODO: Consider adding ownership transfer entrypoint.
}

#[starknet::contract]
pub mod ShadowAccount {
    use openzeppelin::utils::execution::execute_calls;
    use starknet::account::Call;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use starkware_utils::components::eic_upgradable::EICUpgradableComponent;
    use starkware_utils::components::eic_upgradable::interface::IEICUpgradable;
    use super::IShadowAccount;

    component!(path: EICUpgradableComponent, storage: upgradable, event: UpgradableEvent);

    impl UpgradableInternalImpl = EICUpgradableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        upgradable: EICUpgradableComponent::Storage,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        UpgradableEvent: EICUpgradableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.owner.write(get_caller_address());
    }

    #[abi(embed_v0)]
    impl ShadowAccountImpl of IShadowAccount<ContractState> {
        fn execute(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            self.assert_only_owner();
            execute_calls(calls.span())
        }

        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }

    #[abi(embed_v0)]
    impl UpgradableImpl of IEICUpgradable<ContractState> {
        /// Replaces the contract's class hash with `new_class_hash`, upgrading its implementation,
        /// optionally running an External Initializer Contract (EIC) for state migration.
        /// Only the owner is authorized to call this entrypoint.
        fn upgrade(
            ref self: ContractState,
            new_class_hash: ClassHash,
            eic_data: Option<(ClassHash, Span<felt252>)>,
        ) {
            self.assert_only_owner();
            self.upgradable.upgrade(:new_class_hash, :eic_data);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_only_owner(self: @ContractState) {
            assert(get_caller_address() == self.owner(), 'SHADOW_ACCOUNT: NOT OWNER');
        }
    }
}
