use starknet::storage::{
    Mutable, StorageAsPointer, StoragePointer, StoragePointerReadAccess, StoragePointerWriteAccess,
};
use starknet::{ClassHash, ContractAddress, EthAddress, Store};


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
///
/// # Recommendation for Default Value Encoding
/// When used with storage structures like `LinkedIterableMap`, reading a non-existent
/// key returns storage's zero value, which is then decoded. To ensure predictable
/// behavior, implementations SHOULD satisfy:
/// - `encode(Default::default())` returns the zero representation `(0, 0)`
/// - `decode((0, 0))` returns `Default::default()`
///
/// This ensures that reading a missing key yields the type's default value.
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

/// Trait for types that can be cast to/from felt252.
pub trait CastableFelt<T> {
    fn encode(value: T) -> felt252;
    fn decode(value: felt252) -> T;
}

/// Marker trait to enforce this pattern only for specific basic types
pub trait IsBasicFeltType<T> {}

impl IsBasicFeltTypeFelt252 of IsBasicFeltType<felt252>;
impl IsBasicFeltTypeU8 of IsBasicFeltType<u8>;
impl IsBasicFeltTypeU16 of IsBasicFeltType<u16>;
impl IsBasicFeltTypeU32 of IsBasicFeltType<u32>;
impl IsBasicFeltTypeU64 of IsBasicFeltType<u64>;
impl IsBasicFeltTypeU128 of IsBasicFeltType<u128>;
impl IsBasicFeltTypeI8 of IsBasicFeltType<i8>;
impl IsBasicFeltTypeI16 of IsBasicFeltType<i16>;
impl IsBasicFeltTypeI32 of IsBasicFeltType<i32>;
impl IsBasicFeltTypeI64 of IsBasicFeltType<i64>;
impl IsBasicFeltTypeI128 of IsBasicFeltType<i128>;
impl IsBasicFeltTypeContractAddress of IsBasicFeltType<ContractAddress>;
impl IsBasicFeltTypeClassHash of IsBasicFeltType<ClassHash>;
impl IsBasicFeltTypeEthAddress of IsBasicFeltType<EthAddress>;

/// Generic implementation for basic types that fit into felt252
pub impl PrimitiveCastableFelt<
    T, +IsBasicFeltType<T>, +Into<T, felt252>, +TryInto<felt252, T>, +Drop<T>,
