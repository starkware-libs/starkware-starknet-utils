use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::{ContractAddress, EthAddress};

#[starknet::interface]
pub trait ILinkedIterableMapTestContract<TContractState> {
    fn get_value(ref self: TContractState, key: u64) -> u128;
    fn set_value(ref self: TContractState, key: u64, value: u128);
    fn get_all_values(ref self: TContractState) -> Span<(u64, u128)>;
    fn get_len(self: @TContractState) -> u32;
    fn clear(ref self: TContractState);
    fn remove(ref self: TContractState, key: u64);
    fn is_deleted(self: @TContractState, key: u64) -> bool;

    // New methods for the second map (u32, EthAddress)
    fn get_value2(ref self: TContractState, key: u32) -> EthAddress;
    fn set_value2(ref self: TContractState, key: u32, value: EthAddress);
    fn get_all_values2(ref self: TContractState) -> Span<(u32, EthAddress)>;
    fn get_len2(self: @TContractState) -> u32;

    // New methods for the third map (i64, u128)
    fn get_value3(ref self: TContractState, key: i64) -> u128;
    fn set_value3(ref self: TContractState, key: i64, value: u128);

    fn get_all_values3(ref self: TContractState) -> Span<(i64, u128)>;
    fn get_len3(self: @TContractState) -> u32;

    // Methods for the fourth map (u64, i64) - signed VALUE type
    fn get_value_signed(ref self: TContractState, key: u64) -> i64;
    fn set_value_signed(ref self: TContractState, key: u64, value: i64);
    fn get_len_signed(self: @TContractState) -> u32;
}

#[starknet::contract]
mod LinkedIterableMapTestContract {
    use starknet::EthAddress;
    use starkware_utils::storage::linked_iterable_map::{
        LinkedIterableMap, LinkedIterableMapDeletedTrait, LinkedIterableMapIntoIterImpl,
        LinkedIterableMapReadAccess, LinkedIterableMapTrait, LinkedIterableMapWriteAccess,
        MutableLinkedIterableMapTrait,
    };

    #[storage]
    struct Storage {
        linked_map: LinkedIterableMap<u64, u128>,
        linked_map2: LinkedIterableMap<u32, EthAddress>,
        linked_map3: LinkedIterableMap<i64, u128>,
        linked_map_signed_value: LinkedIterableMap<u64, i64>,
    }

    #[abi(embed_v0)]
    impl LinkedIterableMapTestContractImpl of super::ILinkedIterableMapTestContract<ContractState> {
        fn get_value(ref self: ContractState, key: u64) -> u128 {
            self.linked_map.read(key)
        }

        fn set_value(ref self: ContractState, key: u64, value: u128) {
            self.linked_map.write(key, value);
        }

        fn get_all_values(ref self: ContractState) -> Span<(u64, u128)> {
            let mut array = array![];
            for (key, value) in self.linked_map {
                array.append((key, value));
            }

            array.span()
        }

        fn get_len(self: @ContractState) -> u32 {
            LinkedIterableMapTrait::len(self.linked_map)
        }

        fn clear(ref self: ContractState) {
            self.linked_map.clear();
        }

        fn remove(ref self: ContractState, key: u64) {
            self.linked_map.remove(key);
        }

        fn is_deleted(self: @ContractState, key: u64) -> bool {
            LinkedIterableMapDeletedTrait::is_deleted(self.linked_map, key)
        }

        // Implementations for the second map
        fn get_value2(ref self: ContractState, key: u32) -> EthAddress {
            self.linked_map2.read(key)
        }

        fn set_value2(ref self: ContractState, key: u32, value: EthAddress) {
            self.linked_map2.write(key, value);
        }

        fn get_all_values2(ref self: ContractState) -> Span<(u32, EthAddress)> {
            let mut array = array![];
            for (key, value) in self.linked_map2 {
                array.append((key, value));
            }

            array.span()
        }

        fn get_len2(self: @ContractState) -> u32 {
            LinkedIterableMapTrait::len(self.linked_map2)
        }

        // Implementations for the third map
        fn get_value3(ref self: ContractState, key: i64) -> u128 {
            self.linked_map3.read(key)
        }

        fn set_value3(ref self: ContractState, key: i64, value: u128) {
            self.linked_map3.write(key, value);
        }

        fn get_all_values3(ref self: ContractState) -> Span<(i64, u128)> {
            let mut array = array![];
            for (key, value) in self.linked_map3 {
                array.append((key, value));
            }

            array.span()
        }

