use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IIterableMapTestContract<TContractState> {
    fn get_value(ref self: TContractState, key: u8) -> Option<i32>;
    fn set_value(ref self: TContractState, key: u8, value: i32);
    fn get_all_values(ref self: TContractState) -> Span<(u8, i32)>;
    fn get_len(self: @TContractState) -> u64;
    fn remove(ref self: TContractState, key: u8);
    fn entry_and_read(ref self: TContractState, key: u8) -> Option<i32>;
    fn allocate_and_write(ref self: TContractState, key: u8, value: i32);
}

#[starknet::contract]
mod IterableMapTestContract {
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    };
    use starkware_utils::iterable_map::{
        IterableMap, IterableMapIntoIterImpl, IterableMapMutableTrait, IterableMapTrait,
    };

    #[storage]
    struct Storage {
        iterable_map: IterableMap<u8, i32>,
        iterable_map_of_maps: IterableMap<u8, Map<u8, i32>>,
    }

    #[abi(embed_v0)]
    impl IterableMapTestContractImpl of super::IIterableMapTestContract<ContractState> {
        fn get_value(ref self: ContractState, key: u8) -> Option<i32> {
            self.iterable_map.read(key)
        }

        fn set_value(ref self: ContractState, key: u8, value: i32) {
            self.iterable_map.write(key, value);
        }

        fn get_all_values(ref self: ContractState) -> Span<(u8, i32)> {
            let mut array = array![];
            for (key, value) in self.iterable_map {
                array.append((key, value.read()));
            }

            array.span()
        }

        fn get_len(self: @ContractState) -> u64 {
            self.iterable_map.len()
        }

        fn remove(ref self: ContractState, key: u8) {
            self.iterable_map.remove(key);
        }

        fn entry_and_read(ref self: ContractState, key: u8) -> Option<i32> {
            let map = self.iterable_map_of_maps.entry(key)?;
            Option::Some(map.read(key))
        }

        fn allocate_and_write(ref self: ContractState, key: u8, value: i32) {
            let map = self.iterable_map_of_maps.allocate(key);
            map.write(key, value);
        }
    }
}


fn deploy_iterable_map_test_contract() -> ContractAddress {
    let contract = declare("IterableMapTestContract").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

#[test]
fn test_read_and_write() {
    let dispatcher = IIterableMapTestContractDispatcher {
        contract_address: deploy_iterable_map_test_contract(),
    };

    assert_eq!(dispatcher.get_value(1_u8), Option::None);
    dispatcher.set_value(1_u8, -10_i32);
    assert_eq!(dispatcher.get_value(1_u8), Option::Some(-10_i32));
}

#[test]
fn test_empty_map() {
    let dispatcher = IIterableMapTestContractDispatcher {
        contract_address: deploy_iterable_map_test_contract(),
    };

    assert_eq!(dispatcher.get_all_values().len(), 0);
}

#[test]
fn test_multiple_writes() {
    let dispatcher = IIterableMapTestContractDispatcher {
        contract_address: deploy_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u8, -10_i32);
    assert_eq!(dispatcher.get_value(1_u8), Option::Some(-10_i32));
    dispatcher.set_value(1_u8, -20_i32);
    assert_eq!(dispatcher.get_value(1_u8), Option::Some(-20_i32));

    assert_eq!(dispatcher.get_all_values().len(), 1);
}

#[test]
fn test_allocate_and_entry() {
    let dispatcher = IIterableMapTestContractDispatcher {
        contract_address: deploy_iterable_map_test_contract(),
    };

    assert_eq!(dispatcher.entry_and_read(1_u8), Option::None);
    dispatcher.allocate_and_write(1_u8, -10_i32);
    assert_eq!(dispatcher.entry_and_read(1_u8), Option::Some(-10_i32));
}

#[test]
fn test_iterator() {
    let dispatcher = IIterableMapTestContractDispatcher {
        contract_address: deploy_iterable_map_test_contract(),
    };

    let inserted_pairs = array![(1_u8, -10_i32), (2_u8, -20_i32), (3_u8, -30_i32)].span();

    for (key, value) in inserted_pairs {
        dispatcher.set_value(*key, *value);
    }

    let mut read_pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        read_pairs.append((*key, *value));
    }

    let read_pairs = read_pairs.span();
    assert_eq!(read_pairs.len(), inserted_pairs.len());
    for i in 0..read_pairs.len() {
        assert_eq!(inserted_pairs.at(i), read_pairs.at(i));
    }
}

