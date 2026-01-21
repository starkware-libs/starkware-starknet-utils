use starknet::EthAddress;
use starkware_utils::storage::utils::{Castable160, Castable64};

#[test]
fn test_u8_castable() {
    let val: u8 = 10;
    let packed = Castable160::encode(val);
    let unpacked: u8 = Castable160::decode(packed);
    assert(val == unpacked, 'u8 mismatch');
}

#[test]
fn test_u128_castable() {
    let val: u128 = 340282366920938463463374607431768211455; // MAX
    let packed = Castable160::encode(val);
    let unpacked: u128 = Castable160::decode(packed);
    assert(val == unpacked, 'u128 mismatch');
}

#[test]
fn test_i8_castable() {
    let val: i8 = -10;
    let packed = Castable160::encode(val);
    let unpacked: i8 = Castable160::decode(packed);
    assert(val == unpacked, 'i8 mismatch');

    let val: i8 = 127;
    let packed = Castable160::encode(val);
    let unpacked: i8 = Castable160::decode(packed);
    assert(val == unpacked, 'i8 max mismatch');

    let val: i8 = -128;
    let packed = Castable160::encode(val);
    let unpacked: i8 = Castable160::decode(packed);
    assert(val == unpacked, 'i8 min mismatch');
}

#[test]
fn test_i128_castable() {
    let val: i128 = -170141183460469231731687303715884105728;
    let packed = Castable160::encode(val);
    let unpacked: i128 = Castable160::decode(packed);
    assert(val == unpacked, 'i128 mismatch');
}

#[test]
fn test_eth_address_castable() {
    let val: EthAddress = 1252485858049991401322336118102073441816987242963.try_into().unwrap();
    let packed = Castable160::encode(val);
    let unpacked: EthAddress = Castable160::decode(packed);
    assert(val == unpacked, 'EthAddress mismatch');
}

#[test]
#[should_panic(expected: ('Castable160: high bits not 0',))]
fn test_high_bits_panic() {
    let packed = (1, 1); // High bit set
    let _val: u8 = Castable160::decode(packed);
}

#[test]
fn test_u8_Castable64() {
    let val: u8 = 10;
    let packed = Castable64::encode(val);
    let unpacked: u8 = Castable64::decode(packed);
    assert(val == unpacked, 'u8 Castable64 mismatch');
}

#[test]
fn test_u64_Castable64() {
    let val: u64 = 18446744073709551615; // MAX
    let packed = Castable64::encode(val);
    let unpacked: u64 = Castable64::decode(packed);
    assert(val == unpacked, 'u64 Castable64 mismatch');
}

#[test]
fn test_i8_Castable64() {
    let val: i8 = -10;
    let packed = Castable64::encode(val);
    let unpacked: i8 = Castable64::decode(packed);
    assert(val == unpacked, 'i8 Castable64 mismatch');
}

#[test]
fn test_i64_Castable64() {
    let val: i64 = -10;
    let packed = Castable64::encode(val);
    let unpacked: i64 = Castable64::decode(packed);
    assert(val == unpacked, 'i64 Castable64 mismatch');

    let val: i64 = 9223372036854775807; // MAX
    let packed = Castable64::encode(val);
    let unpacked: i64 = Castable64::decode(packed);
    assert(val == unpacked, 'i64 max Castable64 mismatch');

    let val: i64 = -9223372036854775808; // MIN
    let packed = Castable64::encode(val);
    let unpacked: i64 = Castable64::decode(packed);
    assert(val == unpacked, 'i64 min Castable64 mismatch');
}