        fn get_len3(self: @ContractState) -> u32 {
            LinkedIterableMapTrait::len(self.linked_map3)
        }

        // Implementations for the fourth map (u64, i64) - signed VALUE type
        fn get_value_signed(ref self: ContractState, key: u64) -> i64 {
            self.linked_map_signed_value.read(key)
        }

        fn set_value_signed(ref self: ContractState, key: u64, value: i64) {
            self.linked_map_signed_value.write(key, value);
        }

        fn get_len_signed(self: @ContractState) -> u32 {
            LinkedIterableMapTrait::len(self.linked_map_signed_value)
        }
    }
}

fn deploy_linked_iterable_map_test_contract() -> ContractAddress {
    let contract = declare("LinkedIterableMapTestContract").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

#[test]
fn test_read_and_write() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };
    assert_eq!(dispatcher.get_value(1_u64), 0_u128);
    dispatcher.set_value(1_u64, 10_u128);
    assert_eq!(dispatcher.get_value(1_u64), 10_u128);
}

#[test]
fn test_empty_map() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };
    assert_eq!(dispatcher.get_all_values().len(), 0);
}

#[test]
fn test_multiple_writes() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);
    assert_eq!(dispatcher.get_value(1_u64), 10_u128);

    // Update existing entry - LinkedIterableMap avoids redundant read here!
    dispatcher.set_value(1_u64, 20_u128);
    assert_eq!(dispatcher.get_value(1_u64), 20_u128);

    assert_eq!(dispatcher.get_all_values().len(), 1);
}

#[test]
fn test_iterator() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    let inserted_pairs = array![(1_u64, 10_u128), (2_u64, 20_u128), (3_u64, 30_u128)].span();

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
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    let mut expected_len: u32 = 0;
    assert_eq!(dispatcher.get_len(), expected_len);

    let inserted_pairs = array![(1_u64, 10_u128), (2_u64, 20_u128), (3_u64, 30_u128)].span();

    for (key, value) in inserted_pairs {
        dispatcher.set_value(*key, *value);
        expected_len += 1;
        assert_eq!(dispatcher.get_len(), expected_len);
    }
}

#[test]
fn test_clear() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);
    dispatcher.set_value(3_u64, 30_u128);

    assert_eq!(dispatcher.get_len(), 3);
    assert_eq!(dispatcher.get_value(1_u64), 10_u128.into());
    assert_eq!(dispatcher.get_value(2_u64), 20_u128.into());
    assert_eq!(dispatcher.get_value(3_u64), 30_u128.into());

    dispatcher.clear();

    assert_eq!(dispatcher.get_len(), 0);
    assert_eq!(dispatcher.get_all_values().len(), 0);

    assert_eq!(dispatcher.get_value(1_u64), 0_u128);
    assert_eq!(dispatcher.get_value(2_u64), 0_u128);
    assert_eq!(dispatcher.get_value(3_u64), 0_u128);

    // Clear empty map
    dispatcher.clear();

    assert_eq!(dispatcher.get_len(), 0);
}

#[test]
fn test_multiple_updates_same_key() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Insert
    dispatcher.set_value(5_u64, 10_u128);
    assert_eq!(dispatcher.get_value(5_u64), 10_u128.into());
    assert_eq!(dispatcher.get_len(), 1);

    // Update multiple times - LinkedIterableMap avoids redundant reads!

    dispatcher.set_value(5_u64, 40_u128);
    assert_eq!(dispatcher.get_value(5_u64), 40_u128.into());
    assert_eq!(dispatcher.get_len(), 1);

    let count: u128 = 3;
    for i in 0..count {
        dispatcher.set_value(5_u64, 10 + i);
        assert_eq!(dispatcher.get_value(5_u64), 10 + i);
        assert_eq!(dispatcher.get_len(), 1);
    }

    // Should still have only one element
    let mut values = array![];
    for (key, value) in dispatcher.get_all_values() {
        values.append((*key, *value));
    }
    let values = values.span();
    assert_eq!(values.len(), 1);
    let (k, v) = values.at(0);
    assert_eq!(*k, 5_u64);
    assert_eq!(*v, 12_u128);
}

#[test]
fn test_insertion_order_preserved() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Insert in specific order
    let keys = array![10_u64, 20_u64, 30_u64, 40_u64, 50_u64].span();
    for key in keys {
        dispatcher.set_value(*key, (*key).try_into().unwrap());
    }

    // Verify order is preserved
    let mut read_keys = array![];
    for (key, _) in dispatcher.get_all_values() {
        read_keys.append(*key);
    }
    let read_keys = read_keys.span();

    assert_eq!(read_keys.len(), 5);
    assert_eq!(*read_keys.at(0), 10_u64);
    assert_eq!(*read_keys.at(1), 20_u64);
    assert_eq!(*read_keys.at(2), 30_u64);
    assert_eq!(*read_keys.at(3), 40_u64);
    assert_eq!(*read_keys.at(4), 50_u64);
}

