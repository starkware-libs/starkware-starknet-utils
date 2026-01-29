use core::iter::{IntoIterator, Iterator};
use starknet::storage::{
    Map, Mutable, StorageAsPath, StoragePath, StoragePathEntry, StoragePathMutableConversion,
    StoragePointerReadAccess, StoragePointerWriteAccess,
};
use super::linked_iterable_map::packing::{
    MapEntryFelt, MapEntryFeltPacked, MapEntryPackingTrait, MapInfoPackingTrait,
};
use super::linked_iterable_map::{
    LinkedIterableMapDeletedTrait, LinkedIterableMapReadAccess, LinkedIterableMapTrait,
    LinkedIterableMapWriteAccess, MutableLinkedIterableMapTrait,
};
use super::utils::{Castable160, CastableFelt};

// -----------------------------------------------------------------------------
// LinkedIterableMapFelt: felt252 keys, Castable160 values, 2 felts per entry
// -----------------------------------------------------------------------------

#[starknet::storage_node]
pub struct LinkedIterableMapFelt<K, V, +CastableFelt<K>, +Castable160<V>> {
    _entries: Map<felt252, MapEntryFeltPacked>,
    _head: felt252,
    _info: u64,
}

pub impl StoragePathLinkedIterableMapImpl<
    K, V, +CastableFelt<K>, +Castable160<V>,
> of LinkedIterableMapTrait<StoragePath<LinkedIterableMapFelt<K, V>>> {
    fn len(self: StoragePath<LinkedIterableMapFelt<K, V>>) -> u32 {
        MapInfoPackingTrait::unpack(self._info.read()).length
    }
}

pub impl StoragePathMutableLinkedIterableMapImpl<
    K, V, +CastableFelt<K>, +Castable160<V>,
> of LinkedIterableMapTrait<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>> {
    fn len(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>) -> u32 {
        self.as_non_mut().len()
    }
}

// --- LinkedIterableMapReadAccess ---
// Values: felt252 in storage -> u256 -> (low, high) -> Castable160::decode

pub impl StoragePathLinkedIterableMapReadAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapReadAccess<StoragePath<LinkedIterableMapFelt<K, V>>, K, V> {
    fn read(self: StoragePath<LinkedIterableMapFelt<K, V>>, key: K) -> V {
        let packed_entry = self._entries.entry(CastableFelt::encode(key)).read();
        let entry = MapEntryPackingTrait::unpack(packed_entry);
        Castable160::decode(entry.value)
    }
}

pub impl StoragePathMutableLinkedIterableMapReadAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapReadAccess<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, K, V> {
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
    impl StoragePathImpl: LinkedIterableMapReadAccess<StoragePath<StorageAsPathImpl::Value>, K, V>,
> of LinkedIterableMapReadAccess<T, K, V> {
    fn read(self: T, key: K) -> V {
        self.as_path().read(key)
    }
}

// --- LinkedIterableMapWriteAccess & MutableLinkedIterableMapTrait ---

pub impl StoragePathLinkedIterableMapWriteAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapWriteAccess<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, K, V> {
    fn write(self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, key: K, value: V) {
        let key_felt = CastableFelt::encode(key);
        let value_160 = Castable160::encode(value);
        let entry_path = self._entries.entry(key_felt);
        let packed_entry = entry_path.read();
        let mut entry = MapEntryPackingTrait::unpack(packed_entry);

        // 1. Update existing non-deleted
        if entry.exists && !entry.is_deleted {
            entry.value = value_160;
            entry_path.write(entry.pack());
            return;
        }

        let mut info = MapInfoPackingTrait::unpack(self._info.read());

        // 2. Re-insert deleted (stays in same position in list)
        if entry.exists {
            entry.value = value_160;
            entry.is_deleted = false;
            entry_path.write(entry.pack());
            info.length += 1;
            self._info.write(info.pack());
            return;
        }

        let mut head = self._head.read();

        // 3. New Insert (Stack Push / Head Insert)
        let new_entry = MapEntryFelt {
            next: head, value: value_160, is_deleted: false, exists: true,
        };

        entry_path.write(new_entry.pack());

        // Update head to new key
        head = key_felt;
        info.length += 1;
        info.total_nodes += 1;

        self._head.write(head);
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
    impl StoragePathImpl: LinkedIterableMapWriteAccess<StoragePath<StorageAsPathImpl::Value>, K, V>,
> of LinkedIterableMapWriteAccess<T, K, V> {
    fn write(self: T, key: K, value: V) {
        self.as_path().write(key, value)
    }
}

pub impl MutableLinkedIterableMapFeltImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of MutableLinkedIterableMapTrait<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, K> {
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
    impl StoragePathImpl: MutableLinkedIterableMapTrait<StoragePath<StorageAsPathImpl::Value>, K>,
> of MutableLinkedIterableMapTrait<T, K> {
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
> of LinkedIterableMapDeletedTrait<StoragePath<LinkedIterableMapFelt<K, V>>, K> {
    fn is_deleted(self: StoragePath<LinkedIterableMapFelt<K, V>>, key: K) -> bool {
        let packed_entry = self._entries.entry(CastableFelt::encode(key)).read();
        let entry = MapEntryPackingTrait::unpack(packed_entry);
        entry.exists && entry.is_deleted
    }
}

pub impl LinkedIterableMapFeltDeletedMutableImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>,
> of LinkedIterableMapDeletedTrait<StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, K> {
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
    +LinkedIterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
> of IntoIterator<T> {
    type IntoIter = StoragePathImpl::IntoIter;
    fn into_iter(self: T) -> Self::IntoIter {
        self.as_path().into_iter()
    }
}

// --- Public helpers (for call sites that need explicit dispatch) ---

pub fn map_read<K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>>(
    self: StoragePath<LinkedIterableMapFelt<K, V>>, key: K,
) -> V {
    StoragePathLinkedIterableMapReadAccessImpl::read(self, key)
}

pub fn map_write<K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>>(
    self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, key: K, value: V,
) {
    StoragePathLinkedIterableMapWriteAccessImpl::write(self, key, value)
}

pub fn map_remove<K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>>(
    self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>, key: K,
) {
    MutableLinkedIterableMapFeltImpl::remove(self, key)
}

pub fn map_clear<K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>>(
    self: StoragePath<Mutable<LinkedIterableMapFelt<K, V>>>,
) {
    MutableLinkedIterableMapFeltImpl::clear(self)
}

pub fn map_is_deleted<K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>>(
    self: StoragePath<LinkedIterableMapFelt<K, V>>, key: K,
) -> bool {
    LinkedIterableMapFeltDeletedImpl::is_deleted(self, key)
}

pub fn map_iter<K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>>(
    self: StoragePath<LinkedIterableMapFelt<K, V>>,
) -> LinkedMapIterator<K, V> {
    StoragePathLinkedIterableMapIntoIteratorImpl::into_iter(self)
}