#[test]
fn test_len() {
    let dispatcher = IIterableMapTestContractDispatcher {
        contract_address: deploy_iterable_map_test_contract(),
    };

    let mut expected_len = 0;
    assert_eq!(dispatcher.get_len(), expected_len);

    let inserted_pairs = array![(1_u8, -10_i32), (2_u8, -20_i32), (3_u8, -30_i32)].span();

    for (key, value) in inserted_pairs {
        dispatcher.set_value(*key, *value);
        expected_len += 1;
        assert_eq!(dispatcher.get_len(), expected_len);
    };
}

fn test_remove(inserted_pairs: Span<(u8, i32)>, removed_key: u8, expected_pairs: Span<(u8, i32)>) {
    let dispatcher = IIterableMapTestContractDispatcher {
        contract_address: deploy_iterable_map_test_contract(),
    };

    for (key, value) in inserted_pairs {
        dispatcher.set_value(*key, *value);
    }

    dispatcher.remove(removed_key);
    assert_eq!(dispatcher.get_value(removed_key), Option::None);

    let mut read_pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        read_pairs.append((*key, *value));
    }
    let read_pairs = read_pairs.span();

    assert_eq!(read_pairs.len(), expected_pairs.len());

    for i in 0..read_pairs.len() {
        assert_eq!(expected_pairs.at(i), read_pairs.at(i));
    }

    // Trying to remove it again does not matter
    dispatcher.remove(removed_key);
    assert_eq!(dispatcher.get_value(removed_key), Option::None);

    let mut read_pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        read_pairs.append((*key, *value));
    }
    let read_pairs = read_pairs.span();

    assert_eq!(read_pairs.len(), expected_pairs.len());

    for i in 0..read_pairs.len() {
        assert_eq!(expected_pairs.at(i), read_pairs.at(i));
    }
}

#[test]
fn test_remove_first() {
    test_remove(
        inserted_pairs: array![(1_u8, -10_i32), (2_u8, -20_i32), (3_u8, -30_i32)].span(),
        removed_key: 1_u8,
        expected_pairs: array![(3_u8, -30_i32), (2_u8, -20_i32)].span(),
    );
}

#[test]
fn test_remove_second() {
    test_remove(
        inserted_pairs: array![(1_u8, -10_i32), (2_u8, -20_i32), (3_u8, -30_i32)].span(),
        removed_key: 2_u8,
        expected_pairs: array![(1_u8, -10_i32), (3_u8, -30_i32)].span(),
    );
}

#[test]
fn test_remove_third() {
    test_remove(
        inserted_pairs: array![(1_u8, -10_i32), (2_u8, -20_i32), (3_u8, -30_i32)].span(),
        removed_key: 3_u8,
        expected_pairs: array![(1_u8, -10_i32), (2_u8, -20_i32)].span(),
    );
}

#[test]
fn test_remove_forth_not_added() {
    test_remove(
        inserted_pairs: array![(1_u8, -10_i32), (2_u8, -20_i32), (3_u8, -30_i32)].span(),
        removed_key: 4_u8,
        expected_pairs: array![(1_u8, -10_i32), (2_u8, -20_i32), (3_u8, -30_i32)].span(),
    );
}

#[test]
fn test_remove_empty() {
    let dispatcher = IIterableMapTestContractDispatcher {
        contract_address: deploy_iterable_map_test_contract(),
    };

    dispatcher.remove(3_u8);
    assert_eq!(dispatcher.get_value(3_u8), Option::None);

    let mut read_pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        read_pairs.append((*key, *value));
    }
    let read_pairs = read_pairs.span();
    assert_eq!(read_pairs.len(), 0);
}