#[test]
fn test_update_preserves_order() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Insert keys
    dispatcher.set_value(1_u64, 100_u128);
    dispatcher.set_value(2_u64, 200_u128);
    dispatcher.set_value(3_u64, 300_u128);

    // Update middle key
    dispatcher.set_value(2_u64, 250_u128);

    // Verify order is still preserved
    let mut read_pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        read_pairs.append((*key, *value));
    }
    let read_pairs = read_pairs.span();

    assert_eq!(read_pairs.len(), 3);
    let (k0, v0) = read_pairs.at(0);
    assert_eq!(*k0, 1_u64);
    assert_eq!(*v0, 100_u128);
    let (k1, v1) = read_pairs.at(1);
    assert_eq!(*k1, 2_u64);
    assert_eq!(*v1, 250_u128); // Updated value
    let (k2, v2) = read_pairs.at(2);
    assert_eq!(*k2, 3_u64);
    assert_eq!(*v2, 300_u128);
}

#[test]
fn test_large_map() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Insert many elements
    let count: u32 = 50;
    let count_u64: u64 = count.into();
    for i in 0..count_u64 {
        dispatcher.set_value(i, (i * 10).try_into().unwrap());
    }

    assert_eq!(dispatcher.get_len(), count);

    // Verify all values
    let mut count_verified: u32 = 0;
    for (key, value) in dispatcher.get_all_values() {
        assert_eq!(*value, ((*key) * 10).try_into().unwrap());
        count_verified += 1;
    }
    assert_eq!(count_verified, count);
}

#[test]
fn test_zero_value() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(0_u64, 0_u128);
    assert_eq!(dispatcher.get_value(0_u64), 0_u128.into());
    assert_eq!(dispatcher.get_len(), 1);

    // Update to different value
    dispatcher.set_value(0_u64, 42_u128);
    assert_eq!(dispatcher.get_value(0_u64), 42_u128.into());
    assert_eq!(dispatcher.get_len(), 1);
}


#[test]
fn test_clear_and_reinsert() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Insert and clear
    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);
    dispatcher.clear();

    assert_eq!(dispatcher.get_len(), 0);
    assert_eq!(dispatcher.get_value(1_u64), 0_u128);
    assert_eq!(dispatcher.get_value(2_u64), 0_u128);

    // Reinsert same keys
    dispatcher.set_value(1_u64, 100_u128);
    dispatcher.set_value(2_u64, 200_u128);

    assert_eq!(dispatcher.get_len(), 2);
    assert_eq!(dispatcher.get_value(1_u64), 100_u128.into());
    assert_eq!(dispatcher.get_value(2_u64), 200_u128.into());
}

#[test]
fn test_mixed_operations() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Insert
    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);
    dispatcher.set_value(3_u64, 30_u128);

    // Update
    dispatcher.set_value(2_u64, 25_u128);

    // Insert more
    dispatcher.set_value(4_u64, 40_u128);
    dispatcher.set_value(5_u64, 50_u128);

    // Update again
    dispatcher.set_value(1_u64, 15_u128);
    dispatcher.set_value(5_u64, 55_u128);

    assert_eq!(dispatcher.get_len(), 5);

    let mut pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        pairs.append((*key, *value));
    }
    let pairs = pairs.span();

    assert_eq!(pairs.len(), 5);
    // Verify values directly - order should be preserved
    // Since we inserted 1,2,3 then updated 2, then inserted 4,5 then updated 1,5
    // Order should be: 1(15), 2(25), 3(30), 4(40), 5(55)
    let (k0, v0) = pairs.at(0);
    assert_eq!(*k0, 1_u64);
    assert_eq!(*v0, 15_u128);
    let (k1, v1) = pairs.at(1);
    assert_eq!(*k1, 2_u64);
    assert_eq!(*v1, 25_u128);
    let (k2, v2) = pairs.at(2);
    assert_eq!(*k2, 3_u64);
    assert_eq!(*v2, 30_u128);
    let (k3, v3) = pairs.at(3);
    assert_eq!(*k3, 4_u64);
    assert_eq!(*v3, 40_u128);
    let (k4, v4) = pairs.at(4);
    assert_eq!(*k4, 5_u64);
    assert_eq!(*v4, 55_u128);
}


