use core::hash::Hash;
use core::iter::{IntoIterator, Iterator};
use core::num::traits::Zero;
use core::pedersen::HashState;
use starknet::Store;
use starknet::storage::{
    Map, Mutable, MutableVecTrait, PendingStoragePath, StorageAsPath, StoragePath, StoragePathEntry,
    StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
};

/// A Map like struct that represents a map in a contract storage that can also be iterated over.
/// Another thing that IterableMap is different from Map in that it returns Option<Value>, so values
/// that weren't written into it will return Option::None.
#[starknet::storage_node]
#[allow(starknet::invalid_storage_member_types)]
pub struct IterableMap<K, V> {
    _inner_map: Map<K, Entry<V>>,
    _keys: Vec<K>,
}

#[starknet::storage_node]
#[allow(starknet::invalid_storage_member_types)]
struct Entry<V> {
    _index: u64,
    _value: V,
}

/// Trait for the interface of an immutable iterable map.
pub trait IterableMapTrait<T> {
    type Key;
    type Value;
    type Entry;
    fn len(self: T) -> u64;
    fn entry(self: T, key: Self::Key) -> Option<Self::Entry>;
    fn read<+Store<Self::Value>>(self: T, key: Self::Key) -> Option<Self::Value>;
}

impl StoragePathIterableMapImpl<
    K, V, +Drop<K>, +Hash<K, HashState>,
> of IterableMapTrait<StoragePath<IterableMap<K, V>>> {
    type Key = K;
    type Value = V;
    type Entry = PendingStoragePath<V>;
    fn len(self: StoragePath<IterableMap<K, V>>) -> u64 {
        self._keys.len()
    }
    fn entry(
        self: StoragePath<IterableMap<K, V>>, key: Self::Key,
    ) -> Option<PendingStoragePath<Self::Value>> {
        let entry = self._inner_map.entry(key);
        match entry._index.read() {
            0 => Option::None,
            _ => Option::Some(entry._value),
        }
    }
    fn read<+Store<Self::Value>>(
        self: StoragePath<IterableMap<K, V>>, key: Self::Key,
    ) -> Option<Self::Value> {
        Option::Some(self.entry(key)?.read())
    }
}

impl StoragePathMutableIterableMapImpl<
    K, V, +Drop<K>, +Hash<K, HashState>,
> of IterableMapTrait<StoragePath<Mutable<IterableMap<K, V>>>> {
    type Key = K;
    type Value = V;
    type Entry = PendingStoragePath<Mutable<V>>;
    fn len(self: StoragePath<Mutable<IterableMap<K, V>>>) -> u64 {
        self._keys.len()
    }
    fn entry(
        self: StoragePath<Mutable<IterableMap<K, V>>>, key: Self::Key,
    ) -> Option<PendingStoragePath<Mutable<Self::Value>>> {
        let entry = self._inner_map.entry(key);
        match entry._index.read() {
            0 => Option::None,
            _ => Option::Some(entry._value),
        }
    }
    fn read<+Store<Self::Value>>(
        self: StoragePath<Mutable<IterableMap<K, V>>>, key: Self::Key,
    ) -> Option<Self::Value> {
        Option::Some(self.entry(key)?.read())
    }
}

impl IterableMapTraitImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: IterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
    +Drop<StoragePathImpl::Key>,
> of IterableMapTrait<T> {
    type Key = StoragePathImpl::Key;
    type Value = StoragePathImpl::Value;
    type Entry = StoragePathImpl::Entry;
    fn len(self: T) -> u64 {
        self.as_path().len()
    }
    fn entry(self: T, key: Self::Key) -> Option<Self::Entry> {
        self.as_path().entry(key)
    }
    fn read<+Store<Self::Value>>(self: T, key: Self::Key) -> Option<Self::Value> {
        self.as_path().read(key)
    }
}

/// Trait for the interface of a mutable iterable map.
pub trait IterableMapMutableTrait<T> {
    type Key;
    type Value;
    fn remove(self: T, key: Self::Key);
    fn allocate(self: T, key: Self::Key) -> PendingStoragePath<Mutable<Self::Value>>;
    fn write<+Store<Self::Value>, +Drop<Self::Value>>(self: T, key: Self::Key, value: Self::Value);
}

impl StoragePathMutableIterableMapTraitImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>,
> of IterableMapMutableTrait<StoragePath<Mutable<IterableMap<K, V>>>> {
    type Key = K;
    type Value = V;
    fn remove(self: StoragePath<Mutable<IterableMap<K, V>>>, key: Self::Key) {
        let entry = self._inner_map.entry(key);
        let index = entry._index.read();
        if index.is_zero() {
            return;
        }
        entry._index.write(0);
        let last_key = self._keys.pop().unwrap();
        if index <= self._keys.len() {
            self._inner_map.entry(last_key)._index.write(index);
            self._keys.at(index - 1).write(last_key);
        }
    }

    fn allocate(
        self: StoragePath<Mutable<IterableMap<K, V>>>, key: Self::Key,
    ) -> PendingStoragePath<Mutable<Self::Value>> {
        let entry = self._inner_map.entry(key);
        if entry._index.read().is_zero() {
            self._keys.push(key);
            entry._index.write(self._keys.len());
        }
        entry._value
    }

    fn write<+Store<Self::Value>, +Drop<Self::Value>>(
        self: StoragePath<Mutable<IterableMap<K, V>>>, key: Self::Key, value: Self::Value,
    ) {
        self.allocate(key).write(value);
    }
}

impl IterableMapMutableTraitImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: IterableMapMutableTrait<StoragePath<StorageAsPathImpl::Value>>,
    +Drop<StoragePathImpl::Key>,
> of IterableMapMutableTrait<T> {
    type Key = StoragePathImpl::Key;
    type Value = StoragePathImpl::Value;
    fn remove(self: T, key: Self::Key) {
        self.as_path().remove(key);
    }
    fn allocate(self: T, key: Self::Key) -> PendingStoragePath<Mutable<Self::Value>> {
        self.as_path().allocate(key)
    }
    fn write<+Store<Self::Value>, +Drop<Self::Value>>(self: T, key: Self::Key, value: Self::Value) {
        self.as_path().write(key, value)
    }
}

/// Iterator and IntoItarator implementations:
#[derive(Drop)]
struct MapIterator<K, V> {
    _inner_map: StoragePath<Map<K, Entry<V>>>,
    _keys: StoragePath<Vec<K>>,
    _current_index: core::ops::RangeIterator<u64>,
}

pub impl IterableMapIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>,
> of Iterator<MapIterator<K, V>> {
    type Item = (K, PendingStoragePath<V>);
    fn next(ref self: MapIterator<K, V>) -> Option<Self::Item> {
        let key = self._keys.get(self._current_index.next()?)?.read();
        Option::Some((key, self._inner_map.entry(key)._value))
    }
}

impl StoragePathIterableMapIntoIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>,
> of IntoIterator<StoragePath<IterableMap<K, V>>> {
    type IntoIter = MapIterator<K, V>;
    fn into_iter(self: StoragePath<IterableMap<K, V>>) -> Self::IntoIter {
        MapIterator {
            _inner_map: self._inner_map.as_path(),
            _keys: self._keys.as_path(),
            _current_index: (0..self._keys.len()).into_iter(),
        }
    }
}

#[derive(Drop)]
struct MapIteratorMut<K, V> {
    _inner_map: StoragePath<Mutable<Map<K, Entry<V>>>>,
    _keys: StoragePath<Mutable<Vec<K>>>,
    _current_index: core::ops::RangeIterator<u64>,
}

pub impl IterableMapIteratorMutImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>,
> of Iterator<MapIteratorMut<K, V>> {
    type Item = (K, PendingStoragePath<Mutable<V>>);
    fn next(ref self: MapIteratorMut<K, V>) -> Option<Self::Item> {
        let key = self._keys.get(self._current_index.next()?)?.read();
        Option::Some((key, self._inner_map.entry(key)._value))
    }
}

impl StoragePathMutableIterableMapIntoIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>,
> of IntoIterator<StoragePath<Mutable<IterableMap<K, V>>>> {
    type IntoIter = MapIteratorMut<K, V>;
    fn into_iter(self: StoragePath<Mutable<IterableMap<K, V>>>) -> Self::IntoIter {
        MapIteratorMut {
            _inner_map: self._inner_map.as_path(),
            _keys: self._keys.as_path(),
            _current_index: (0..self._keys.len()).into_iter(),
        }
    }
}

pub impl IterableMapIntoIterImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: IntoIterator<StoragePath<StorageAsPathImpl::Value>>,
    +IterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
> of IntoIterator<T> {
    type IntoIter = StoragePathImpl::IntoIter;
    fn into_iter(self: T) -> Self::IntoIter {
        self.as_path().into_iter()
    }
}
