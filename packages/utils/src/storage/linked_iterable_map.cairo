use core::iter::{IntoIterator, Iterator};
use starknet::storage::{
    Map, Mutable, StorageAsPath, StorageMapReadAccess, StorageMapWriteAccess, StoragePath,
    StoragePathMutableConversion, StoragePointerReadAccess, StoragePointerWriteAccess,
};
use super::utils::{Castable160, Castable64};
pub mod packing;
use packing::{HeadTailLengthStorePacking, MapEntry, MapEntryStorePacking};


#[starknet::storage_node]
#[allow(starknet::invalid_storage_member_types)]
pub struct LinkedIterableMap<K, V, +Castable64<K>, +Castable160<V>> {
    _entries: Map<u64, felt252>,
    _head_tail_length: felt252,
}

/// Trait for the interface of a linked iterable map.
pub trait LinkedIterableMapTrait<T> {
    fn len(self: T) -> u32;
}

impl StoragePathLinkedIterableMapImpl<
    K, V, +Castable64<K>, +Castable160<V>,
> of LinkedIterableMapTrait<StoragePath<LinkedIterableMap<K, V>>> {
    fn len(self: StoragePath<LinkedIterableMap<K, V>>) -> u32 {
        let packed = self._head_tail_length.read();
        let head_tail_length = HeadTailLengthStorePacking::unpack(packed);
        head_tail_length.length
    }
}

impl StoragePathMutableLinkedIterableMapImpl<
    K, V, +Castable64<K>, +Castable160<V>,
