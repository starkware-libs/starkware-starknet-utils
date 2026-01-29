use core::iter::{IntoIterator, Iterator};
use starknet::storage::{
    Map, Mutable, StorageAsPath, StoragePath, StoragePathEntry, StoragePathMutableConversion,
    StoragePointerReadAccess, StoragePointerWriteAccess,
};
use super::linked_iterable_map::packing::{
    MapEntryFelt, MapEntryFeltPacked, MapEntryPackingTrait, MapInfoPackingTrait,
    pack_value_and_flags, unpack_value_and_flags_to_flags, unpack_value_and_flags_to_value,
};
use super::utils::{Castable160, CastableFelt};


/// Trait for the interface of a linked iterable map.
pub trait LinkedIterableMapFeltTrait<T> {
    fn len(self: T) -> u32;
}

/// Trait for reading values with a specific type from the map
pub trait LinkedIterableMapFeltReadAccess<T, K, V> {
    fn read(self: T, key: K) -> V;
}

/// Trait for writing values with a specific type to the map
pub trait LinkedIterableMapFeltWriteAccess<T, K, V> {
    fn write(self: T, key: K, value: V);
}

/// Mutable trait for clearing the map and removing keys
pub trait MutableLinkedIterableMapFeltTrait<T, K> {
    fn clear(self: T);
    fn remove(self: T, key: K);
}

/// Trait for checking if a key is deleted (works on both mutable and non-mutable)
pub trait LinkedIterableMapFeltDeletedTrait<T, K> {
    fn is_deleted(self: T, key: K) -> bool;
}

#[starknet::storage_node]
pub struct LinkedIterableMapFelt<K, V, +CastableFelt<K>, +Castable160<V>> {
    _entries: Map<felt252, MapEntryFeltPacked>,
    _head: felt252,
    _info: u64,
}

pub impl StoragePathLinkedIterableMapImpl<
    K, V, +CastableFelt<K>, +Castable160<V>,
> of LinkedIterableMapFeltTrait<StoragePath<LinkedIterableMapFelt<K, V>>> {
    fn len(self: StoragePath<LinkedIterableMapFelt<K, V>>) -> u32 {
        MapInfoPackingTrait::unpack(self._info.read()).length
    }
}

pub impl StoragePathMutableLinkedIterableMapImpl<
    K, V, +CastableFelt<K>, +Castable160<V>,
> of LinkedIterableMapFeltTrait<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>> {
    fn len(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>) -> u32 {
        self.as_non_mut().len()
    }
}

// --- LinkedIterableMapReadAccess ---
// Values: felt252 in storage -> u256 -> (low, high) -> Castable160::decode

pub impl StoragePathLinkedIterableMapReadAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapFeltReadAccess<StoragePath<LinkedIterableMapFelt<K, V>>, K, V> {
    fn read(self: StoragePath<LinkedIterableMapFelt<K, V>>, key: K) -> V {
        let value_and_flags = self._entries.entry(CastableFelt::encode(key)).value_and_flags.read();
        Castable160::decode(unpack_value_and_flags_to_value(value_and_flags))
    }
}

pub impl StoragePathMutableLinkedIterableMapReadAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapFeltReadAccess<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, K, V> {
    fn read(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, key: K) -> V {
        self.as_non_mut().read(key)
    }
}

pub impl LinkedIterableMapReadAccessGenericImpl<
    T,
    K,
    V,
    +Drop<T>,
    +Drop<K>,
    +Drop<V>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: LinkedIterableMapFeltReadAccess<
        StoragePath<StorageAsPathImpl::Value>, K, V,
    >,
> of LinkedIterableMapFeltReadAccess<T, K, V> {
    fn read(self: T, key: K) -> V {
        self.as_path().read(key)
    }
}

// --- LinkedIterableMapWriteAccess & MutableLinkedIterableMapTrait ---

pub impl StoragePathLinkedIterableMapWriteAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapFeltWriteAccess<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, K, V> {
    fn write(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, key: K, value: V) {
        let key_felt = CastableFelt::encode(key);
        let value_160 = Castable160::encode(value);
        let entry_path = self._entries.entry(key_felt);
        let value_and_flags = entry_path.value_and_flags.read();
        let (exists, is_deleted) = unpack_value_and_flags_to_flags(value_and_flags);

        // 1. Update existing non-deleted: write only value_and_flags, preserve next
        if exists && !is_deleted {
            entry_path
                .value_and_flags
                .write(pack_value_and_flags(value: value_160, is_deleted: false, exists: true));
            return;
        }

        // 2. Re-insert deleted: write only value_and_flags, then update length
        if exists {
            entry_path
                .value_and_flags
                .write(pack_value_and_flags(value: value_160, is_deleted: false, exists: true));
            let mut info = MapInfoPackingTrait::unpack(self._info.read());
            info.length += 1;
            self._info.write(info.pack());
            return;
        }

        // 3. New insert: write both slots (next = head, value_and_flags), then update head and info
        let head = self._head.read();
        let mut info = MapInfoPackingTrait::unpack(self._info.read());

        entry_path.next.write(head);
        entry_path
            .value_and_flags
            .write(pack_value_and_flags(value: value_160, is_deleted: false, exists: true));

        self._head.write(key_felt);
        info.length += 1;
        info.total_nodes += 1;
        self._info.write(info.pack());
    }
}

