use core::hash::Hash;
use core::iter::{IntoIterator, Iterator};
use core::pedersen::HashState;
use starknet::Store;
use starknet::storage::{
    IntoIterRange, Map, Mutable, MutableVecTrait, PendingStoragePathTrait, StorageAsPath,
    StorageAsPointer, StorageMapReadAccess, StorageMapWriteAccess, StoragePath, StoragePathEntry,
    StoragePathMutableConversion, StoragePointer0Offset, StoragePointerReadAccess,
    StoragePointerWriteAccess, Vec, VecIter, VecTrait,
};

/// A Map like struct that represents a map in a contract storage that can also be iterated over.
/// Another thing that IterableMap is different from Map in that it returns Option<Value>, so values
/// that weren't written into it will return Option::None.
#[starknet::storage_node]
#[allow(starknet::invalid_storage_member_types)]
pub struct IterableMap<K, V> {
    _inner_map: Map<K, Option<V>>,
    _keys: Vec<K>,
}

/// Trait for the interface of a iterable map.
pub trait IterableMapTrait<T> {
    type Key;
    type Value;
    fn len(self: T) -> u64;
    fn keys_iter(self: T) -> VecIter<StoragePath<Vec<Self::Key>>>;
    fn pointer(self: T, key: Self::Key) -> StoragePointer0Offset<Option<Self::Value>>;
}


impl StoragePathIterableMapImpl<
    K, V, +Drop<K>, +Drop<V>, +Store<Option<V>>, +Hash<K, HashState>,
> of IterableMapTrait<StoragePath<IterableMap<K, V>>> {
    type Key = K;
    type Value = V;
    fn len(self: StoragePath<IterableMap<K, V>>) -> u64 {
        self._keys.len()
    }

    fn keys_iter(self: StoragePath<IterableMap<K, V>>) -> VecIter<StoragePath<Vec<K>>> {
        self._keys.as_path().into_iter_full_range()
    }

    fn pointer(
        self: StoragePath<IterableMap<K, V>>, key: Self::Key,
    ) -> StoragePointer0Offset<Option<Self::Value>> {
        self._inner_map.entry(key).as_ptr()
    }
}

impl StoragePathMutableIterableMapImpl<
    K, V, +Drop<K>, +Drop<V>, +Store<Option<V>>, +Hash<K, HashState>,
> of IterableMapTrait<StoragePath<Mutable<IterableMap<K, V>>>> {
    type Key = K;
    type Value = V;
    fn len(self: StoragePath<Mutable<IterableMap<K, V>>>) -> u64 {
        self.as_non_mut().len()
    }

    fn keys_iter(self: StoragePath<Mutable<IterableMap<K, V>>>) -> VecIter<StoragePath<Vec<K>>> {
        self.as_non_mut().keys_iter()
    }

    fn pointer(
        self: StoragePath<Mutable<IterableMap<K, V>>>, key: Self::Key,
    ) -> StoragePointer0Offset<Option<Self::Value>> {
        self.as_non_mut().pointer(key)
    }
}

pub impl IterableMapTraitImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: IterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
    +Drop<StoragePathImpl::Key>,
> of IterableMapTrait<T> {
    type Key = StoragePathImpl::Key;
    type Value = StoragePathImpl::Value;
    fn len(self: T) -> u64 {
        self.as_path().len()
    }

    fn keys_iter(self: T) -> VecIter<StoragePath<Vec<Self::Key>>> {
        self.as_path().keys_iter()
    }

    fn pointer(self: T, key: Self::Key) -> StoragePointer0Offset<Option<StoragePathImpl::Value>> {
        self.as_path().pointer(key)
    }
}

/// Read and write access trait implementations:
impl StoragePathIterableMapReadAccessImpl<
    K, V, +Drop<K>, +Store<Option<V>>, +Hash<K, HashState>,
> of StorageMapReadAccess<StoragePath<IterableMap<K, V>>> {
    type Key = K;
    type Value = Option<V>;
    fn read(self: StoragePath<IterableMap<K, V>>, key: Self::Key) -> Self::Value {
        self._inner_map.entry(key).read()
    }
}

impl StoragePathMutableIterableMapReadAccessImpl<
    K, V, +Drop<K>, +Store<Option<V>>, +Hash<K, HashState>,
> of StorageMapReadAccess<StoragePath<Mutable<IterableMap<K, V>>>> {
    type Key = K;
    type Value = Option<V>;
    fn read(self: StoragePath<Mutable<IterableMap<K, V>>>, key: Self::Key) -> Self::Value {
        self.as_non_mut().read(key)
    }
}

pub impl IterableMapReadAccessImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: StorageMapReadAccess<StoragePath<StorageAsPathImpl::Value>>,
    +IterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
    +Drop<StoragePathImpl::Key>,
> of StorageMapReadAccess<T> {
    type Key = StoragePathImpl::Key;
    type Value = StoragePathImpl::Value;
    fn read(self: T, key: Self::Key) -> Self::Value {
        self.as_path().read(key)
    }
}

