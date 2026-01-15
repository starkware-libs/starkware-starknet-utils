use starknet::EthAddress;
use starkware_utils::storage::utils::{Storable160, Storable64};

#[test]
fn test_u8_storable() {
    let val: u8 = 10;
    let packed = Storable160::encode(val);
    let unpacked: u8 = Storable160::decode(packed);
    assert(val == unpacked, 'u8 mismatch');
}

#[test]
fn test_u128_storable() {
    let val: u128 = 340282366920938463463374607431768211455; // MAX
    let packed = Storable160::encode(val);
    let unpacked: u128 = Storable160::decode(packed);
    assert(val == unpacked, 'u128 mismatch');
}

#[test]
fn test_i8_storable() {
    let val: i8 = -10;
    let packed = Storable160::encode(val);
    let unpacked: i8 = Storable160::decode(packed);
    assert(val == unpacked, 'i8 mismatch');

    let val: i8 = 127;
    let packed = Storable160::encode(val);
    let unpacked: i8 = Storable160::decode(packed);
    assert(val == unpacked, 'i8 max mismatch');

    let val: i8 = -128;
    let packed = Storable160::encode(val);
    let unpacked: i8 = Storable160::decode(packed);
    assert(val == unpacked, 'i8 min mismatch');
}

#[test]
fn test_i128_storable() {
    let val: i128 = -10;
    let packed = Storable160::encode(val);
    let unpacked: i128 = Storable160::decode(packed);
    assert(val == unpacked, 'i128 mismatch');
}

#[test]
fn test_eth_address_storable() {
    let val: EthAddress = 123.try_into().unwrap();
    let packed = Storable160::encode(val);
    let unpacked: EthAddress = Storable160::decode(packed);
    assert(val == unpacked, 'EthAddress mismatch');
}

#[test]
#[should_panic(expected: ('Storable160: high bits not 0',))]
fn test_high_bits_panic() {
    let packed = (1, 1); // High bit set
    let _val: u8 = Storable160::decode(packed);
}

#[test]
fn test_u8_storable64() {
    let val: u8 = 10;
    let packed = Storable64::encode(val);
    let unpacked: u8 = Storable64::decode(packed);
    assert(val == unpacked, 'u8 storable64 mismatch');
}

#[test]
fn test_u64_storable64() {
    let val: u64 = 18446744073709551615; // MAX
    let packed = Storable64::encode(val);
    let unpacked: u64 = Storable64::decode(packed);
    assert(val == unpacked, 'u64 storable64 mismatch');
}

#[test]
fn test_i8_storable64() {
    let val: i8 = -10;
    let packed = Storable64::encode(val);
    let unpacked: i8 = Storable64::decode(packed);
    assert(val == unpacked, 'i8 storable64 mismatch');
}

#[test]
fn test_i64_storable64() {
    let val: i64 = -10;
    let packed = Storable64::encode(val);
    let unpacked: i64 = Storable64::decode(packed);
    assert(val == unpacked, 'i64 storable64 mismatch');

    let val: i64 = 9223372036854775807; // MAX
    let packed = Storable64::encode(val);
    let unpacked: i64 = Storable64::decode(packed);
    assert(val == unpacked, 'i64 max storable64 mismatch');

    let val: i64 = -9223372036854775808; // MIN
    let packed = Storable64::encode(val);
    let unpacked: i64 = Storable64::decode(packed);
    assert(val == unpacked, 'i64 min storable64 mismatch');
}
