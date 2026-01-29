#[cfg(test)]
mod tests {
    use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
    use starknet::{ContractAddress, EthAddress};
    use starkware_utils::storage::linked_iterable_map_felt::{
        LinkedIterableMapFelt, LinkedIterableMapFeltReadAccess, LinkedIterableMapFeltTrait,
        LinkedIterableMapFeltWriteAccess, LinkedIterableMapIntoIterImpl,
        MutableLinkedIterableMapFeltTrait,
    };

    #[starknet::interface]
    trait ITestContract<TContractState> {
        fn write_felt(ref self: TContractState, key: felt252, value: u128);
        fn read_felt(self: @TContractState, key: felt252) -> u128;
        fn exists_felt(self: @TContractState, key: felt252) -> bool;
        fn is_deleted_felt(self: @TContractState, key: felt252) -> bool;
        fn get_len(self: @TContractState) -> u32;
        fn write_generic(ref self: TContractState, key: ContractAddress, value: u128);
        fn read_generic(self: @TContractState, key: ContractAddress) -> u128;
        fn get_all(self: @TContractState) -> Span<(felt252, u128)>;
        fn remove(ref self: TContractState, key: felt252);
        fn clear(ref self: TContractState);
        fn write_eth(ref self: TContractState, key: felt252, value: EthAddress);
        fn read_eth(self: @TContractState, key: felt252) -> EthAddress;
        fn get_all_eth(self: @TContractState) -> Span<(felt252, EthAddress)>;
        fn write_i128(ref self: TContractState, key: i128, value: u128);
        fn read_i128(self: @TContractState, key: i128) -> u128;
        fn get_all_i128(self: @TContractState) -> Span<(i128, u128)>;
        fn get_len_i128(self: @TContractState) -> u32;
        fn remove_i128(ref self: TContractState, key: i128);
    }

    #[starknet::contract]
    mod TestContract {
        use starknet::{ContractAddress, EthAddress};
        use crate::storage::linked_iterable_map_felt::{
            LinkedIterableMapFeltDeletedTrait, LinkedIterableMapFeltExistsTrait,
        };
        use super::{
            LinkedIterableMapFelt, LinkedIterableMapFeltReadAccess, LinkedIterableMapFeltTrait,
            LinkedIterableMapFeltWriteAccess, LinkedIterableMapIntoIterImpl,
            MutableLinkedIterableMapFeltTrait,
        };

        #[storage]
        struct Storage {
            map_felt: LinkedIterableMapFelt<felt252, u128>,
            map_generic: LinkedIterableMapFelt<ContractAddress, u128>,
            map_eth: LinkedIterableMapFelt<felt252, EthAddress>,
            map_i128: LinkedIterableMapFelt<i128, u128>,
        }