pub impl LinkedIterableMapWriteAccessGenericImpl<
    T,
    K,
    V,
    +Drop<T>,
    +Drop<K>,
    +Drop<V>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: LinkedIterableMapFeltWriteAccess<
        StoragePath<StorageAsPathImpl::Value>, K, V,
    >,
> of LinkedIterableMapFeltWriteAccess<T, K, V> {
    fn write(self: T, key: K, value: V) {
        self.as_path().write(key, value)
    }
}

pub impl MutableLinkedIterableMapFeltImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of MutableLinkedIterableMapFeltTrait<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, K> {
    fn remove(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, key: K) {
        let key_felt = CastableFelt::encode(key);
        let entry_path = self._entries.entry(key_felt);
        let packed_entry = entry_path.read();
        let mut entry = MapEntryPackingTrait::unpack(packed_entry);

        if !entry.exists || entry.is_deleted {
            return;
        }

        entry.is_deleted = true;
        entry.value = (0, 0);
        entry_path.write(entry.pack());

        let mut info = MapInfoPackingTrait::unpack(self._info.read());
        info.length -= 1;
        self._info.write(info.pack());
    }

    fn clear(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>) {
        let info = MapInfoPackingTrait::unpack(self._info.read());
        let mut current = self._head.read();
        let mut nodes_remaining = info.total_nodes;

        while nodes_remaining > 0 {
            let entry_path = self._entries.entry(current);
            let entry = MapEntryPackingTrait::unpack(entry_path.read());
            entry_path
                .write(
                    MapEntryFelt { next: 0, value: (0, 0), is_deleted: false, exists: false }
                        .pack(),
                );
            current = entry.next;
            nodes_remaining -= 1;
        }

        self._head.write(0);
        self._info.write(0);
    }
}

pub impl MutableLinkedIterableMapGenericImpl<
    T,
    K,
    +Drop<T>,
    +Drop<K>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: MutableLinkedIterableMapFeltTrait<
        StoragePath<StorageAsPathImpl::Value>, K,
    >,
> of MutableLinkedIterableMapFeltTrait<T, K> {
    fn remove(self: T, key: K) {
        self.as_path().remove(key)
    }
    fn clear(self: T) {
        self.as_path().clear()
    }
}

// --- LinkedIterableMapDeletedTrait ---

pub impl LinkedIterableMapFeltDeletedImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>,
> of LinkedIterableMapFeltDeletedTrait<StoragePath<LinkedIterableMapFelt<K, V>>, K> {
    fn is_deleted(self: StoragePath<LinkedIterableMapFelt<K, V>>, key: K) -> bool {
        let value_and_flags = self._entries.entry(CastableFelt::encode(key)).value_and_flags.read();
        let (exists, is_deleted) = unpack_value_and_flags_to_flags(value_and_flags);
        exists && is_deleted
    }
}

pub impl LinkedIterableMapFeltDeletedMutableImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>,
> of LinkedIterableMapFeltDeletedTrait<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, K> {
    fn is_deleted(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, key: K) -> bool {
        self.as_non_mut().is_deleted(key)
    }
}

// --- IntoIterator ---

#[derive(Copy, Drop)]
pub struct LinkedMapIterator<K, V> {
    _entries: StoragePath<Map<felt252, MapEntryFeltPacked>>,
    _current: felt252,
    _nodes_to_visit: u32,
}

pub impl LinkedMapIteratorImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of Iterator<LinkedMapIterator<K, V>> {
    type Item = (K, V);
    fn next(ref self: LinkedMapIterator<K, V>) -> Option<Self::Item> {
        loop {
            if self._nodes_to_visit == 0 {
                return Option::None;
            }

            let key_felt = self._current;
            let packed_entry = self._entries.entry(key_felt).read();
            let entry = MapEntryPackingTrait::unpack(packed_entry);

            self._current = entry.next;
            self._nodes_to_visit -= 1;

            if !entry.is_deleted {
                return Option::Some(
                    (CastableFelt::decode(key_felt), Castable160::decode(entry.value)),
                );
            }
        }
    }
}

pub impl StoragePathLinkedIterableMapIntoIteratorImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of IntoIterator<StoragePath<LinkedIterableMapFelt<K, V>>> {
    type IntoIter = LinkedMapIterator<K, V>;
    fn into_iter(self: StoragePath<LinkedIterableMapFelt<K, V>>) -> Self::IntoIter {
        let head = self._head.read();
        let info = MapInfoPackingTrait::unpack(self._info.read());
        LinkedMapIterator {
            _entries: self._entries.as_path(), _current: head, _nodes_to_visit: info.total_nodes,
        }
    }
}

pub impl StoragePathMutableLinkedIterableMapIntoIteratorImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of IntoIterator<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>> {
    type IntoIter = LinkedMapIterator<K, V>;
    fn into_iter(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>) -> Self::IntoIter {
        self.as_non_mut().into_iter()
    }
}

pub impl LinkedIterableMapIntoIterImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: IntoIterator<StoragePath<StorageAsPathImpl::Value>>,
    +LinkedIterableMapFeltTrait<StoragePath<StorageAsPathImpl::Value>>,
> of IntoIterator<T> {
    type IntoIter = StoragePathImpl::IntoIter;
    fn into_iter(self: T) -> Self::IntoIter {
        self.as_path().into_iter()
    }
}
