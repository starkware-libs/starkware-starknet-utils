/// Minimal versioned interface so tests can observe which class currently backs the contract.
#[starknet::interface]
pub trait IMockVersion<TContractState> {
    fn version(self: @TContractState) -> felt252;
}

/// Mock embedding `EICUpgradableComponent`. Exposes an unguarded `upgrade` (access control is the
/// developer's responsibility, out of the component's scope) and reports version `1`.
#[starknet::contract]
pub mod EICUpgradableMock {
    use starknet::ClassHash;
    use starkware_utils::components::eic_upgradable::EICUpgradableComponent;
    use starkware_utils::components::eic_upgradable::interface::IEICUpgradable;
    use super::IMockVersion;

    component!(path: EICUpgradableComponent, storage: upgradable, event: UpgradableEvent);

    impl UpgradableInternal = EICUpgradableComponent::InternalImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub upgradable: EICUpgradableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        UpgradableEvent: EICUpgradableComponent::Event,
    }

    #[abi(embed_v0)]
    impl EICUpgradableImpl of IEICUpgradable<ContractState> {
        fn upgrade(
            ref self: ContractState,
            new_class_hash: ClassHash,
            eic_data: Option<(ClassHash, Span<felt252>)>,
        ) {
            self.upgradable.upgrade(:new_class_hash, :eic_data);
        }
    }

    #[abi(embed_v0)]
    impl MockVersionImpl of IMockVersion<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            1
        }
    }
}

/// EIC used by the tests: writes `data[0]` into the `eic_marker` slot (in the caller's storage
/// context when `library_call`ed), so a test can confirm the EIC ran. Reverts on a bad length.
#[starknet::contract]
pub mod EICMock {
    use starknet::storage::StoragePointerWriteAccess;
    use starkware_utils::components::eic_upgradable::interface::IEIC;

    #[storage]
    struct Storage {
        eic_marker: felt252,
    }

    #[abi(embed_v0)]
    impl EICImpl of IEIC<ContractState> {
        fn eic_initialize(ref self: ContractState, data: Span<felt252>) {
            assert(data.len() == 1, 'EIC_INIT_DATA_LEN_MISMATCH');
            self.eic_marker.write(*data[0]);
        }
    }
}

/// Target class for upgrade tests: a distinct class hash from `EICUpgradableMock` that reports
/// version `2`, so a test can confirm `replace_class` actually took effect.
#[starknet::contract]
pub mod EICUpgradableMockV2 {
    use super::IMockVersion;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MockVersionImpl of IMockVersion<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            2
        }
    }
}