        #[abi(embed_v0)]
        impl TestContractImpl of super::ITestContract<ContractState> {
            fn write_felt(ref self: ContractState, key: felt252, value: u128) {
                self.map_felt.write(key, value);
            }
            fn read_felt(self: @ContractState, key: felt252) -> u128 {
                self.map_felt.read(key)
            }
            fn exists_felt(self: @ContractState, key: felt252) -> bool {
                self.map_felt.exists(key)
            }
            fn is_deleted_felt(self: @ContractState, key: felt252) -> bool {
                self.map_felt.is_deleted(key)
            }
            fn get_len(self: @ContractState) -> u32 {
                self.map_felt.len()
            }
            fn write_generic(ref self: ContractState, key: ContractAddress, value: u128) {
                self.map_generic.write(key, value);
            }
            fn read_generic(self: @ContractState, key: ContractAddress) -> u128 {
                self.map_generic.read(key)
            }
            fn get_all(self: @ContractState) -> Span<(felt252, u128)> {
                let mut arr = array![];
                // Iterator works on StoragePath via IntoIterator
                for (k, v) in self.map_felt {
                    arr.append((k, v));
                }
                arr.span()
            }
            fn remove(ref self: ContractState, key: felt252) {
                self.map_felt.remove(key);
            }
            fn clear(ref self: ContractState) {
                self.map_felt.clear();
            }
            fn write_eth(ref self: ContractState, key: felt252, value: EthAddress) {
                self.map_eth.write(key, value);
            }
            fn read_eth(self: @ContractState, key: felt252) -> EthAddress {
                self.map_eth.read(key)
            }
            fn get_all_eth(self: @ContractState) -> Span<(felt252, EthAddress)> {
                let mut arr = array![];
                for (k, v) in self.map_eth {
                    arr.append((k, v));
                }
                arr.span()
            }
            fn write_i128(ref self: ContractState, key: i128, value: u128) {
                self.map_i128.write(key, value);
            }
            fn read_i128(self: @ContractState, key: i128) -> u128 {
                self.map_i128.read(key)
            }
            fn get_all_i128(self: @ContractState) -> Span<(i128, u128)> {
                let mut arr = array![];
                for (k, v) in self.map_i128 {
                    arr.append((k, v));
                }
                arr.span()
            }
            fn get_len_i128(self: @ContractState) -> u32 {
                self.map_i128.len()
            }
            fn remove_i128(ref self: ContractState, key: i128) {
                self.map_i128.remove(key);
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
    fn test_key_zero() {
        let dispatcher = deploy();
        // Key 0 (felt252 zero) is valid; _head uses 0 only for empty list
        dispatcher.write_felt(0, 1);
        assert(dispatcher.read_felt(0) == 1, 'Read key 0');
        assert(dispatcher.get_len() == 1, 'Len with key 0');
        let items = dispatcher.get_all();
        assert(items.len() == 1, 'Iter len 1');
        assert(*items.at(0) == (0, 1), 'Iter includes key 0');

        dispatcher.write_felt('A', 2);
        assert(dispatcher.get_len() == 2, 'Len with 0 and A');
        dispatcher.remove(0);
        assert(dispatcher.read_felt(0) == 0, 'Read key 0 after remove');
        assert(dispatcher.get_len() == 1, 'Len after remove 0');
        dispatcher.write_felt(0, 10);
        assert(dispatcher.read_felt(0) == 10, 'Reinsert key 0');
        assert(dispatcher.get_len() == 2, 'Len after reinsert 0');
    }

    #[test]
    fn test_reinsert_preserves_position() {
        let dispatcher = deploy();
        // Insert A, B, C -> iteration order C, B, A (LIFO)
        dispatcher.write_felt('A', 1);
        dispatcher.write_felt('B', 2);
        dispatcher.write_felt('C', 3);
        let items = dispatcher.get_all();
        assert(*items.at(0) == ('C', 3), 'First C');
        assert(*items.at(1) == ('B', 2), 'Second B');
        assert(*items.at(2) == ('A', 1), 'Third A');

        dispatcher.remove('B');
        dispatcher.write_felt('B', 20); // Reinsert: does not move to head
        assert(dispatcher.read_felt('B') == 20, 'Reinsert value');
        assert(dispatcher.get_len() == 3, 'Len 3 after reinsert');
        let items2 = dispatcher.get_all();
        // Order must stay C, B, A (reinserted B keeps its position)
        assert(*items2.at(0) == ('C', 3), 'First still C');
        assert(*items2.at(1) == ('B', 20), 'Second still B');
        assert(*items2.at(2) == ('A', 1), 'Third still A');
    }

    #[test]
    fn test_exists() {
        let dispatcher = deploy();
        // Missing key
        assert(dispatcher.exists_felt('M') == false, 'missing -> exists false');
        assert(dispatcher.is_deleted_felt('M') == false, 'missing -> is_deleted false');

        dispatcher.write_felt('M', 1);
        assert(dispatcher.exists_felt('M') == true, 'after write -> exists true');
        assert(dispatcher.is_deleted_felt('M') == false, 'after write -> is_deleted false');

        dispatcher.remove('M');
        assert(dispatcher.exists_felt('M') == false, 'after remove -> exists false');
        assert(dispatcher.is_deleted_felt('M') == true, 'after remove -> is_deleted true');
        assert(dispatcher.read_felt('M') == 0, 'after remove read 0');

        // Stored value 0: read returns 0 but exists distinguishes from absent/deleted
        dispatcher.write_felt('Z', 0);
        assert(dispatcher.exists_felt('Z') == true, 'zero value -> exists true');
        assert(dispatcher.read_felt('Z') == 0, 'zero value read 0');
    }

    #[test]
    fn test_large_felt_value() {
        let dispatcher = deploy();
        // Max u128 (2^128 - 1) in the u128-valued map
        let val_u128: u128 = 340282366920938463463374607431768211455;
        dispatcher.write_felt('LARGE', val_u128);
        assert(dispatcher.read_felt('LARGE') == val_u128, 'Read large u128 failed');
        let val2: u128 = 12345;
        dispatcher.write_felt('LARGE', val2);
        assert(dispatcher.read_felt('LARGE') == val2, 'Read large update failed');

        // 160-bit value via EthAddress (uses full 160-bit storage; high 32 bits can be non-zero)
        let val_160: EthAddress = 0x1234567890abcdef1234567890abcdef12345678.try_into().unwrap();
        dispatcher.write_eth('ETH', val_160);
        assert(dispatcher.read_eth('ETH') == val_160, 'Read 160-bit EthAddress failed');
        let all_eth = dispatcher.get_all_eth();
        assert(all_eth.len() == 1, 'Iter len 1 for eth');
        assert(*all_eth.at(0) == ('ETH', val_160), 'Iter 160-bit value');
    }

    #[test]
    fn test_empty_map() {
        let dispatcher = deploy();
        assert(dispatcher.get_all().len() == 0, 'Empty map should have no items');
        assert(dispatcher.get_len() == 0, 'Empty map len should be 0');
    }

    #[test]
    fn test_iterator() {
        let dispatcher = deploy();
        dispatcher.write_felt('A', 1);
        dispatcher.write_felt('B', 2);
        dispatcher.write_felt('C', 3);

        let inserted = array![('C', 3_u128), ('B', 2_u128), ('A', 1_u128)].span();
        let mut read_pairs = array![];
        for (k, v) in dispatcher.get_all() {
            read_pairs.append((*k, *v));
        }
        let read_pairs = read_pairs.span();
        assert(read_pairs.len() == inserted.len(), 'Iterator length mismatch');
        for i in 0..inserted.len() {
            assert(*read_pairs.at(i) == *inserted.at(i), 'Iterator item mismatch');
        }
    }

    #[test]
    fn test_len() {
        let dispatcher = deploy();
        assert(dispatcher.get_len() == 0, 'Initial len');
        dispatcher.write_felt('A', 1);
        assert(dispatcher.get_len() == 1, 'Len after first insert');
        dispatcher.write_felt('B', 2);
        assert(dispatcher.get_len() == 2, 'Len after second insert');
        dispatcher.remove('A');
        assert(dispatcher.get_len() == 1, 'Len after remove');
        dispatcher.clear();
        assert(dispatcher.get_len() == 0, 'Len after clear');
    }

    #[test]
    fn test_multiple_writes() {
        let dispatcher = deploy();
        dispatcher.write_felt('K', 10);
        assert(dispatcher.read_felt('K') == 10, 'First write');
        dispatcher.write_felt('K', 20);
        assert(dispatcher.read_felt('K') == 20, 'Second write');
        assert(dispatcher.get_all().len() == 1, 'Still one entry');
        assert(dispatcher.get_len() == 1, 'Len still 1');
    }

    #[test]
    fn test_clear() {
        let dispatcher = deploy();
        dispatcher.write_felt('A', 1);
        dispatcher.write_felt('B', 2);
        dispatcher.write_felt('C', 3);
        assert(dispatcher.get_len() == 3, 'Len before clear');
        dispatcher.clear();
        assert(dispatcher.get_len() == 0, 'Len after clear');
        assert(dispatcher.get_all().len() == 0, 'Iterator empty after clear');
        assert(dispatcher.read_felt('A') == 0, 'Read A after clear');
        assert(dispatcher.read_felt('B') == 0, 'Read B after clear');
        assert(dispatcher.read_felt('C') == 0, 'Read C after clear');
        dispatcher.clear();
        assert(dispatcher.get_len() == 0, 'Len after second clear');
    }

    #[test]
    fn test_multiple_updates_same_key() {
        let dispatcher = deploy();
        dispatcher.write_felt('X', 1);
        dispatcher.write_felt('X', 2);
        dispatcher.write_felt('X', 3);
        assert(dispatcher.read_felt('X') == 3, 'Final value');
        assert(dispatcher.get_len() == 1, 'Len is 1');
    }

    #[test]
    fn test_zero_value() {
        let dispatcher = deploy();
        dispatcher.write_felt('Z', 0);
        assert(dispatcher.read_felt('Z') == 0, 'Read zero');
        assert(dispatcher.get_len() == 1, 'Len with zero value');
        dispatcher.write_felt('Z', 42);
        assert(dispatcher.read_felt('Z') == 42, 'Read after update');
    }

    #[test]
    fn test_iterator_empty_after_clear() {
        let dispatcher = deploy();
        dispatcher.write_felt('A', 1);
        dispatcher.write_felt('B', 2);
        dispatcher.clear();
        let mut count = 0_u32;
        for _ in dispatcher.get_all() {
            count += 1;
        }
        assert(count == 0, 'empty after clear');
    }

    #[test]
    fn test_clear_and_reinsert() {
        let dispatcher = deploy();
        dispatcher.write_felt('A', 1);
        dispatcher.write_felt('B', 2);
        dispatcher.clear();
        assert(dispatcher.get_len() == 0, 'Len after clear');
        assert(dispatcher.read_felt('A') == 0, 'A zero after clear');
        assert(dispatcher.read_felt('B') == 0, 'B zero after clear');
        dispatcher.write_felt('A', 100);
        dispatcher.write_felt('B', 200);
        assert(dispatcher.get_len() == 2, 'Len after reinsert');
        assert(dispatcher.read_felt('A') == 100, 'A after reinsert');
        assert(dispatcher.read_felt('B') == 200, 'B after reinsert');
    }

    #[test]
    fn test_signed_key_i128() {
        let dispatcher = deploy();
        // Negative keys use offset encoding; raw .into() would overflow near P
        dispatcher.write_i128(-1_i128, 100);
        dispatcher.write_i128(-1000_i128, 200);
        dispatcher.write_i128(0_i128, 300);
        dispatcher.write_i128(42_i128, 400);

        assert(dispatcher.read_i128(-1_i128) == 100, 'read -1');
        assert(dispatcher.read_i128(-1000_i128) == 200, 'read -1000');
        assert(dispatcher.read_i128(0_i128) == 300, 'read 0');
        assert(dispatcher.read_i128(42_i128) == 400, 'read 42');

        assert(dispatcher.get_len_i128() == 4, 'len 4');

        let all = dispatcher.get_all_i128();
        assert(all.len() == 4, 'iter len 4');
        for (k, v) in all {
            assert(dispatcher.read_i128(*k) == *v, 'iter matches read');
        }

        dispatcher.remove_i128(-1000_i128);
        assert(dispatcher.read_i128(-1000_i128) == 0, 'read removed');
        assert(dispatcher.get_len_i128() == 3, 'len after remove');
    }

    #[test]
    fn test_signed_key_i128_extreme() {
        let dispatcher = deploy();
        // Min/max i128: offset encoding keeps them in safe felt range
        let min_i128: i128 = -170141183460469231731687303715884105728;
        let max_i128: i128 = 170141183460469231731687303715884105727;
        dispatcher.write_i128(min_i128, 1);
        dispatcher.write_i128(max_i128, 2);
        assert(dispatcher.read_i128(min_i128) == 1, 'read min');
        assert(dispatcher.read_i128(max_i128) == 2, 'read max');
        assert(dispatcher.get_len_i128() == 2, 'len 2');
    }
}
