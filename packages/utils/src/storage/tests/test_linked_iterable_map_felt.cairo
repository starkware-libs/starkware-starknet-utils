#[cfg(test)]
mod tests {
    use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
    use starknet::ContractAddress;
    use starkware_utils::storage::linked_iterable_map_felt::{
        LinkedIterableMapFelt, LinkedIterableMapIntoIterImpl, map_clear, map_is_deleted, map_iter,
        map_read, map_remove, map_write,
    };

    #[starknet::interface]
    trait ITestContract<TContractState> {
        fn write_felt(ref self: TContractState, key: felt252, value: u128);
        fn read_felt(self: @TContractState, key: felt252) -> u128;
        fn is_deleted_felt(self: @TContractState, key: felt252) -> bool;
        fn write_generic(ref self: TContractState, key: ContractAddress, value: u128);
        fn read_generic(self: @TContractState, key: ContractAddress) -> u128;
        fn get_all(self: @TContractState) -> Span<(felt252, u128)>;
        fn remove(ref self: TContractState, key: felt252);
        fn clear(ref self: TContractState);
    }

    #[starknet::contract]
    mod TestContract {
        use starknet::ContractAddress;
        use starknet::storage::StorageAsPath;
        use super::{
            LinkedIterableMapFelt, LinkedIterableMapIntoIterImpl, map_clear, map_is_deleted,
            map_iter, map_read, map_remove, map_write,
        };

        #[storage]
        struct Storage {
            map_felt: LinkedIterableMapFelt<felt252, u128>,
            map_generic: LinkedIterableMapFelt<ContractAddress, u128>,
        }

        #[abi(embed_v0)]
        impl TestContractImpl of super::ITestContract<ContractState> {
            fn write_felt(ref self: ContractState, key: felt252, value: u128) {
                map_write(self.map_felt.as_path(), key, value);
            }
            fn read_felt(self: @ContractState, key: felt252) -> u128 {
                map_read(self.map_felt.as_path(), key)
            }
            fn is_deleted_felt(self: @ContractState, key: felt252) -> bool {
                map_is_deleted(self.map_felt.as_path(), key)
            }
            fn write_generic(ref self: ContractState, key: ContractAddress, value: u128) {
                map_write(self.map_generic.as_path(), key, value);
            }
            fn read_generic(self: @ContractState, key: ContractAddress) -> u128 {
                map_read(self.map_generic.as_path(), key)
            }
            fn get_all(self: @ContractState) -> Span<(felt252, u128)> {
                let mut arr = array![];
                // Iterator works on StoragePath via IntoIterator
                for (k, v) in map_iter(self.map_felt.as_path()) {
                    arr.append((k, v));
                }
                arr.span()
            }
            fn remove(ref self: ContractState, key: felt252) {
                map_remove(self.map_felt.as_path(), key);
            }
            fn clear(ref self: ContractState) {
                map_clear(self.map_felt.as_path());
            }
        }
    }

    fn deploy() -> ITestContractDispatcher {
        let contract = declare("TestContract").unwrap().contract_class();
        let (addr, _) = contract.deploy(@array![]).unwrap();
        ITestContractDispatcher { contract_address: addr }
    }

    #[test]
    fn test_stack_order() {
        let dispatcher = deploy();

        // Insert A, then B, then C
        dispatcher.write_felt('A', 1);
        dispatcher.write_felt('B', 2);
        dispatcher.write_felt('C', 3);

        let items = dispatcher.get_all();

        // Expect Stack Order (LIFO): C, B, A
        assert(*items.at(0) == ('C', 3), 'First should be C');
        assert(*items.at(1) == ('B', 2), 'Second should be B');
        assert(*items.at(2) == ('A', 1), 'Third should be A');
    }

    #[test]
    fn test_generic_types() {
        let dispatcher = deploy();
        let addr: ContractAddress = 123.try_into().unwrap();

        dispatcher.write_generic(addr, 100);
        assert(dispatcher.read_generic(addr) == 100, 'Read generic failed');
    }

    #[test]
    fn test_remove_and_clear() {
        let dispatcher = deploy();
        dispatcher.write_felt('A', 1);
        dispatcher.write_felt('B', 2);

        dispatcher.remove('A');
        assert(dispatcher.read_felt('A') == 0, 'Remove failed');

        let items = dispatcher.get_all();
        assert(items.len() == 1, 'Len after remove wrong');
        assert(*items.at(0) == ('B', 2), 'Wrong item remaining');

        dispatcher.clear();
        assert(dispatcher.get_all().len() == 0, 'Clear failed');
    }

    #[test]
    fn test_is_deleted() {
        let dispatcher = deploy();
        dispatcher.write_felt('X', 1);
        assert(dispatcher.is_deleted_felt('X') == false, 'not deleted');

        dispatcher.remove('X');
        assert(dispatcher.is_deleted_felt('X') == true, 'deleted after remove');

        dispatcher.write_felt('X', 2);
        assert(dispatcher.is_deleted_felt('X') == false, 'reinsert clears deleted');
        assert(dispatcher.read_felt('X') == 2, 'reinsert readable');
    }

    #[test]
    fn test_large_felt_value() {
        let dispatcher = deploy();
        // Use value that fits in 160 bits
        // 2^160 - 1
        let val: u128 = 340282366920938463463374607431768211455;
        dispatcher.write_felt('LARGE', val);
        assert(dispatcher.read_felt('LARGE') == val, 'Read large failed');

        // Test update
        let val2: u128 = 12345;
        dispatcher.write_felt('LARGE', val2);
        assert(dispatcher.read_felt('LARGE') == val2, 'Read large update failed');
    }
}
