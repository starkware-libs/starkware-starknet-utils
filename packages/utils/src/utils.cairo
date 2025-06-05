use openzeppelin::account::utils::is_valid_stark_signature;
use starknet::Store;
use starknet::storage::{
    Mutable, StorageAsPointer, StoragePointer, StoragePointerReadAccess, StoragePointerWriteAccess,
};
use starkware_utils::errors::assert_with_byte_array;
use starkware_utils::math::fraction::FractionTrait;
use starkware_utils::types::time::time::{Time, Timestamp};
use starkware_utils::types::{HashType, PublicKey, Signature};

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

pub fn validate_stark_signature(public_key: PublicKey, msg_hash: HashType, signature: Signature) {
    assert(
        is_valid_stark_signature(:msg_hash, :public_key, :signature), 'INVALID_STARK_KEY_SIGNATURE',
    );
}

pub fn validate_expiration(expiration: Timestamp, err: felt252) {
    assert(Time::now() <= expiration, err);
}

pub fn validate_ratio<N, D, +Into<N, i128>, +Drop<N>, +Into<D, u128>, +Drop<D>>(
    n1: i128, d1: u128, n2: i128, d2: u128, err: ByteArray,
) {
    let f1 = FractionTrait::new(numerator: n1, denominator: d1);
    let f2 = FractionTrait::new(numerator: n2, denominator: d2);
    assert_with_byte_array(f1 <= f2, err);
}

pub fn short_string_to_byte_array(felt: felt252) -> ByteArray {
    let mut ba = Default::default();
    let mut felt_num: u256 = felt.into();
    while (felt_num != 0) {
        let byte: u8 = (felt_num % 256_u256).try_into().unwrap();
        ba.append_byte(byte);
        felt_num = felt_num / 256_u256;
    }
    ba.rev()
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_short_string_to_byte_array() {
        let felt = 'this is my test';
        let ba = short_string_to_byte_array(felt);
        assert_eq!(ba, "this is my test");
    }
}
