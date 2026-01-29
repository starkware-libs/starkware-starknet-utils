use core::iter::{IntoIterator, Iterator};
use starknet::storage::{
    Map, Mutable, StorageAsPath, StoragePath, StoragePathEntry, StoragePathMutableConversion,
    StoragePointerReadAccess, StoragePointerWriteAccess,
};
use super::linked_iterable_map::packing::{MapEntryFelt, MapEntryFeltStorePacking};
use super::utils::{Castable160, CastableFelt};

// -----------------------------------------------------------------------------
// LinkedIterableMap Implementation
// -----------------------------------------------------------------------------

#[derive(Copy, Drop, Serde, starknet::Store)]
struct HeadLength {
    head: felt252,
    length: u32,
    total_nodes: u32,
}

#[starknet::storage_node]
pub struct LinkedIterableMap<K, V, +CastableFelt<K>, +Castable160<V>> {
    // Map from Key(felt) -> (Next(felt), Value+Flags(felt))
    // todo : change to (felt252,felt252).
    _entries: Map<felt252, MapEntryFelt>,
    _head_length: HeadLength,
}

/// Trait for the interface of a linked iterable map.
pub trait LinkedIterableMapTrait<T> {
    fn len(self: T) -> u32;
    fn is_empty(self: T) -> bool;
}

impl StoragePathLinkedIterableMapImpl<
    K, V, +CastableFelt<K>, +Castable160<V>,
> of LinkedIterableMapTrait<StoragePath<LinkedIterableMap<K, V>>> {
    fn len(self: StoragePath<LinkedIterableMap<K, V>>) -> u32 {
        self._head_length.read().length
    }
    fn is_empty(self: StoragePath<LinkedIterableMap<K, V>>) -> bool {
        self.len() == 0
    }
}

impl StoragePathMutableLinkedIterableMapImpl<
    K, V, +CastableFelt<K>, +Castable160<V>,
> of LinkedIterableMapTrait<StoragePath<Mutable<LinkedIterableMap<K, V>>>> {
    fn len(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>) -> u32 {
        self.as_non_mut().len()
    }
    fn is_empty(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>) -> bool {
        self.as_non_mut().is_empty()
    }
}

// Generic implementation for any type that can be converted to StoragePath
pub impl LinkedIterableMapTraitImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: LinkedIterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
> of LinkedIterableMapTrait<T> {
    fn len(self: T) -> u32 {
        self.as_path().len()
    }
    fn is_empty(self: T) -> bool {
        self.as_path().is_empty()
    }
}

// --- Read Access ---

pub trait LinkedIterableMapReadAccess<T, K, V> {
    fn read(self: T, key: K) -> V;
    fn contains(self: T, key: K) -> bool;
}

impl StoragePathLinkedIterableMapReadAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapReadAccess<StoragePath<LinkedIterableMap<K, V>>, K, V> {
    fn read(self: StoragePath<LinkedIterableMap<K, V>>, key: K) -> V {
        let key_felt = CastableFelt::encode(key);
        let entry = self._entries.entry(key_felt).read();

        if !entry.exists || entry.is_deleted {
            return Castable160::decode((0, 0));
        }
        Castable160::decode(entry.value)
    }

    fn contains(self: StoragePath<LinkedIterableMap<K, V>>, key: K) -> bool {
        let key_felt = CastableFelt::encode(key);
        let entry = self._entries.entry(key_felt).read();
        entry.exists && !entry.is_deleted
    }
}

