use core::hash::Hash;
use core::iter::{IntoIterator, Iterator};
use core::pedersen::HashState;
use starknet::Store;
use starknet::storage::{
    Map, Mutable, StorageAsPath, StorageMapReadAccess, StorageMapWriteAccess, StoragePath,
};

#[derive(Copy, Drop, starknet::Store)]
struct Entry<K, V> {
    _value: V,
    _key: K,
}

#[generate_trait]
impl EntryImpl<K, V> of EntryTrait<K, V> {
    fn key(self: Entry<K, V>) -> K {
        self._key
    }
    fn value(self: Entry<K, V>) -> V {
        self._value
    }
}

/// FastIterableMap is a map that is optimized for fast iteration.
#[starknet::storage_node]
#[allow(starknet::invalid_storage_member_types)]
pub struct FastIterableMap<K, V> {
    _inner_map: Map<K, Entry<K, V>>,
    _initialized_map: Map<K, bool>,
    _head: K,
    _tail: K,
    _length: u64,
}

/// Trait for the interface of a iterable map.
pub trait FastIterableMapTrait<T> {
    type Key;
    fn len(self: T) -> u64;
}

impl StoragePathFastIterableMapImpl<
    K, V, +Drop<K>, +Drop<V>, +Store<V>, +Hash<K, HashState>,
> of FastIterableMapTrait<StoragePath<FastIterableMap<K, V>>> {
    type Key = K;
    fn len(self: StoragePath<FastIterableMap<K, V>>) -> u64 {
        self._length.read()
    }
}

impl StoragePathMutableFastIterableMapImpl<
    K, V, +Drop<K>, +Drop<V>, +Store<V>, +Hash<K, HashState>,
> of FastIterableMapTrait<StoragePath<Mutable<FastIterableMap<K, V>>>> {
    type Key = K;
    fn len(self: StoragePath<Mutable<FastIterableMap<K, V>>>) -> u64 {
        self._length.read()
    }
}

pub impl FastIterableMapTraitImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: FastIterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
    +Drop<StoragePathImpl::Key>,
> of FastIterableMapTrait<T> {
    type Key = StoragePathImpl::Key;
    fn len(self: T) -> u64 {
        self.as_path().len()
    }
}

/// Read and write access trait implementations:
impl StoragePathFastIterableMapReadAccessImpl<
    K, V, +Drop<K>, +Drop<V>, +Store<K>, +Store<V>, +Hash<K, HashState>,
> of StorageMapReadAccess<StoragePath<FastIterableMap<K, V>>> {
    type Key = K;
    type Value = V;
    fn read(self: StoragePath<FastIterableMap<K, V>>, key: Self::Key) -> Option<Self::Value> {
        if self._initialized_map.entry(key).read() == true {
            Option::Some(self._inner_map.entry(key).read().value())
        } else {
            Option::None
        }
    }
}

impl StoragePathMutableFastIterableMapReadAccessImpl<
    K, V, +Drop<K>, +Store<V>, +Default<V>, +Hash<K, HashState>,
> of StorageMapReadAccess<StoragePath<Mutable<FastIterableMap<K, V>>>> {
    type Key = K;
    type Value = V;
    fn read(
        self: StoragePath<Mutable<FastIterableMap<K, V>>>, key: Self::Key,
    ) -> Option<Self::Value> {
        if self._initialized_map.entry(key).read() == true {
            Option::Some(self._inner_map.entry(key).read().value())
        } else {
            Option::None
        }
    }
}

pub impl FastIterableMapReadAccessImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: StorageMapReadAccess<StoragePath<StorageAsPathImpl::Value>>,
    +FastIterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
    +Drop<StoragePathImpl::Key>,
> of StorageMapReadAccess<T> {
    type Key = StoragePathImpl::Key;
    type Value = StoragePathImpl::Value;
    fn read(self: T, key: Self::Key) -> Self::Value {
        self.as_path().read(key)
    }
}

impl StoragePathFastIterableMapWriteAccessImpl<
    K, V, +Drop<K>, +Drop<V>, +Store<K>, +Store<V>, +Hash<K, HashState>, +Copy<K>,