#[test]
fn test_iterator_empty_after_clear() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);
    dispatcher.clear();

    // Iterator should return nothing
    let mut count = 0_u64;
    for _ in dispatcher.get_all_values() {
        count += 1;
    }
    assert_eq!(count, 0);
}

#[test]
fn test_remove() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Insert keys
    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);
    dispatcher.set_value(3_u64, 30_u128);

    assert_eq!(dispatcher.get_len(), 3);
    assert_eq!(dispatcher.get_value(1_u64), 10_u128.into());
    assert_eq!(dispatcher.get_value(2_u64), 20_u128.into());
    assert_eq!(dispatcher.get_value(3_u64), 30_u128.into());

    // Remove middle key
    dispatcher.remove(2_u64);
    assert_eq!(dispatcher.get_len(), 2);
    assert_eq!(dispatcher.get_value(2_u64), 0_u128);
    assert_eq!(dispatcher.is_deleted(2_u64), true);
    assert_eq!(dispatcher.get_value(1_u64), 10_u128.into());
    assert_eq!(dispatcher.get_value(3_u64), 30_u128.into());

    // Verify iterator skips deleted item
    let mut pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        pairs.append((*key, *value));
    }
    let pairs = pairs.span();
    assert_eq!(pairs.len(), 2);
    let (k0, v0) = pairs.at(0);
    assert_eq!(*k0, 1_u64);
    assert_eq!(*v0, 10_u128);
    let (k1, v1) = pairs.at(1);
    assert_eq!(*k1, 3_u64);
    assert_eq!(*v1, 30_u128);
}

#[test]
fn test_remove_head() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);
    dispatcher.set_value(3_u64, 30_u128);

    // Remove head
    dispatcher.remove(1_u64);
    assert_eq!(dispatcher.get_len(), 2);
    assert_eq!(dispatcher.get_value(1_u64), 0_u128);
    assert_eq!(dispatcher.is_deleted(1_u64), true);

    // Verify remaining items
    let mut pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        pairs.append((*key, *value));
    }
    let pairs = pairs.span();
    assert_eq!(pairs.len(), 2);
}

#[test]
fn test_remove_tail() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);
    dispatcher.set_value(3_u64, 30_u128);

    // Remove tail
    dispatcher.remove(3_u64);
    assert_eq!(dispatcher.get_len(), 2);
    assert_eq!(dispatcher.get_value(3_u64), 0_u128);
    assert_eq!(dispatcher.is_deleted(3_u64), true);

    // Verify remaining items
    let mut pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        pairs.append((*key, *value));
    }
    let pairs = pairs.span();
    assert_eq!(pairs.len(), 2);
}

#[test]
fn test_remove_all() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);
    dispatcher.set_value(3_u64, 30_u128);

    dispatcher.remove(1_u64);
    dispatcher.remove(2_u64);
    dispatcher.remove(3_u64);

    assert_eq!(dispatcher.get_len(), 0);
    assert_eq!(dispatcher.get_value(1_u64), 0_u128);
    assert_eq!(dispatcher.get_value(2_u64), 0_u128);
    assert_eq!(dispatcher.get_value(3_u64), 0_u128);

    // Iterator should return nothing
    let mut count = 0_u64;
    for _ in dispatcher.get_all_values() {
        count += 1;
    }
    assert_eq!(count, 0);
}

#[test]
fn test_remove_and_reinsert() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.set_value(2_u64, 20_u128);

    // Remove
    dispatcher.remove(1_u64);
    assert_eq!(dispatcher.get_len(), 1);
    assert_eq!(dispatcher.get_value(1_u64), 0_u128);

    // Reinsert same key
    dispatcher.set_value(1_u64, 100_u128);
    assert_eq!(dispatcher.get_len(), 2);
    assert_eq!(dispatcher.get_value(1_u64), 100_u128.into());
    assert_eq!(dispatcher.is_deleted(1_u64), false);
}

#[test]
fn test_remove_nonexistent() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);

    // Remove non-existent key (should be no-op)
    dispatcher.remove(99_u64);
    assert_eq!(dispatcher.get_len(), 1);
    assert_eq!(dispatcher.get_value(1_u64), 10_u128.into());
}

#[test]
fn test_remove_already_deleted() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(1_u64, 10_u128);
    dispatcher.remove(1_u64);
    assert_eq!(dispatcher.get_len(), 0);

    // Remove again (should be no-op)
    dispatcher.remove(1_u64);
    assert_eq!(dispatcher.get_len(), 0);
    assert_eq!(dispatcher.is_deleted(1_u64), true);
}

