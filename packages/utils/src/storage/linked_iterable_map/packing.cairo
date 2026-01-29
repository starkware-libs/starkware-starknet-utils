use core::num::traits::Pow;
use starknet::storage_access::StorePacking;

const TWO_POW_32: u128 = 2_u128.pow(32);
const TWO_POW_64: u128 = 2_u128.pow(64);
const TWO_POW_96: u128 = 2_u128.pow(96);
const TWO_POW_97: u128 = 2_u128.pow(97);
const MASK_32: u128 = TWO_POW_32 - 1;
const MASK_64: u128 = TWO_POW_64 - 1;

/// Entry structure packing value, next pointer, deleted flag, and exists flag together
/// This allows a single read per member during iteration
/// Layout in felt252 (226 bits total, fits in 251-bit felt):
///   - bits 0-127: value_low (u128)
///   - bits 128-159: value_high (u32)
///   - bits 160-223: next key (u64)
///   - bit 224: is_deleted flag
///   - bit 225: exists flag
#[derive(Copy, Drop, PartialEq, Serde, Debug)]
pub struct MapEntry {
    pub value: (u128, u32),
    pub next: u64,
    pub is_deleted: bool,
    pub exists: bool,
}

pub impl MapEntryStorePacking of StorePacking<MapEntry, felt252> {
    fn pack(value: MapEntry) -> felt252 {
        // Pack into felt252:
        //   low u128 = value.0
        //   high u128 = value.1 (bits 0-31) | next (bits 32-95) | is_deleted (bit 96) | exists (bit
        //   97)
        let (val_low, val_high) = value.value;
        let val_high_u128: u128 = val_high.into();

        let deleted_bit: u128 = if value.is_deleted {
            TWO_POW_96
        } else {
            0
        };
        let exists_bit: u128 = if value.exists {
            TWO_POW_97
        } else {
            0
        };

        // shift next by 32
        let next_shifted = value.next.into() * TWO_POW_32;

        let high: u128 = val_high_u128 + next_shifted + deleted_bit + exists_bit;
        let u256_val: u256 = u256 { low: val_low, high };
        u256_val.try_into().unwrap()
    }

    fn unpack(value: felt252) -> MapEntry {
        let u256 { low, high } = value.into();
        let val_low = low;
        let val_high: u32 = (high & MASK_32).try_into().unwrap();
        let next: u64 = ((high / TWO_POW_32) & MASK_64).try_into().unwrap();
        let is_deleted: bool = (high & TWO_POW_96) != 0;
        let exists: bool = (high & TWO_POW_97) != 0;
        MapEntry { value: (val_low, val_high), next, is_deleted, exists }
    }
}

/// Helper struct to pack head, tail, length, and total_nodes
/// Layout in felt252 (224 bits total, fits in 251-bit felt):
///   - bits 0-63: head (u64)
///   - bits 64-95: length (u32)
///   - bits 96-127: total_nodes (u32)
///   - bits 128-191: tail (u64)
#[derive(Copy, Drop, PartialEq, Serde, Debug)]
pub struct HeadTailLength {
    pub head: u64,
    pub tail: u64,
    pub length: u32, // Count of non-deleted items
    pub total_nodes: u32 // Total nodes in linked list (including deleted)
}

pub impl HeadTailLengthStorePacking of StorePacking<HeadTailLength, felt252> {
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

// -----------------------------------------------------------------------------
// Storage Packing (MapEntryFelt)
// -----------------------------------------------------------------------------

#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct MapEntryFelt {
    pub next: felt252,
    pub value: (u128, u32), // Castable160 format
    pub is_deleted: bool,
    pub exists: bool,
}

pub impl MapEntryFeltStorePacking of StorePacking<MapEntryFelt, (felt252, felt252)> {
    fn pack(value: MapEntryFelt) -> (felt252, felt252) {
        let next = value.next;

        let temp_entry = MapEntry {
            value: value.value,
            next: 0, // Dummy next
            is_deleted: value.is_deleted,
            exists: value.exists,
        };

        let packed_val_flags = MapEntryStorePacking::pack(temp_entry);

        (next, packed_val_flags)
    }

