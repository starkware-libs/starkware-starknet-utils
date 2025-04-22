use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::{SNIP12Metadata, StarknetDomain, StructHash};
use starknet::get_tx_info;
use starkware_utils::types::{HashType, PublicKey};

/// Trait for calculating the hash of a message given the `public_key`
pub trait OffchainMessageHash<T> {
    fn get_message_hash(self: @T, public_key: PublicKey) -> HashType;
}

pub const REVISION: felt252 = 1;
pub const STARKNET_MESSAGE: felt252 = 'StarkNet Message';

pub(crate) impl OffchainMessageHashImpl<
    T, +StructHash<T>, impl metadata: SNIP12Metadata,
> of OffchainMessageHash<T> {
    fn get_message_hash(self: @T, public_key: PublicKey) -> HashType {
        let domain = StarknetDomain {
            name: metadata::name(),
            version: metadata::version(),
            chain_id: get_tx_info().unbox().chain_id,
            revision: REVISION,
        };
        PoseidonTrait::new()
            .update_with(STARKNET_MESSAGE)
            .update_with(domain.hash_struct())
            .update_with(public_key)
            .update_with(self.hash_struct())
            .finalize()
    }
}
