use core::iter::{IntoIterator, Iterator};
use core::num::traits::Pow;
use core::option::OptionTrait;
use starknet::storage::{
    Map, Mutable, StorageAsPath, StorageMapReadAccess, StorageMapWriteAccess, StoragePath,
    StoragePathMutableConversion, StoragePointerReadAccess, StoragePointerWriteAccess,
};
use starknet::storage_access::StorePacking;

const TWO_POW_32: u128 = 2_u128.pow(32);
const TWO_POW_64: u128 = 2_u128.pow(64);
const TWO_POW_65: u128 = 2_u128.pow(65);
const TWO_POW_96: u128 = 2_u128.pow(96);
const MASK_32: u128 = TWO_POW_32 - 1;
const MASK_64: u128 = TWO_POW_64 - 1;


/// Entry structure packing value, next pointer, deleted flag, and exists flag together
/// This allows a single read per member during iteration
/// Layout in felt252 (194 bits total, fits in 251-bit felt):
///   - bits 0-127: value (u128)
///   - bits 128-191: next key (u64)
///   - bit 192: is_deleted flag
///   - bit 193: exists flag
#[derive(Copy, Drop)]
struct MapEntry {
    value: u128,
    next: u64,
    is_deleted: bool,
    exists: bool,
}

impl MapEntryStorePacking of StorePacking<MapEntry, felt252> {
    fn pack(value: MapEntry) -> felt252 {
        // Pack into felt252:
        //   low u128 = value
        //   high u128 = next (bits 0-63) | is_deleted (bit 64) | exists (bit 65)
        let deleted_bit: u128 = if value.is_deleted {
            TWO_POW_64
        } else {
            0
        };
        let exists_bit: u128 = if value.exists {
            TWO_POW_65
        } else {
            0
        };
        let high: u128 = value.next.into() + deleted_bit + exists_bit;
        let u256_val: u256 = u256 { low: value.value, high };
        u256_val.try_into().unwrap()
    }

    fn unpack(value: felt252) -> MapEntry {
        let u256 { low, high } = value.into();
        let next: u64 = (high & MASK_64).try_into().unwrap();
        let is_deleted: bool = (high & TWO_POW_64) != 0;
        let exists: bool = (high & TWO_POW_65) != 0;
        MapEntry { value: low, next, is_deleted, exists }
    }
}


/// A Map like struct that represents a map in a contract storage that can also be iterated over.
/// Uses a linked list to track keys (u64), eliminating redundant reads when updating existing
/// entries.
/// Head, tail, and length are packed into u256 (split into 2 u128 values) for storage efficiency.
/// Stores u128 values directly, combined with next pointer for single-read iteration.
#[starknet::storage_node]
#[allow(starknet::invalid_storage_member_types)]
pub struct LinkedIterableMap {
    // Combined storage: each entry stores value (u128) + next pointer with deleted flag (u64)
    // This allows only one read per member during iteration
    _entries: Map<u64, felt252>,
    // Linked list structure: head, tail, and length packed into felt252
    // Layout: first u128 = head (u64, lower) | length (u64, upper)
    //         second u128 = tail (u64, lower)
    // 0 means None for head/tail
    _head_tail_length: felt252,
}

/// Helper struct to pack head, tail, length, and total_nodes
/// Layout in felt252 (224 bits total, fits in 251-bit felt):
///   - bits 0-63: head (u64)
///   - bits 64-95: length (u32)
///   - bits 96-127: total_nodes (u32)
///   - bits 128-191: tail (u64)
#[derive(Copy, Drop)]
struct HeadTailLength {
    head: u64,
    tail: u64,
    length: u32, // Count of non-deleted items
    total_nodes: u32 // Total nodes in linked list (including deleted)
}

