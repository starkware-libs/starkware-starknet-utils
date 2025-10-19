use core::keccak::compute_keccak_byte_array;
use core::pedersen::pedersen;
use openzeppelin::account::extensions::src9::OutsideExecution;
use starknet::ContractAddress;
use starknet::account::Call;
use starknet::class_hash::ClassHash;
use starknet::eth_address::EthAddress;
use starknet::eth_signature::public_key_point_to_eth_address;
use starknet::secp256_trait::{Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;

pub const MIN_TRANSACTION_VERSION: u256 = 3;
pub const QUERY_OFFSET: u256 = 0x100000000000000000000000000000000;

pub fn is_tx_version_valid() -> bool {
    let tx_info = starknet::get_tx_info().unbox();
    let tx_version = tx_info.version.into();
    if tx_version >= QUERY_OFFSET {
        tx_version >= QUERY_OFFSET + MIN_TRANSACTION_VERSION
    } else {
        tx_version >= MIN_TRANSACTION_VERSION
    }
}

// TODO: Consider changing the types to u128 where possible to save keccaks.
#[derive(Drop)]
pub struct TransactionMetadata {
    pub version: felt252,
    pub chain_id: felt252,
    pub execution_resources: Span<felt252>,
    pub tip: felt252,
    pub nonce: felt252,
}

#[derive(Drop)]
pub struct Transaction {
    pub calls: Span<Call>,
    pub metadata: @TransactionMetadata,
}

/// Adds a felt252 to the byte array (as 32 bytes).
fn push_felt(ref res: ByteArray, val: felt252) {
    let x: u256 = val.into();
    res.append_word(x.high.into(), 16);
    res.append_word(x.low.into(), 16);
}

/// Adds an array of felt252 to the byte array (as the hash of the concatenation of the felts).
fn push_felt_array(ref res: ByteArray, felts: Span<felt252>) {
    let mut byte_array: ByteArray = "";
    for x in felts {
        push_felt(ref byte_array, *x);
    }

    let msg_hash = compute_keccak_byte_array(@byte_array);
    res.append_word_rev(msg_hash.low.into(), 16);
    res.append_word_rev(msg_hash.high.into(), 16);
}

pub fn push_call(ref res: ByteArray, call: @Call) {
    let mut byte_array: ByteArray = "";
    // Push type hash.
    byte_array.append_word(0x7793b9bed3b87c6119fe923f0da4e85e, 16);
    byte_array.append_word(0x1f97a03272a446514622ee7bd62ad25f, 16);

    push_felt(ref byte_array, (*call.to).into());
    push_felt(ref byte_array, *call.selector);
    push_felt_array(ref byte_array, *call.calldata);

    let msg_hash = compute_keccak_byte_array(@byte_array);
    res.append_word_rev(msg_hash.low.into(), 16);
    res.append_word_rev(msg_hash.high.into(), 16);
}

/// Adds an array of Call to the byte array (as the hash of the concatenation of the Calls).
fn push_call_array(ref res: ByteArray, calls: Span<Call>) {
    let mut byte_array: ByteArray = "";
    for x in calls {
        push_call(ref byte_array, x);
    }

    let msg_hash = compute_keccak_byte_array(@byte_array);
    res.append_word_rev(msg_hash.low.into(), 16);
    res.append_word_rev(msg_hash.high.into(), 16);
}

pub fn push_metadata(ref res: ByteArray, metadata: @TransactionMetadata) {
    let mut byte_array: ByteArray = "";
    // Push type hash.
    byte_array.append_word(0x3e1a84b9a25a2ffe216927b61cc91a10, 16);
    byte_array.append_word(0x921dabd3305985281d0bb9707b0d8310, 16);

    push_felt(ref byte_array, *metadata.version);
    push_felt(ref byte_array, *metadata.chain_id);
    push_felt_array(ref byte_array, *metadata.execution_resources);
    push_felt(ref byte_array, *metadata.tip);
    push_felt(ref byte_array, *metadata.nonce);

    let msg_hash = compute_keccak_byte_array(@byte_array);
    res.append_word_rev(msg_hash.low.into(), 16);
    res.append_word_rev(msg_hash.high.into(), 16);
}

pub fn push_transaction(ref res: ByteArray, transaction: @Transaction) {
    let mut byte_array: ByteArray = "";

    // Push type hash.
    byte_array.append_word(0x1dc45489b8d4418703686ca441c4ea8e, 16);
    byte_array.append_word(0xad534ff02815a47b9059490edf3a0c68, 16);

    push_call_array(ref byte_array, *transaction.calls);
    push_metadata(ref byte_array, *transaction.metadata);

    let msg_hash = compute_keccak_byte_array(@byte_array);
    res.append_word_rev(msg_hash.low.into(), 16);
    res.append_word_rev(msg_hash.high.into(), 16);
}

pub fn push_outside_execution(ref res: ByteArray, outside_execution: @OutsideExecution) {
    let mut byte_array: ByteArray = "";

    // Push type hash
    byte_array.append_word(0x57fbef2abe14202f3651b3935a8feddd, 16);
    byte_array.append_word(0x357b8f83a862e046239d196ec76f281e, 16);

    push_call_array(ref byte_array, *outside_execution.calls);
    push_felt(ref byte_array, (*outside_execution.caller).into());
    push_felt(ref byte_array, *outside_execution.nonce);
    push_felt(ref byte_array, (*outside_execution.execute_after).into());
    push_felt(ref byte_array, (*outside_execution.execute_before).into());

    let msg_hash = compute_keccak_byte_array(@byte_array);
    res.append_word_rev(msg_hash.low.into(), 16);
    res.append_word_rev(msg_hash.high.into(), 16);
}

pub fn get_transaction_hash(transaction: @Transaction) -> u256 {
    let mut byte_array: ByteArray = "";
    byte_array.append_byte(0x19);
    byte_array.append_byte(0x1);

    // Domain separator.
    byte_array.append_word(0xd2beb680fe50f1d897e8368af738973f, 16);
    byte_array.append_word(0x5a6eb481a91b414478b0f52c29618f3f, 16);

    push_transaction(ref byte_array, transaction);

    let msg_hash = compute_keccak_byte_array(@byte_array);

    u256 {
        low: core::integer::u128_byte_reverse(msg_hash.high),
        high: core::integer::u128_byte_reverse(msg_hash.low),
    }
}

pub fn get_outside_execution_hash(outside_execution: @OutsideExecution) -> u256 {
    let mut byte_array: ByteArray = "";
    byte_array.append_byte(0x19);
    byte_array.append_byte(0x1);

    // TODO: use another domain separator.
    // Domain separator.
    byte_array.append_word(0xd2beb680fe50f1d897e8368af738973f, 16);
    byte_array.append_word(0x5a6eb481a91b414478b0f52c29618f3f, 16);

    push_outside_execution(ref byte_array, outside_execution);

    let msg_hash = compute_keccak_byte_array(@byte_array);

    u256 {
        low: core::integer::u128_byte_reverse(msg_hash.high),
        high: core::integer::u128_byte_reverse(msg_hash.low),
    }
}

/// Returns the eth address of the signer of the message, or None if the signature is malformed.
pub fn recover_eth_address(msg_hash: u256, signature: Span<felt252>) -> Option<EthAddress> {
    if signature.len() != 5 {
        return None;
    }
    let r_high: u128 = (*signature[0]).try_into()?;
    let r_low: u128 = (*signature[1]).try_into()?;
    let s_high: u128 = (*signature[2]).try_into()?;
    let s_low: u128 = (*signature[3]).try_into()?;
    let r = u256 { low: r_low, high: r_high };
    let s = u256 { low: s_low, high: s_high };
    let v = *signature[4];
    let signature = Signature { r, s, y_parity: v != 0 };

    let public_key_point = recover_public_key::<Secp256k1Point>(:msg_hash, :signature)?;
    Some(public_key_point_to_eth_address(:public_key_point))
}

/// Returns `true` if the signature is valid for the given message hash and eth address.
pub fn is_valid_signature(
    msg_hash: u256, signature: Span<felt252>, eth_address: EthAddress,
) -> bool {
    recover_eth_address(msg_hash, signature) == Some(eth_address)
}

/// Computes the Starknet eth account address from an Ethereum address and the StarknetEthAccount
/// class hash.
pub fn compute_starknet_eth_account_address(
    eth_address: EthAddress,
    class_hash: ClassHash,
    contract_address_salt: felt252,
    deployer_address: ContractAddress,
) -> ContractAddress {
    // Compute constructor calldata hash: pedersen([eth_address]).
    let constructor_calldata_hash = pedersen(pedersen(0, eth_address.into()), 1);

    // Compute the contract address.
    let hash = 0;
    let hash = pedersen(hash, 'STARKNET_CONTRACT_ADDRESS');
    let hash = pedersen(hash, contract_address_salt);
    let hash = pedersen(hash, deployer_address.into());
    let hash = pedersen(hash, class_hash.into());
    let hash = pedersen(hash, constructor_calldata_hash);
    let hash = pedersen(hash, 5);
    hash.try_into().expect('Invalid contract address')
}