> of LinkedIterableMapTrait<StoragePath<Mutable<LinkedIterableMap<K, V>>>> {
    fn len(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>) -> u32 {
        self.as_non_mut().len()
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
}

/// Trait for reading values with a specific type from the map
pub trait LinkedIterableMapReadAccess<T, K, V> {
    fn read(self: T, key: K) -> V;
}

/// Trait for writing values with a specific type to the map
pub trait LinkedIterableMapWriteAccess<T, K, V> {
    fn write(self: T, key: K, value: V);
}

/// Read implementation for StoragePath
impl StoragePathLinkedIterableMapReadAccessImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapReadAccess<StoragePath<LinkedIterableMap<K, V>>, K, V> {
    fn read(self: StoragePath<LinkedIterableMap<K, V>>, key: K) -> V {
        let key_u64 = Castable64::encode(key);
        let packed: felt252 = StorageMapReadAccess::read(self._entries, key_u64);
        let entry = MapEntryStorePacking::unpack(packed);
        Castable160::decode(entry.value)
    }
}

impl StoragePathMutableLinkedIterableMapReadAccessImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapReadAccess<StoragePath<Mutable<LinkedIterableMap<K, V>>>, K, V> {
    fn read(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>, key: K) -> V {
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

/// Write implementation for StoragePath
impl StoragePathLinkedIterableMapWriteAccessImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of LinkedIterableMapWriteAccess<StoragePath<Mutable<LinkedIterableMap<K, V>>>, K, V> {
    fn write(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>, key: K, value: V) {
        let key_u64 = Castable64::encode(key);
        let value_encoded = Castable160::encode(value);

        // Read entry first - exists flag tells us if key is in the list
        let entry_packed: felt252 = StorageMapReadAccess::read(self._entries, key_u64);
        let entry = MapEntryStorePacking::unpack(entry_packed);

        // Fast path: if entry exists and is not deleted, just update value
        // No need to read _head_tail_length at all
        if entry.exists && !entry.is_deleted {
            let new_entry = MapEntry {
                value: value_encoded, next: entry.next, is_deleted: false, exists: true,
            };
            StorageMapWriteAccess::write(
                self._entries, key_u64, MapEntryStorePacking::pack(new_entry),
            );
            return;
        }

        // Need metadata for deleted entries or new keys
        let packed = self._head_tail_length.read();
        let mut head_tail_length = HeadTailLengthStorePacking::unpack(packed);

        if entry.exists {
            // Key was deleted - unmark as deleted
            head_tail_length.length += 1;
            let new_entry = MapEntry {
                value: value_encoded, next: entry.next, is_deleted: false, exists: true,
            };
            StorageMapWriteAccess::write(
                self._entries, key_u64, MapEntryStorePacking::pack(new_entry),
            );
            self._head_tail_length.write(HeadTailLengthStorePacking::pack(head_tail_length));
            return;
        }

        // New key - add to linked list
        if head_tail_length.total_nodes > 0 {
            // Append to end: update old tail's next pointer
            let old_tail_packed: felt252 = StorageMapReadAccess::read(
                self._entries, head_tail_length.tail,
            );
            let old_tail_entry = MapEntryStorePacking::unpack(old_tail_packed);
            let updated_tail = MapEntry {
                value: old_tail_entry.value,
                next: key_u64,
                is_deleted: old_tail_entry.is_deleted,
                exists: true,
            };
            StorageMapWriteAccess::write(
                self._entries, head_tail_length.tail, MapEntryStorePacking::pack(updated_tail),
            );
        } else {
            // First element - set as head
            head_tail_length.head = key_u64;
        }
        // Update tail, length, and total_nodes
        head_tail_length.tail = key_u64;
        head_tail_length.length += 1;
        head_tail_length.total_nodes += 1;
        // Write new entry with no next pointer (tail), marked as exists
        let new_entry = MapEntry { value: value_encoded, next: 0, is_deleted: false, exists: true };
        StorageMapWriteAccess::write(self._entries, key_u64, MapEntryStorePacking::pack(new_entry));
        self._head_tail_length.write(HeadTailLengthStorePacking::pack(head_tail_length));
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

/// Iterator implementation for linked list traversal
/// The iterator skips deleted entries transparently, but still reads them.
#[derive(Copy, Drop)]
struct LinkedMapIterator<K, V> {
    _entries: StoragePath<Map<u64, felt252>>,
    _current: u64,
    _nodes_to_visit: u32 // Total nodes left to traverse (including deleted)
}

pub impl LinkedMapIteratorImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of Iterator<LinkedMapIterator<K, V>> {
    type Item = (K, V);
    fn next(ref self: LinkedMapIterator<K, V>) -> Option<Self::Item> {
        // Keep iterating until we find a non-deleted item or run out of nodes
        loop {
            if self._nodes_to_visit == 0 {
                return Option::None;
            }

            let key_u64 = self._current;

            // Single read: get both value and next pointer from combined entry
            let packed: felt252 = StorageMapReadAccess::read(self._entries, key_u64);
            let entry = MapEntryStorePacking::unpack(packed);

            // Move to next node
            self._current = entry.next;
            self._nodes_to_visit -= 1;

            // Skip deleted items
            if entry.is_deleted {
                continue;
            }

            // Return value from the same read - no extra storage access!
            return Option::Some((Castable64::decode(key_u64), Castable160::decode(entry.value)));
        }
    }
}

impl StoragePathLinkedIterableMapIntoIteratorImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of IntoIterator<StoragePath<LinkedIterableMap<K, V>>> {
    type IntoIter = LinkedMapIterator<K, V>;
    fn into_iter(self: StoragePath<LinkedIterableMap<K, V>>) -> Self::IntoIter {
        let packed = self._head_tail_length.read();
        let head_tail_length = HeadTailLengthStorePacking::unpack(packed);
        // Use total_nodes to know how many nodes to traverse
        LinkedMapIterator {
            _entries: self._entries.as_path(),
            _current: head_tail_length.head,
            _nodes_to_visit: head_tail_length.total_nodes,
        }
    }
}

#[derive(Copy, Drop)]
struct LinkedMapIteratorMut<K, V> {
    _entries: StoragePath<Mutable<Map<u64, felt252>>>,
    _current: u64,
    _nodes_to_visit: u32 // Total nodes left to traverse (including deleted)
}

pub impl LinkedMapIteratorMutImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of Iterator<LinkedMapIteratorMut<K, V>> {
    type Item = (K, V);
    fn next(ref self: LinkedMapIteratorMut<K, V>) -> Option<Self::Item> {
        // Keep iterating until we find a non-deleted item or run out of nodes
        loop {
            if self._nodes_to_visit == 0 {
                return Option::None;
            }

            let key_u64 = self._current;

            // Single read: get both value and next pointer from combined entry
            let packed: felt252 = StorageMapReadAccess::read(self._entries, key_u64);
            let entry = MapEntryStorePacking::unpack(packed);

            // Move to next node
            self._current = entry.next;
            self._nodes_to_visit -= 1;

            // Skip deleted items
            if entry.is_deleted {
                continue;
            }

            // Return value from the same read - no extra storage access!
            return Option::Some((Castable64::decode(key_u64), Castable160::decode(entry.value)));
        }
    }
}

impl StoragePathMutableLinkedIterableMapIntoIteratorImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>, +Drop<V>,
> of IntoIterator<StoragePath<Mutable<LinkedIterableMap<K, V>>>> {
    type IntoIter = LinkedMapIteratorMut<K, V>;
    fn into_iter(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>) -> Self::IntoIter {
        let packed = self._head_tail_length.read();
        let head_tail_length = HeadTailLengthStorePacking::unpack(packed);
        // Use total_nodes to know how many nodes to traverse
        LinkedMapIteratorMut {
            _entries: self._entries.as_path(),
            _current: head_tail_length.head,
            _nodes_to_visit: head_tail_length.total_nodes,
        }
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

/// Mutable trait for clearing the map and removing keys
pub trait MutableLinkedIterableMapTrait<T, K> {
    fn clear(self: T);
    fn remove(self: T, key: K);
}

/// Trait for checking if a key is deleted (works on both mutable and non-mutable)
pub trait LinkedIterableMapDeletedTrait<T, K> {
    fn is_deleted(self: T, key: K) -> bool;
}

impl MutableLinkedIterableMapImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>,
> of MutableLinkedIterableMapTrait<StoragePath<Mutable<LinkedIterableMap<K, V>>>, K> {
    fn clear(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>) {
        // Clear by traversing linked list using total_nodes count
        let packed = self._head_tail_length.read();
        let mut head_tail_length = HeadTailLengthStorePacking::unpack(packed);
        let mut current = head_tail_length.head;
        let mut nodes_remaining = head_tail_length.total_nodes;

        while nodes_remaining != 0 {
            // Read current entry to get next pointer
            let entry_packed: felt252 = StorageMapReadAccess::read(self._entries, current);

            let entry = MapEntryStorePacking::unpack(entry_packed);

            // Clear the entry (set to 0)
            StorageMapWriteAccess::write(self._entries, current, 0);

            current = entry.next;

            nodes_remaining -= 1;
        }

        // Reset head, tail, length, and total_nodes
        head_tail_length.head = 0;
        head_tail_length.tail = 0;
        head_tail_length.length = 0_u32;
        head_tail_length.total_nodes = 0_u32;
        self._head_tail_length.write(HeadTailLengthStorePacking::pack(head_tail_length));
    }

    fn remove(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>, key: K) {
        let key_u64 = Castable64::encode(key);
        let entry_packed: felt252 = StorageMapReadAccess::read(self._entries, key_u64);
        let entry = MapEntryStorePacking::unpack(entry_packed);

        // If doesn't exist or already deleted, do nothing
        if !entry.exists || entry.is_deleted {
            return;
        }

        // Mark as deleted, clear value, preserve next pointer and exists flag
        let deleted_entry = MapEntry {
            value: (0_u128, 0_u32), next: entry.next, is_deleted: true, exists: true,
        };
        StorageMapWriteAccess::write(
            self._entries, key_u64, MapEntryStorePacking::pack(deleted_entry),
        );

        // Decrement length
        let packed = self._head_tail_length.read();
        let mut head_tail_length = HeadTailLengthStorePacking::unpack(packed);
        head_tail_length.length -= 1;
        self._head_tail_length.write(HeadTailLengthStorePacking::pack(head_tail_length));
    }
}

impl LinkedIterableMapDeletedImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>,
> of LinkedIterableMapDeletedTrait<StoragePath<LinkedIterableMap<K, V>>, K> {
    fn is_deleted(self: StoragePath<LinkedIterableMap<K, V>>, key: K) -> bool {
        let key_u64 = Castable64::encode(key);
        let entry_packed: felt252 = StorageMapReadAccess::read(self._entries, key_u64);
        let entry = MapEntryStorePacking::unpack(entry_packed);
        entry.exists && entry.is_deleted
    }
}

impl LinkedIterableMapDeletedMutableImpl<
    K, V, +Castable64<K>, +Castable160<V>, +Drop<K>,
> of LinkedIterableMapDeletedTrait<StoragePath<Mutable<LinkedIterableMap<K, V>>>, K> {
    fn is_deleted(self: StoragePath<Mutable<LinkedIterableMap<K, V>>>, key: K) -> bool {
        self.as_non_mut().is_deleted(key)
    }
}

pub impl LinkedIterableMapDeletedTraitImpl<
    T,
    K,
    +Drop<T>,
    +Drop<K>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: LinkedIterableMapDeletedTrait<StoragePath<StorageAsPathImpl::Value>, K>,
> of LinkedIterableMapDeletedTrait<T, K> {
    fn is_deleted(self: T, key: K) -> bool {
        self.as_path().is_deleted(key)
    }
}
