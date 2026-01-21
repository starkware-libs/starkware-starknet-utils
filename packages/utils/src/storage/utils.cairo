use starknet::storage::{
    Mutable, StorageAsPointer, StoragePointer, StoragePointerReadAccess, StoragePointerWriteAccess,
};
use starknet::{EthAddress, Store};


pub trait AddToStorage<T> {
    type Value;
    fn add_and_write(self: T, value: Self::Value) -> Self::Value;
}

pub impl AddToStorageGeneralImpl<
    T,
    +Drop<T>,
    impl AsPointerImpl: StorageAsPointer<T>,
    impl PointerImpl: AddToStorage<StoragePointer<AsPointerImpl::Value>>,
    +Drop<PointerImpl::Value>,
> of AddToStorage<T> {
    type Value = PointerImpl::Value;
    fn add_and_write(self: T, value: Self::Value) -> Self::Value {
        self.as_ptr().deref().add_and_write(value)
    }
}

pub impl StoragePointerAddToStorageImpl<
    TValue, +Drop<TValue>, +Add<TValue>, +Copy<TValue>, +Store<TValue>,
> of AddToStorage<StoragePointer<Mutable<TValue>>> {
    type Value = TValue;
    fn add_and_write(self: StoragePointer<Mutable<TValue>>, value: TValue) -> TValue {
        let new_value = self.read() + value;
        self.write(new_value);
        new_value
    }
}

pub trait SubFromStorage<T> {
    type Value;
    fn sub_and_write(self: T, value: Self::Value) -> Self::Value;
}

pub impl SubFromStorageGeneralImpl<
    T,
    +Drop<T>,
    impl AsPointerImpl: StorageAsPointer<T>,
    impl PointerImpl: SubFromStorage<StoragePointer<AsPointerImpl::Value>>,
    +Drop<PointerImpl::Value>,
> of SubFromStorage<T> {
    type Value = PointerImpl::Value;
    fn sub_and_write(self: T, value: Self::Value) -> Self::Value {
        self.as_ptr().deref().sub_and_write(value)
    }
}

pub impl StoragePathSubFromStorageImpl<
    TValue, +Drop<TValue>, +Sub<TValue>, +Copy<TValue>, +Store<TValue>,
> of SubFromStorage<StoragePointer<Mutable<TValue>>> {
    type Value = TValue;
    fn sub_and_write(self: StoragePointer<Mutable<TValue>>, value: TValue) -> TValue {
        let new_value = self.read() - value;
        self.write(new_value);
        new_value
    }
}


/// Trait for types that can be stored as 160 bits.
///
/// The format is a tuple `(low: u128, high: u32)`.
///
/// # Requirements
/// - `encode` should be injective: distinct values map to distinct tuples.
/// - `decode` should be the inverse of `encode` on its image:
///   decode(encode(v)) == v
pub trait Castable160<V> {
    /// Convert a value into its 160-bit representation `(low, high)`.
    fn encode(value: V) -> (u128, u32);

    /// Convert a 160-bit representation back into the original value.
    fn decode(value: (u128, u32)) -> V;
}

/// `Castable160` implementation for primitive integer types ('u8', 'u16', 'u32', 'u64' and 'u128'.)
/// that fit entirely in 128 bits.
pub impl PrimitiveCastable160<T, +Into<T, u128>, +TryInto<u128, T>, +Drop<T>> of Castable160<T> {
    fn encode(value: T) -> (u128, u32) {
        (value.into(), 0)
    }
    fn decode(value: (u128, u32)) -> T {
        let (low, high) = value;
        assert(high == 0, 'Castable160: high bits not 0');
        low.try_into().unwrap()
    }
}

/// Trait to define the offset for signed integer.
trait SignedIntegerOffset<T> {
    fn offset() -> felt252;
}

impl I8Offset of SignedIntegerOffset<i8> {
    fn offset() -> felt252 {
        // 2 ** 7
        128
    }
}

impl I16Offset of SignedIntegerOffset<i16> {
    fn offset() -> felt252 {
        // 2** 15
        32768
    }
}

impl I32Offset of SignedIntegerOffset<i32> {
    fn offset() -> felt252 {
        // 2** 31
        2147483648
    }
}

impl I64Offset of SignedIntegerOffset<i64> {
    fn offset() -> felt252 {
        // 2** 63
        9223372036854775808
    }
}

impl I128Offset of SignedIntegerOffset<i128> {
    fn offset() -> felt252 {
        // 2** 127
        170141183460469231731687303715884105728
    }
}

pub impl SignedIntegerCastable160<
    T, +SignedIntegerOffset<T>, +Into<T, felt252>, +TryInto<felt252, T>, +Drop<T>,
> of Castable160<T> {
    fn encode(value: T) -> (u128, u32) {
        let val_felt: felt252 = value.into();
        let offset = SignedIntegerOffset::<T>::offset();
        let val_u128: u128 = (val_felt + offset).try_into().unwrap();
        (val_u128, 0)
    }
    fn decode(value: (u128, u32)) -> T {
        let (low, high) = value;
        assert(high == 0, 'Castable160: high bits not 0');
        let val_felt: felt252 = low.into();
        let offset = SignedIntegerOffset::<T>::offset();
        (val_felt - offset).try_into().unwrap()
    }
}

pub impl EthAddressCastable160 of Castable160<EthAddress> {
    fn encode(value: EthAddress) -> (u128, u32) {
        let felt_val: felt252 = value.into();
        let u256_val: u256 = felt_val.into();
        let low = u256_val.low;
        let high: u32 = u256_val.high.try_into().unwrap();
        (low, high)
    }
    fn decode(value: (u128, u32)) -> EthAddress {
        let (low, high) = value;
        let u256_val = u256 { low, high: high.into() };
        u256_val.try_into().unwrap()
    }
}

/// Trait for types that can be stored as 64 bits.
///
/// The format is a `u64`.
///
/// # Requirements
/// - `encode` should be injective: distinct values map to distinct tuples.
/// - `decode` should be the inverse of `encode` on its image:
///   decode(encode(v)) == v
pub trait Castable64<V> {
    /// Convert a value into its 64-bit representation.
    fn encode(value: V) -> u64;
    /// Convert a 64-bit representation back into the original value.
    fn decode(value: u64) -> V;
}

pub impl PrimitiveCastable64<T, +Into<T, u64>, +TryInto<u64, T>, +Drop<T>> of Castable64<T> {
    fn encode(value: T) -> u64 {
        value.into()
    }
    fn decode(value: u64) -> T {
        value.try_into().unwrap()
    }
}


/// Trait to check if a type fits in 64 bits.
trait FitsIn64<T> {}
impl I8FitsIn64 of FitsIn64<i8> {}
impl I16FitsIn64 of FitsIn64<i16> {}
impl I32FitsIn64 of FitsIn64<i32> {}
impl I64FitsIn64 of FitsIn64<i64> {}

pub impl SignedIntegerCastable64<
    T, +FitsIn64<T>, +SignedIntegerOffset<T>, +Into<T, felt252>, +TryInto<felt252, T>, +Drop<T>,
> of Castable64<T> {
    fn encode(value: T) -> u64 {
        let val_felt: felt252 = value.into();
        let offset = SignedIntegerOffset::<T>::offset();
        let val_u64: u64 = (val_felt + offset).try_into().unwrap();
        val_u64
    }
    fn decode(value: u64) -> T {
        let val_felt: felt252 = value.into();
        let offset = SignedIntegerOffset::<T>::offset();
        (val_felt - offset).try_into().unwrap()
    }
}
