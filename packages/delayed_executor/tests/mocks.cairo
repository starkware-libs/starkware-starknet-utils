#[starknet::interface]
pub trait IMockCounter<TState> {
    fn increment(ref self: TState);
    fn get_count(self: @TState) -> u64;
}

#[starknet::contract]
pub mod MockCounter {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::mocks::IMockCounter;

    #[storage]
    struct Storage {
        count: u64,
    }

    #[abi(embed_v0)]
    impl MockCounterImpl of IMockCounter<ContractState> {
        fn increment(ref self: ContractState) {
            self.count.write(self.count.read() + 1);
        }

        fn get_count(self: @ContractState) -> u64 {
            self.count.read()
        }
    }
}

#[starknet::contract]
pub mod MockMultiOwned {
    use starknet::ContractAddress;
    use starkware_delayed_executor::multi_owned::MultiOwnedComponent;

    component!(path: MultiOwnedComponent, storage: multi_owned, event: MultiOwnedEvent);

    #[abi(embed_v0)]
    impl MultiOwnedImpl = MultiOwnedComponent::MultiOwnedImpl<ContractState>;
    pub impl MultiOwnedInternalImpl = MultiOwnedComponent::InternalImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub multi_owned: MultiOwnedComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        MultiOwnedEvent: MultiOwnedComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owners: Span<ContractAddress>, acceptance_delay: u64) {
        self.multi_owned.initializer(owners, acceptance_delay);
    }
}