impl StoragePathIterableMapWriteAccessImpl<
    K, V, +Drop<K>, +Drop<V>, +Store<K>, +Store<V>, +Hash<K, HashState>, +Copy<K>,
> of StorageMapWriteAccess<StoragePath<Mutable<IterableMap<K, V>>>> {
    type Key = K;
    type Value = V;
    fn write(self: StoragePath<Mutable<IterableMap<K, V>>>, key: Self::Key, value: Self::Value) {
        let entry = self._inner_map.entry(key);
        if entry.read().is_none() {
            self._keys.push(key);
        }
        entry.write(Option::Some(value));
    }
}

pub impl IterableMapWriteAccessImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: StorageMapWriteAccess<StoragePath<StorageAsPathImpl::Value>>,
    +IterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
    +Drop<StoragePathImpl::Key>,
    +Drop<StoragePathImpl::Value>,
> of StorageMapWriteAccess<T> {
    type Key = StoragePathImpl::Key;
    type Value = StoragePathImpl::Value;
    fn write(self: T, key: Self::Key, value: Self::Value) {
        self.as_path().write(key, value)
    }
}

/// Iterator and IntoItarator implementations:
#[derive(Copy, Drop)]
struct MapIterator<K, V> {
    _inner_map: StoragePath<Map<K, Option<V>>>,
    _keys: StoragePath<Vec<K>>,
    _next_index: u64,
    _remaining: u64,
}

pub impl IterableMapIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>, +Store<Option<V>>,
> of Iterator<MapIterator<K, V>> {
    type Item = (K, V);
    fn next(ref self: MapIterator<K, V>) -> Option<Self::Item> {
        if self._remaining == 0 {
            return Option::None;
        } else {
            self._remaining -= 1;
        }
        let entry = PendingStoragePathTrait::<
            K, Vec<K>,
        >::new(storage_path: @(self._keys), pending_key: self._next_index.into())
            .as_path();
        let key = entry.read();
        self._next_index += 1;
        let value: V = self._inner_map.read(key).unwrap();
        Option::Some((key, value))
    }
}

impl StoragePathIterableMapIntoIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>, +Store<Option<V>>,
> of IntoIterator<StoragePath<IterableMap<K, V>>> {
    type IntoIter = MapIterator<K, V>;
    fn into_iter(self: StoragePath<IterableMap<K, V>>) -> Self::IntoIter {
        MapIterator {
            _inner_map: self._inner_map.as_path(),
            _keys: self._keys.as_path(),
            _next_index: 0,
            _remaining: self._keys.len(),
        }
    }
}

#[derive(Copy, Drop)]
struct MapIteratorMut<K, V> {
    _inner_map: StoragePath<Mutable<Map<K, Option<V>>>>,
    _keys: StoragePath<Mutable<Vec<K>>>,
    _next_index: u64,
    _remaining: u64,
}

pub impl IterableMapIteratorMutImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>, +Store<Option<V>>,
> of Iterator<MapIteratorMut<K, V>> {
    type Item = (K, V);
    fn next(ref self: MapIteratorMut<K, V>) -> Option<Self::Item> {
        if self._remaining == 0 {
            return Option::None;
        } else {
            self._remaining -= 1;
        }
        let entry = PendingStoragePathTrait::<
            K, Mutable<Vec<K>>,
        >::new(storage_path: @(self._keys), pending_key: self._next_index.into())
            .as_path();
        let key = entry.read();
        self._next_index += 1;
        let value: V = self._inner_map.read(key).unwrap();
        Option::Some((key, value))
    }
}

impl StoragePathMutableIterableMapIntoIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>, +Store<Option<V>>,
> of IntoIterator<StoragePath<Mutable<IterableMap<K, V>>>> {
    type IntoIter = MapIteratorMut<K, V>;
    fn into_iter(self: StoragePath<Mutable<IterableMap<K, V>>>) -> Self::IntoIter {
        MapIteratorMut {
            _inner_map: self._inner_map.as_path(),
            _keys: self._keys.as_path(),
            _next_index: 0,
            _remaining: self._keys.len(),
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

/// Mutable trait for the interface of iterable map.
pub trait MutableIterableMapTrait<T> {
    type Key;
    fn clear(self: T);
}

/// Implement `MutableIterableMapTrait` for `StoragePath<Mutable<IterableMap<K, V>>>`.
impl MutableIterableMapImpl<
    K, V, +Drop<K>, +Drop<V>, +Store<Option<V>>, +Store<K>, +Hash<K, HashState>,
> of MutableIterableMapTrait<StoragePath<Mutable<IterableMap<K, V>>>> {
    type Key = K;
    fn clear(self: StoragePath<Mutable<IterableMap<K, V>>>) {
        let len = self._keys.len();
        for _ in 0..len {
            let key = self._keys.pop().unwrap();
            self._inner_map.entry(key).write(Option::None);
        }
    }
}