#[test]
fn test_remove_key_zero() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value(0_u64, 100_u128);
    dispatcher.set_value(1_u64, 10_u128);
    assert_eq!(dispatcher.get_len(), 2);

    // Remove key 0
    dispatcher.remove(0_u64);
    assert_eq!(dispatcher.get_len(), 1);
    assert_eq!(dispatcher.get_value(0_u64), 0_u128);
    assert_eq!(dispatcher.is_deleted(0_u64), true);
    assert_eq!(dispatcher.get_value(1_u64), 10_u128.into());

    // Verify iterator skips deleted key 0
    let mut pairs = array![];
    for (key, value) in dispatcher.get_all_values() {
        pairs.append((*key, *value));
    }
    let pairs = pairs.span();
    assert_eq!(pairs.len(), 1);
    let (k, v) = pairs.at(0);
    assert_eq!(*k, 1_u64);
    assert_eq!(*v, 10_u128);
}

#[test]
fn test_different_types() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    let addr1: EthAddress = 1.try_into().unwrap();
    let addr2: EthAddress = 2.try_into().unwrap();

    dispatcher.set_value2(1_u32, addr1);
    dispatcher.set_value2(2_u32, addr2);

    assert_eq!(dispatcher.get_len2(), 2);
    assert_eq!(dispatcher.get_value2(1_u32), addr1);
    assert_eq!(dispatcher.get_value2(2_u32), addr2);

    let mut pairs = array![];
    for (key, value) in dispatcher.get_all_values2() {
        pairs.append((*key, *value));
    }
    let pairs = pairs.span();
    assert_eq!(pairs.len(), 2);
    let (k0, v0) = pairs.at(0);
    assert_eq!(*k0, 1_u32);
    assert_eq!(*v0, addr1);
    let (k1, v1) = pairs.at(1);
    assert_eq!(*k1, 2_u32);
    assert_eq!(*v1, addr2);
}

#[test]
fn test_i64_key() {
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    dispatcher.set_value3(10_i64, 100_u128);
    dispatcher.set_value3(-20_i64, 200_u128);

    assert_eq!(dispatcher.get_len3(), 2);
    assert_eq!(dispatcher.get_value3(10_i64), 100_u128);
    assert_eq!(dispatcher.get_value3(-20_i64), 200_u128);

    let mut pairs = array![];
    for (key, value) in dispatcher.get_all_values3() {
        pairs.append((*key, *value));
    }
    let pairs = pairs.span();
    assert_eq!(pairs.len(), 2);

    // Order depends on insertion
    let (k0, v0) = pairs.at(0);
    assert_eq!(*k0, 10_i64);
    assert_eq!(*v0, 100_u128);

    let (k1, v1) = pairs.at(1);
    assert_eq!(*k1, -20_i64);
    assert_eq!(*v1, 200_u128);
}

#[test]
fn test_signed_value_read_nonexistent_returns_default() {
    // Reading a non-existent key SHOULD return 0 (the default value for i64)
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Map is empty, reading a non-existent key should return 0
    let nonexistent_value = dispatcher.get_value_signed(999_u64);
    assert_eq!(nonexistent_value, 0_i64);

    // Write a value and verify it works correctly
    dispatcher.set_value_signed(1_u64, 42_i64);
    assert_eq!(dispatcher.get_value_signed(1_u64), 42_i64);
    assert_eq!(dispatcher.get_len_signed(), 1);

    // Write a negative value
    dispatcher.set_value_signed(2_u64, -100_i64);
    assert_eq!(dispatcher.get_value_signed(2_u64), -100_i64);
    assert_eq!(dispatcher.get_len_signed(), 2);

    // Reading another non-existent key should also return 0
    let another_nonexistent = dispatcher.get_value_signed(12345_u64);
    assert_eq!(another_nonexistent, 0_i64);
}

#[test]
fn test_signed_value_zero_is_valid() {
    // Test that 0 is a valid signed value and can be stored/retrieved correctly
    let dispatcher = ILinkedIterableMapTestContractDispatcher {
        contract_address: deploy_linked_iterable_map_test_contract(),
    };

    // Store 0 as a signed value
    dispatcher.set_value_signed(1_u64, 0_i64);
    assert_eq!(dispatcher.get_value_signed(1_u64), 0_i64);
    assert_eq!(dispatcher.get_len_signed(), 1);
}