> of StorageMapWriteAccess<StoragePath<Mutable<FastIterableMap<K, V>>>> {
    type Key = K;
    type Value = V;
    fn write(
        self: StoragePath<Mutable<FastIterableMap<K, V>>>, key: Self::Key, value: Self::Value,
    ) {
        if self._initialized_map.entry(key).read() == true {
            self._inner_map.entry(key).read().value().write(value);
        } else {
            let current_length = self._length.read();
            if current_length != 0 {
                let current_tail_key = self._tail.read();
                self._inner_map.entry(current_tail_key).read().key().write(key);
            } else {
                self._head.write(key);
            }
            self._tail.write(key);
            self._initialized_map.entry(key).write(true);
            self._length.write(current_length + 1);
            self._inner_map.entry(key).read().value().write(value);
        }
    }
}

pub impl FastIterableMapWriteAccessImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: StorageMapWriteAccess<StoragePath<StorageAsPathImpl::Value>>,
    +FastIterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
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
struct FastMapIterator<K, V> {
    _inner_map: Map<K, Entry<K, V>>,
    _current_key: K,
    _current_index: u64,
    _length: u64,
}

#[derive(Copy, Drop)]
struct FastMapIteratorMut<K, V> {
    _inner_map: Map<K, Entry<K, V>>,
    _current_key: K,
    _current_index: u64,
    _length: u64,
}

pub impl FastIterableMapIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>, +Store<V>,
> of Iterator<FastMapIterator<K, V>> {
    type Item = (K, V);
    fn next(ref self: FastMapIterator<K, V>) -> Option<Self::Item> {
        if self._current_index >= self._length {
            return Option::None;
        }
        let current_key = self._current_key;
        let current_entry = self._inner_map.entry(current_key).read();
        self._current_key = current_entry.key();
        self._current_index += 1;
        Option::Some((current_key, current_entry.value()))
    }
}

impl StoragePathFastIterableMapIntoIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>, +Store<V>,
> of IntoIterator<StoragePath<FastIterableMap<K, V>>> {
    type IntoIter = FastMapIterator<K, V>;
    fn into_iter(self: StoragePath<FastIterableMap<K, V>>) -> Self::IntoIter {
        FastMapIterator {
            _inner_map: self._inner_map,
            _current_key: self._head.read(),
            _current_index: 0,
            _length: self._length.read(),
        }
    }
}

pub impl FastIterableMapIteratorMutImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>, +Store<V>,
> of Iterator<FastMapIteratorMut<K, V>> {
    type Item = (K, V);
    fn next(ref self: FastMapIteratorMut<K, V>) -> Option<Self::Item> {
        if self._current_index >= self._length {
            return Option::None;
        }
        let current_key = self._current_key;
        let current_entry = self._inner_map.entry(current_key).read();
        self._current_key = current_entry.key();
        self._current_index += 1;
        Option::Some((current_key, current_entry.value()))
    }
}

impl StoragePathMutableFastIterableMapIntoIteratorImpl<
    K, V, +Drop<K>, +Store<K>, +Hash<K, HashState>, +Copy<K>, +Store<V>,
> of IntoIterator<StoragePath<Mutable<FastIterableMap<K, V>>>> {
    type IntoIter = FastMapIteratorMut<K, V>;
    fn into_iter(self: StoragePath<Mutable<FastIterableMap<K, V>>>) -> Self::IntoIter {
        FastMapIteratorMut {
            _inner_map: self._inner_map,
            _current_key: self._head.read(),
            _current_index: 0,
            _length: self._length.read(),
        }
    }
}

pub impl FastIterableMapIntoIterImpl<
    T,
    +Drop<T>,
    impl StorageAsPathImpl: StorageAsPath<T>,
    impl StoragePathImpl: IntoIterator<StoragePath<StorageAsPathImpl::Value>>,
    +FastIterableMapTrait<StoragePath<StorageAsPathImpl::Value>>,
> of IntoIterator<T> {
    type IntoIter = StoragePathImpl::IntoIter;
    fn into_iter(self: T) -> Self::IntoIter {
        self.as_path().into_iter()
    }
}