impl HeadTailLengthStorePacking of StorePacking<HeadTailLength, felt252> {
    fn pack(value: HeadTailLength) -> felt252 {
        // Pack into u256:
        //   low u128 = head (bits 0-63) | length (bits 64-95) | total_nodes (bits 96-127)
        //   high u128 = tail (bits 0-63)
        let low: u128 = value.head.into()
            + (value.length.into() * TWO_POW_64)
            + (value.total_nodes.into() * TWO_POW_96);
        let high: u128 = value.tail.into();

        // Convert u256 to felt252
        let u256_val: u256 = u256 { low, high: high };
        u256_val.try_into().unwrap()
    }

    fn unpack(value: felt252) -> HeadTailLength {
        // Convert felt252 to u256, then extract fields
        let u256 { low, high } = value.into();

        let head: u64 = (low & MASK_64).try_into().unwrap();
        let length: u32 = ((low / TWO_POW_64) & MASK_32).try_into().unwrap();
        let total_nodes: u32 = (low / TWO_POW_96).try_into().unwrap();
        let tail: u64 = high.try_into().unwrap();
        HeadTailLength { head, tail, length, total_nodes }
    }
}

/// Trait for the interface of a linked iterable map.
pub trait LinkedIterableMapTrait<T> {
    fn len(self: T) -> u32;
}

impl StoragePathLinkedIterableMapImpl of LinkedIterableMapTrait<StoragePath<LinkedIterableMap>> {
    fn len(self: StoragePath<LinkedIterableMap>) -> u32 {
        let packed = self._head_tail_length.read();
        let head_tail_length = HeadTailLengthStorePacking::unpack(packed);
        head_tail_length.length
    }
}

impl StoragePathMutableLinkedIterableMapImpl of LinkedIterableMapTrait<
    StoragePath<Mutable<LinkedIterableMap>>,