> of CastableFelt<T> {
    fn encode(value: T) -> felt252 {
        value.into()
    }
    fn decode(value: felt252) -> T {
        value.try_into().unwrap()
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

/// Zigzag encoding for signed integers: maps signed to unsigned while preserving 0 → 0.
/// encode(0) = 0, encode(1) = 2, encode(-1) = 1, encode(2) = 4, encode(-2) = 3, etc.
pub impl SignedIntegerCastable160<
    T,
    +SignedIntegerOffset<T>,
    +Into<T, felt252>,
    +TryInto<felt252, T>,
    +Drop<T>,
    +Copy<T>,
    +PartialOrd<T>,
    +Default<T>,
> of Castable160<T> {
    fn encode(value: T) -> (u128, u32) {
        let val_felt: felt252 = value.into();
        let val_u128: u128 = if value >= Default::default() {
            // Non-negative: multiply by 2
            (val_felt * 2).try_into().unwrap()
        } else {
            // Negative: (-value) * 2 - 1
            ((-val_felt) * 2 - 1).try_into().unwrap()
        };
        (val_u128, 0)
    }
    fn decode(value: (u128, u32)) -> T {
        let (low, high) = value;
        assert(high == 0, 'Castable160: high bits not 0');
        let val_felt: felt252 = if low % 2 == 0 {
            // Even: non-negative, divide by 2
            (low / 2).into()
        } else {
            // Odd: negative, -((n + 1) / 2)
            let positive: felt252 = ((low - 1) / 2).into() + 1;
            -positive
        };
        val_felt.try_into().unwrap()
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
///
/// # Recommendation for Default Value Encoding
/// When used with storage structures like `LinkedIterableMap`, reading a non-existent
/// key returns storage's zero value, which is then decoded. To ensure predictable
/// behavior, implementations SHOULD satisfy:
/// - `encode(Default::default())` returns `0`
/// - `decode(0)` returns `Default::default()`
///
/// This ensures that reading a missing key yields the type's default value.
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

/// Zigzag encoding for signed integers that fit in 64 bits.
/// encode(0) = 0, encode(1) = 2, encode(-1) = 1, encode(2) = 4, encode(-2) = 3, etc.
pub impl SignedIntegerCastable64<
    T,
    +FitsIn64<T>,
    +Into<T, felt252>,
    +TryInto<felt252, T>,
    +Drop<T>,
    +Copy<T>,
    +PartialOrd<T>,
    +Default<T>,
> of Castable64<T> {
    fn encode(value: T) -> u64 {
        let val_felt: felt252 = value.into();
        if value >= Default::default() {
            // Non-negative: multiply by 2
            (val_felt * 2).try_into().unwrap()
        } else {
            // Negative: (-value) * 2 - 1
            ((-val_felt) * 2 - 1).try_into().unwrap()
        }
    }
    fn decode(value: u64) -> T {
        let val_felt: felt252 = if value % 2 == 0 {
            // Even: non-negative, divide by 2
            (value / 2).into()
        } else {
            // Odd: negative, -((n + 1) / 2)
            let positive: felt252 = ((value - 1) / 2).into() + 1;
            -positive
        };
        val_felt.try_into().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use starknet::{ClassHash, ContractAddress, EthAddress};
    use super::{
        Castable160, Castable64, CastableFelt, EthAddressCastable160, PrimitiveCastable160,
        PrimitiveCastable64, PrimitiveCastableFelt, SignedIntegerCastable160,
        SignedIntegerCastable64,
    };

    #[test]
    fn test_castable_felt_primitives() {
        // u8
        let v_u8: u8 = 255;
        let enc_u8 = CastableFelt::encode(v_u8);
        let dec_u8: u8 = CastableFelt::decode(enc_u8);
        assert_eq!(v_u8, dec_u8);

        // u16
        let v_u16: u16 = 65535;
        let enc_u16 = CastableFelt::encode(v_u16);
        let dec_u16: u16 = CastableFelt::decode(enc_u16);
        assert_eq!(v_u16, dec_u16);

        // u32
        let v_u32: u32 = 4294967295;
        let enc_u32 = CastableFelt::encode(v_u32);
        let dec_u32: u32 = CastableFelt::decode(enc_u32);
        assert_eq!(v_u32, dec_u32);

        // u64
        let v_u64: u64 = 18446744073709551615;
        let enc_u64 = CastableFelt::encode(v_u64);
        let dec_u64: u64 = CastableFelt::decode(enc_u64);
        assert_eq!(v_u64, dec_u64);

        // u128
        let v_u128: u128 = 340282366920938463463374607431768211455;
        let enc_u128 = CastableFelt::encode(v_u128);
        let dec_u128: u128 = CastableFelt::decode(enc_u128);
        assert_eq!(v_u128, dec_u128);

        // felt252
        let v_felt: felt252 = 123456789;
        let enc_felt = CastableFelt::encode(v_felt);
        let dec_felt: felt252 = CastableFelt::decode(enc_felt);
        assert_eq!(v_felt, dec_felt);
    }

    #[test]
    fn test_castable_felt_signed() {
        // i8
        let v_i8: i8 = -100;
        let enc_i8 = CastableFelt::encode(v_i8);
        let dec_i8: i8 = CastableFelt::decode(enc_i8);
        assert_eq!(v_i8, dec_i8);

        // i16
        let v_i16: i16 = -30000;
        let enc_i16 = CastableFelt::encode(v_i16);
        let dec_i16: i16 = CastableFelt::decode(enc_i16);
        assert_eq!(v_i16, dec_i16);

        // i32
        let v_i32: i32 = -2000000000;
        let enc_i32 = CastableFelt::encode(v_i32);
        let dec_i32: i32 = CastableFelt::decode(enc_i32);
        assert_eq!(v_i32, dec_i32);

        // i64
        let v_i64: i64 = -9000000000000000000;
        let enc_i64 = CastableFelt::encode(v_i64);
        let dec_i64: i64 = CastableFelt::decode(enc_i64);
        assert_eq!(v_i64, dec_i64);

        // i128
        let v_i128: i128 = -170141183460469231731687303715884100000;
        let enc_i128 = CastableFelt::encode(v_i128);
        let dec_i128: i128 = CastableFelt::decode(enc_i128);
        assert_eq!(v_i128, dec_i128);
    }

    #[test]
    fn test_castable_felt_addresses() {
        // ContractAddress
        let v_ca: ContractAddress = 12345.try_into().unwrap();
        let enc_ca = CastableFelt::encode(v_ca);
        let dec_ca: ContractAddress = CastableFelt::decode(enc_ca);
        assert_eq!(v_ca, dec_ca);

        // ClassHash
        let v_ch: ClassHash = 67890.try_into().unwrap();
        let enc_ch = CastableFelt::encode(v_ch);
        let dec_ch: ClassHash = CastableFelt::decode(enc_ch);
        assert_eq!(v_ch, dec_ch);

        // EthAddress
        let v_ea: EthAddress = 0x1234567890abcdef1234567890abcdef12345678.try_into().unwrap();
        let enc_ea = CastableFelt::encode(v_ea);
        let dec_ea: EthAddress = CastableFelt::decode(enc_ea);
        assert_eq!(v_ea, dec_ea);
    }

    // -------------------------------------------------------------------------
    // Tests for encode(default) == 0 and decode(0) == default property
    // -------------------------------------------------------------------------
    // These tests verify the recommended property that decode(0) should return
    // the type's default value. Unsigned types satisfy this property, while
    // signed integer types do NOT (they return the minimum value instead).

    #[test]
    fn test_castable160_decode_zero_unsigned_types() {
        // Unsigned types: decode((0, 0)) should return 0 (the default)
        let dec_u8: u8 = Castable160::decode((0, 0));
        assert_eq!(dec_u8, 0_u8);

        let dec_u16: u16 = Castable160::decode((0, 0));
        assert_eq!(dec_u16, 0_u16);

        let dec_u32: u32 = Castable160::decode((0, 0));
        assert_eq!(dec_u32, 0_u32);

        let dec_u64: u64 = Castable160::decode((0, 0));
        assert_eq!(dec_u64, 0_u64);

        let dec_u128: u128 = Castable160::decode((0, 0));
        assert_eq!(dec_u128, 0_u128);

        // EthAddress: decode((0, 0)) should return zero address
        let dec_eth: EthAddress = Castable160::decode((0, 0));
        let zero_eth: EthAddress = 0.try_into().unwrap();
        assert_eq!(dec_eth, zero_eth);
    }

    #[test]
    fn test_castable160_encode_default_unsigned_types() {
        // Unsigned types: encode(0) should return (0, 0)
        assert_eq!(Castable160::encode(0_u8), (0, 0));
        assert_eq!(Castable160::encode(0_u16), (0, 0));
        assert_eq!(Castable160::encode(0_u32), (0, 0));
        assert_eq!(Castable160::encode(0_u64), (0, 0));
        assert_eq!(Castable160::encode(0_u128), (0, 0));

        // EthAddress: encode(zero) should return (0, 0)
        let zero_eth: EthAddress = 0.try_into().unwrap();
        assert_eq!(Castable160::encode(zero_eth), (0, 0));
    }

    #[test]
    fn test_castable160_decode_zero_signed_types() {
        // Signed types: decode((0, 0)) SHOULD return 0 (the default value)

        let dec_i8: i8 = Castable160::decode((0, 0));
        assert_eq!(dec_i8, 0_i8);

        let dec_i16: i16 = Castable160::decode((0, 0));
        assert_eq!(dec_i16, 0_i16);

        let dec_i32: i32 = Castable160::decode((0, 0));
        assert_eq!(dec_i32, 0_i32);

        let dec_i64: i64 = Castable160::decode((0, 0));
        assert_eq!(dec_i64, 0_i64);

        let dec_i128: i128 = Castable160::decode((0, 0));
        assert_eq!(dec_i128, 0_i128);
    }

    #[test]
    fn test_castable160_encode_default_signed_types() {
        // Signed types: encode(0) SHOULD return (0, 0)

        assert_eq!(Castable160::encode(0_i8), (0, 0));
        assert_eq!(Castable160::encode(0_i16), (0, 0));
        assert_eq!(Castable160::encode(0_i32), (0, 0));
        assert_eq!(Castable160::encode(0_i64), (0, 0));
        assert_eq!(Castable160::encode(0_i128), (0, 0));
    }

    #[test]
    fn test_castable64_decode_zero_unsigned_types() {
        // Unsigned types: decode(0) should return 0 (the default)
        let dec_u8: u8 = Castable64::decode(0);
        assert_eq!(dec_u8, 0_u8);

        let dec_u16: u16 = Castable64::decode(0);
        assert_eq!(dec_u16, 0_u16);

        let dec_u32: u32 = Castable64::decode(0);
        assert_eq!(dec_u32, 0_u32);

        let dec_u64: u64 = Castable64::decode(0);
        assert_eq!(dec_u64, 0_u64);
    }

    #[test]
    fn test_castable64_encode_default_unsigned_types() {
        // Unsigned types: encode(0) should return 0
        assert_eq!(Castable64::encode(0_u8), 0);
        assert_eq!(Castable64::encode(0_u16), 0);
        assert_eq!(Castable64::encode(0_u32), 0);
        assert_eq!(Castable64::encode(0_u64), 0);
    }

    #[test]
    fn test_castable64_decode_zero_signed_types() {
        // Signed types: decode(0) SHOULD return 0 (the default value)

        let dec_i8: i8 = Castable64::decode(0);
        assert_eq!(dec_i8, 0_i8);

        let dec_i16: i16 = Castable64::decode(0);
        assert_eq!(dec_i16, 0_i16);

        let dec_i32: i32 = Castable64::decode(0);
        assert_eq!(dec_i32, 0_i32);

        let dec_i64: i64 = Castable64::decode(0);
        assert_eq!(dec_i64, 0_i64);
    }

    #[test]
    fn test_castable64_encode_default_signed_types() {
        // Signed types: encode(0) SHOULD return 0

        assert_eq!(Castable64::encode(0_i8), 0);
        assert_eq!(Castable64::encode(0_i16), 0);
        assert_eq!(Castable64::encode(0_i32), 0);
        assert_eq!(Castable64::encode(0_i64), 0);
    }
}