impl StoragePathMutableLinkedIterableMapReadAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapReadAccess<StoragePath<Mutable<LinkedIterableMap<K, V>>>, K, V> {
    fn read(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>, key: K) -> V {
        self.as_non_mut().read(key)
    }
    fn contains(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>, key: K) -> bool {
        self.as_non_mut().contains(key)
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
    fn contains(self: T, key: K) -> bool {
        self.as_path().contains(key)
    }
}

// --- Write Access ---

pub trait LinkedIterableMapWriteAccess<T, K, V> {
    fn write(self: T, key: K, value: V);
    fn remove(self: T, key: K);
    fn clear(self: T);
}

impl StoragePathLinkedIterableMapWriteAccessImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapWriteAccess<StoragePath<Mutable<LinkedIterableMap<K, V>>>, K, V> {
    fn write(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>, key: K, value: V) {
        let key_felt = CastableFelt::encode(key);
        let value_encoded = Castable160::encode(value);

        let entry_path = self._entries.entry(key_felt);
        let mut entry = entry_path.read();

        // 1. Update existing non-deleted
        if entry.exists && !entry.is_deleted {
            entry.value = value_encoded;
            entry_path.write(entry);
            return;
        }

        let mut hl = self._head_length.read();

        // 2. Re-insert deleted (stays in same position in list)
        if entry.exists {
            entry.value = value_encoded;
            entry.is_deleted = false;
            entry_path.write(entry);
            hl.length += 1;
            self._head_length.write(hl);
            return;
        }

        // 3. New Insert (Stack Push / Head Insert)
        let new_entry = MapEntryFelt {
            next: hl.head, // Point to old head
            value: value_encoded,
            is_deleted: false,
            exists: true,
        };

        entry_path.write(new_entry);

        // Update head to new key
        hl.head = key_felt;
        hl.length += 1;
        hl.total_nodes += 1;
        self._head_length.write(hl);
    }

    fn remove(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>, key: K) {
        let key_felt = CastableFelt::encode(key);
        let entry_path = self._entries.entry(key_felt);
        let mut entry = entry_path.read();

        if !entry.exists || entry.is_deleted {
            return;
        }

        entry.is_deleted = true;
        entry.value = (0, 0); // Clear value
        entry_path.write(entry);

        let mut hl = self._head_length.read();
        hl.length -= 1;
        self._head_length.write(hl);
    }

    fn clear(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>) {
        let mut hl = self._head_length.read();
        let mut current = hl.head;
        let mut nodes_remaining = hl.total_nodes;

        while nodes_remaining > 0 {
            let entry_path = self._entries.entry(current);
            let entry = entry_path.read();

            // Zero out entry
            entry_path
                .write(MapEntryFelt { next: 0, value: (0, 0), is_deleted: false, exists: false });

            current = entry.next;
            nodes_remaining -= 1;
        }

        self._head_length.write(HeadLength { head: 0, length: 0, total_nodes: 0 });
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
    fn remove(self: T, key: K) {
        self.as_path().remove(key)
    }
    fn clear(self: T) {
        self.as_path().clear()
    }
}

// --- Iterator ---

#[derive(Copy, Drop)]
struct LinkedMapIterator<K, V> {
    _entries: StoragePath<Map<felt252, MapEntryFelt>>,
    _current: felt252,
    _nodes_to_visit: u32,
}

impl LinkedMapIteratorImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of Iterator<LinkedMapIterator<K, V>> {
    type Item = (K, V);
    fn next(ref self: LinkedMapIterator<K, V>) -> Option<Self::Item> {
        loop {
            if self._nodes_to_visit == 0 {
                return Option::None;
            }

            let key_felt = self._current;
            let entry = self._entries.entry(key_felt).read();

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
> of IntoIterator<StoragePath<LinkedIterableMap<K, V>>> {
    type IntoIter = LinkedMapIterator<K, V>;
    fn into_iter(self: StoragePath<LinkedIterableMap<K, V>>) -> Self::IntoIter {
        let hl = self._head_length.read();
        LinkedMapIterator {
            _entries: self._entries.as_path(), _current: hl.head, _nodes_to_visit: hl.total_nodes,
        }
    }
}

pub impl StoragePathMutableLinkedIterableMapIntoIteratorImpl<
    K, V, +CastableFelt<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of IntoIterator<StoragePath<Mutable<LinkedIterableMap<K, V>>>> {
    type IntoIter = LinkedMapIterator<K, V>;
    fn into_iter(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>) -> Self::IntoIter {
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