    fn unpack(value: (felt252, felt252)) -> MapEntryFelt {
        let (next, packed_felt) = value;

        // We can use MapEntryStorePacking::unpack to get value and flags
        // It will return a MapEntry with next=0 (since we packed it with 0)
        let temp_entry = MapEntryStorePacking::unpack(packed_felt);

        MapEntryFelt {
            next,
            value: temp_entry.value,
            is_deleted: temp_entry.is_deleted,
            exists: temp_entry.exists,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        HeadTailLength, HeadTailLengthStorePacking, MapEntry, MapEntryFelt,
        MapEntryFeltStorePacking, MapEntryStorePacking,
    };

    #[test]
    fn test_map_entry_packing() {
        let entry = MapEntry {
            value: (123456789_u128, 987654321_u32), next: 100_u64, is_deleted: true, exists: true,
        };

        let packed = MapEntryStorePacking::pack(entry);
        let unpacked = MapEntryStorePacking::unpack(packed);

        assert_eq!(entry, unpacked);
    }

    #[test]
    fn test_map_entry_packing_max_values() {
        let entry = MapEntry {
            value: (
                340282366920938463463374607431768211455_u128, 4294967295_u32,
            ), // Max u128, Max u32
            next: 18446744073709551615_u64, // Max u64
            is_deleted: true,
            exists: true,
        };

        let packed = MapEntryStorePacking::pack(entry);
        let unpacked = MapEntryStorePacking::unpack(packed);

        assert_eq!(entry, unpacked);
    }

    #[test]
    fn test_map_entry_packing_zeros() {
        let entry = MapEntry {
            value: (0_u128, 0_u32), next: 0_u64, is_deleted: false, exists: false,
        };

        let packed = MapEntryStorePacking::pack(entry);
        let unpacked = MapEntryStorePacking::unpack(packed);

        assert_eq!(entry, unpacked);
    }

    #[test]
    fn test_map_entry_packing_flags_combinations() {
        // Case 1: is_deleted = false, exists = true
        let entry1 = MapEntry {
            value: (1_u128, 1_u32), next: 1_u64, is_deleted: false, exists: true,
        };
        let packed1 = MapEntryStorePacking::pack(entry1);
        let unpacked1 = MapEntryStorePacking::unpack(packed1);
        assert_eq!(entry1, unpacked1);

        // Case 2: is_deleted = true, exists = false
        // Semantically unusual, but struct-wise valid
        let entry2 = MapEntry {
            value: (1_u128, 1_u32), next: 1_u64, is_deleted: true, exists: false,
        };
        let packed2 = MapEntryStorePacking::pack(entry2);
        let unpacked2 = MapEntryStorePacking::unpack(packed2);
        assert_eq!(entry2, unpacked2);
    }

    #[test]
    fn test_head_tail_length_packing() {
        let htl = HeadTailLength { head: 10_u64, tail: 20_u64, length: 5_u32, total_nodes: 10_u32 };

        let packed = HeadTailLengthStorePacking::pack(htl);
        let unpacked = HeadTailLengthStorePacking::unpack(packed);

        assert_eq!(htl, unpacked);
    }

    #[test]
    fn test_head_tail_length_packing_max_values() {
        let htl = HeadTailLength {
            head: 18446744073709551615_u64, // Max u64
            tail: 18446744073709551615_u64, // Max u64
            length: 4294967295_u32, // Max u32
            total_nodes: 4294967295_u32 // Max u32
        };

        let packed = HeadTailLengthStorePacking::pack(htl);
        let unpacked = HeadTailLengthStorePacking::unpack(packed);

        assert_eq!(htl, unpacked);
    }

    #[test]
    fn test_map_entry_felt_packing() {
        let entry = MapEntryFelt {
            next: 123456789, value: (987654321_u128, 123_u32), is_deleted: true, exists: true,
        };

        let packed = MapEntryFeltStorePacking::pack(entry);
        let unpacked = MapEntryFeltStorePacking::unpack(packed);

        assert_eq!(entry, unpacked);

        let (next_packed, _) = packed;
        assert_eq!(next_packed, 123456789);
    }

    #[test]
    fn test_map_entry_felt_packing_max_values() {
        let entry = MapEntryFelt {
            next: 0x1234567890abcdef1234567890abcdef, // Big felt
            value: (340282366920938463463374607431768211455_u128, 4294967295_u32),
            is_deleted: true,
            exists: true,
        };

        let packed = MapEntryFeltStorePacking::pack(entry);
        let unpacked = MapEntryFeltStorePacking::unpack(packed);

        assert_eq!(entry, unpacked);
    }
}