> {
    fn len(self: StoragePath<Mutable<LinkedIterableMap>>) -> u32 {
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
pub trait LinkedIterableMapReadAccess<T, V> {
    fn read(self: T, key: u64) -> V;
}

/// Trait for writing values with a specific type to the map
pub trait LinkedIterableMapWriteAccess<T, V> {
    fn write(self: T, key: u64, value: V);
}

/// Read implementation for StoragePath - supports any type that can be created from u128
impl StoragePathLinkedIterableMapReadAccessImpl<
    V, +TryInto<u128, V>, +Drop<V>,
> of LinkedIterableMapReadAccess<StoragePath<LinkedIterableMap>, V> {
    fn read(self: StoragePath<LinkedIterableMap>, key: u64) -> V {
        let packed: felt252 = StorageMapReadAccess::read(self._entries, key);
        let entry = MapEntryStorePacking::unpack(packed);
        entry.value.try_into().unwrap()
    }
}

impl StoragePathMutableLinkedIterableMapReadAccessImpl<
    V, +TryInto<u128, V>, +Drop<V>,
> of LinkedIterableMapReadAccess<StoragePath<Mutable<LinkedIterableMap>>, V> {
    fn read(self: StoragePath<Mutable<LinkedIterableMap>>, key: u64) -> V {
        self.as_non_mut().read(key)
    }
}

pub impl LinkedIterableMapReadAccessGenericImpl<
    T,
    V,
    +Drop<T>,
    +Drop<V>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: LinkedIterableMapReadAccess<StoragePath<StorageAsPathImpl::Value>, V>,
> of LinkedIterableMapReadAccess<T, V> {
    fn read(self: T, key: u64) -> V {
        self.as_path().read(key)
    }
}

/// Write implementation for StoragePath - supports any type that can convert to u128
impl StoragePathLinkedIterableMapWriteAccessImpl<
    V, +Into<V, u128>, +Drop<V>,
> of LinkedIterableMapWriteAccess<StoragePath<Mutable<LinkedIterableMap>>, V> {
    fn write(self: StoragePath<Mutable<LinkedIterableMap>>, key: u64, value: V) {
        let value_u128: u128 = value.into();

        // Read entry first - exists flag tells us if key is in the list
        let entry_packed: felt252 = StorageMapReadAccess::read(self._entries, key);
        let entry = MapEntryStorePacking::unpack(entry_packed);

        // Fast path: if entry exists and is not deleted, just update value
        // No need to read _head_tail_length at all
        if entry.exists && !entry.is_deleted {
            let new_entry = MapEntry {
                value: value_u128, next: entry.next, is_deleted: false, exists: true,
            };
            StorageMapWriteAccess::write(self._entries, key, MapEntryStorePacking::pack(new_entry));
            return;
        }

        // Need metadata for deleted entries or new keys
        let packed = self._head_tail_length.read();
        let mut head_tail_length = HeadTailLengthStorePacking::unpack(packed);

        if entry.exists {
            // Key was deleted - unmark as deleted
            head_tail_length.length += 1;
            let new_entry = MapEntry {
                value: value_u128, next: entry.next, is_deleted: false, exists: true,
            };
            StorageMapWriteAccess::write(self._entries, key, MapEntryStorePacking::pack(new_entry));
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
                next: key,
                is_deleted: old_tail_entry.is_deleted,
                exists: true,
            };
            StorageMapWriteAccess::write(
                self._entries, head_tail_length.tail, MapEntryStorePacking::pack(updated_tail),
            );
        } else {
            // First element - set as head
            head_tail_length.head = key;
        }
        // Update tail, length, and total_nodes
        head_tail_length.tail = key;
        head_tail_length.length += 1;
        head_tail_length.total_nodes += 1;
        // Write new entry with no next pointer (tail), marked as exists
        let new_entry = MapEntry { value: value_u128, next: 0, is_deleted: false, exists: true };
        StorageMapWriteAccess::write(self._entries, key, MapEntryStorePacking::pack(new_entry));
        self._head_tail_length.write(HeadTailLengthStorePacking::pack(head_tail_length));
    }
}

pub impl LinkedIterableMapWriteAccessGenericImpl<
    T,
    V,
    +Drop<T>,
    +Drop<V>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: LinkedIterableMapWriteAccess<StoragePath<StorageAsPathImpl::Value>, V>,
> of LinkedIterableMapWriteAccess<T, V> {
    fn write(self: T, key: u64, value: V) {
        self.as_path().write(key, value)
    }
}

/// Iterator implementation for linked list traversal
#[derive(Copy, Drop)]
struct LinkedMapIterator {
    _entries: StoragePath<Map<u64, felt252>>,
    _current: u64,
    _nodes_to_visit: u32 // Total nodes left to traverse (including deleted)
}

pub impl LinkedMapIteratorImpl of Iterator<LinkedMapIterator> {
    type Item = (u64, u128);
    fn next(ref self: LinkedMapIterator) -> Option<Self::Item> {
        // Keep iterating until we find a non-deleted item or run out of nodes
        loop {
            if self._nodes_to_visit == 0 {
                return Option::None;
            }

            let key = self._current;

            // Single read: get both value and next pointer from combined entry
            let packed: felt252 = StorageMapReadAccess::read(self._entries, key);
            let entry = MapEntryStorePacking::unpack(packed);

            // Move to next node
            self._current = entry.next;
            self._nodes_to_visit -= 1;

            // Skip deleted items
            if entry.is_deleted {
                continue;
            }

            // Return value from the same read - no extra storage access!
            return Option::Some((key, entry.value));
        }
    }
}

impl StoragePathLinkedIterableMapIntoIteratorImpl of IntoIterator<StoragePath<LinkedIterableMap>> {
    type IntoIter = LinkedMapIterator;
    fn into_iter(self: StoragePath<LinkedIterableMap>) -> Self::IntoIter {
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
struct LinkedMapIteratorMut {
    _entries: StoragePath<Mutable<Map<u64, felt252>>>,
    _current: u64,
    _nodes_to_visit: u32 // Total nodes left to traverse (including deleted)
}

pub impl LinkedMapIteratorMutImpl of Iterator<LinkedMapIteratorMut> {
    type Item = (u64, u128);
    fn next(ref self: LinkedMapIteratorMut) -> Option<Self::Item> {
        // Keep iterating until we find a non-deleted item or run out of nodes
        loop {
            if self._nodes_to_visit == 0 {
                return Option::None;
            }

            let key = self._current;

            // Single read: get both value and next pointer from combined entry
            let packed: felt252 = StorageMapReadAccess::read(self._entries, key);
            let entry = MapEntryStorePacking::unpack(packed);

            // Move to next node
            self._current = entry.next;
            self._nodes_to_visit -= 1;

            // Skip deleted items
            if entry.is_deleted {
                continue;
            }

            // Return value from the same read - no extra storage access!
            return Option::Some((key, entry.value));
        }
    }
}

impl StoragePathMutableLinkedIterableMapIntoIteratorImpl of IntoIterator<
    StoragePath<Mutable<LinkedIterableMap>>,
> {
    type IntoIter = LinkedMapIteratorMut;
    fn into_iter(self: StoragePath<Mutable<LinkedIterableMap>>) -> Self::IntoIter {
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
pub trait MutableLinkedIterableMapTrait<T> {
    fn clear(self: T);
    fn remove(self: T, key: u64);
}

/// Trait for checking if a key is deleted (works on both mutable and non-mutable)
pub trait LinkedIterableMapDeletedTrait<T> {
    fn is_deleted(self: T, key: u64) -> bool;
}

impl MutableLinkedIterableMapImpl of MutableLinkedIterableMapTrait<
    StoragePath<Mutable<LinkedIterableMap>>,
> {
    fn clear(self: StoragePath<Mutable<LinkedIterableMap>>) {
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

    fn remove(self: StoragePath<Mutable<LinkedIterableMap>>, key: u64) {
        let entry_packed: felt252 = StorageMapReadAccess::read(self._entries, key);
        let entry = MapEntryStorePacking::unpack(entry_packed);

        // If doesn't exist or already deleted, do nothing
        if !entry.exists || entry.is_deleted {
            return;
        }

        // Mark as deleted, clear value, preserve next pointer and exists flag
        let deleted_entry = MapEntry {
            value: 0_u128, next: entry.next, is_deleted: true, exists: true,
        };
        StorageMapWriteAccess::write(self._entries, key, MapEntryStorePacking::pack(deleted_entry));

        // Decrement length
        let packed = self._head_tail_length.read();
        let mut head_tail_length = HeadTailLengthStorePacking::unpack(packed);
        head_tail_length.length -= 1;
        self._head_tail_length.write(HeadTailLengthStorePacking::pack(head_tail_length));
    }
}

impl LinkedIterableMapDeletedImpl of LinkedIterableMapDeletedTrait<StoragePath<LinkedIterableMap>> {
    fn is_deleted(self: StoragePath<LinkedIterableMap>, key: u64) -> bool {
        let entry_packed: felt252 = StorageMapReadAccess::read(self._entries, key);
        let entry = MapEntryStorePacking::unpack(entry_packed);
        entry.exists && entry.is_deleted
    }
}

impl LinkedIterableMapDeletedMutableImpl of LinkedIterableMapDeletedTrait<
    StoragePath<Mutable<LinkedIterableMap>>,
> {
    fn is_deleted(self: StoragePath<Mutable<LinkedIterableMap>>, key: u64) -> bool {
        self.as_non_mut().is_deleted(key)
    }
}

pub impl LinkedIterableMapDeletedTraitImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: LinkedIterableMapDeletedTrait<StoragePath<StorageAsPathImpl::Value>>,
> of LinkedIterableMapDeletedTrait<T> {
    fn is_deleted(self: T, key: u64) -> bool {
        self.as_path().is_deleted(key)
    }
}
