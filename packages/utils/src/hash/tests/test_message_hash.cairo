use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::{PoseidonTrait, poseidon_hash_span};
use openzeppelin::utils::cryptography::snip12::{
    SNIP12Metadata, STARKNET_DOMAIN_TYPE_HASH, StarknetDomain, StructHash,
};
use openzeppelin_testing::constants::{PUBKEY, RECIPIENT};
use snforge_std::{start_cheat_chain_id, test_address};
use starknet::ContractAddress;
use starkware_utils::hash::message_hash::{OffchainMessageHash, REVISION, STARKNET_MESSAGE};
use starkware_utils::signature::stark::HashType;

const MESSAGE_TYPE_HASH: HashType =
    0x120ae1bdaf7c1e48349da94bb8dad27351ca115d6605ce345aee02d68d99ec1;

const DAPP_NAME: felt252 = 'DAPP_NAME';
const VERSION: felt252 = 'v1';
const CHAIN_ID: felt252 = 'TEST';

#[derive(Copy, Drop, Hash)]
struct Message {
    recipient: ContractAddress,
    amount: u256,
    nonce: felt252,
    expiry: u64,
}

impl StructHashImpl of StructHash<Message> {
    fn hash_struct(self: @Message) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(MESSAGE_TYPE_HASH).update_with(*self).finalize()
    }
}

impl SNIP12MetadataImpl of SNIP12Metadata {
    fn name() -> felt252 {
        DAPP_NAME
    }
    fn version() -> felt252 {
        VERSION
    }
}

#[test]
fn test_starknet_domain_type_hash() {
    let expected = selector!(
        "\"StarknetDomain\"(\"name\":\"shortstring\",\"version\":\"shortstring\",\"chainId\":\"shortstring\",\"revision\":\"shortstring\")",
    );
    assert_eq!(STARKNET_DOMAIN_TYPE_HASH, expected);
}

#[test]
fn test_StructHashStarknetDomainImpl() {
    let domain = StarknetDomain {
        name: DAPP_NAME, version: VERSION, chain_id: CHAIN_ID, revision: REVISION,
    };

    let expected = poseidon_hash_span(
        array![
            STARKNET_DOMAIN_TYPE_HASH,
            domain.name,
            domain.version,
            domain.chain_id,
            domain.revision,
        ]
            .span(),
    );
    assert_eq!(domain.hash_struct(), expected);
}

#[test]
fn test_OffchainMessageHashImpl_Felt() {
    let message = Message { recipient: RECIPIENT, amount: 100, nonce: 1, expiry: 1000 };
    let domain = StarknetDomain {
        name: DAPP_NAME, version: VERSION, chain_id: CHAIN_ID, revision: REVISION,
    };

    let contract_address = test_address();
    start_cheat_chain_id(contract_address, CHAIN_ID);

    let expected = poseidon_hash_span(
        array![STARKNET_MESSAGE, domain.hash_struct(), PUBKEY, message.hash_struct()].span(),
    );
    assert_eq!(message.get_message_hash(PUBKEY), expected);
}
