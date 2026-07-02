use core::integer::u256;
use core::keccak::compute_keccak_byte_array;
use openzeppelin::interfaces::src9::OutsideExecution;
use starknet::ResourcesBounds;
use starknet::account::Call;
use starknet::eth_address::EthAddress;
use starknet::eth_signature::public_key_point_to_eth_address;
use starknet::secp256_trait::{Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;

// keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
const EIP712_DOMAIN_TYPE_HASH: u256 =
    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f_u256;

// keccak256("Call(uint256 address,uint256 selector,uint256[] data)")
const CALL_TYPE_HASH: u256 =
    0x7793b9bed3b87c6119fe923f0da4e85e1f97a03272a446514622ee7bd62ad25f_u256;

// keccak256("OutsideExecution(Call[] calls,uint256 caller,uint256 nonce,uint256
// execute_after,uint256 execute_before)Call(...)")
const OUTSIDE_EXECUTION_TYPE_HASH: u256 =
    0x57fbef2abe14202f3651b3935a8feddd357b8f83a862e046239d196ec76f281e_u256;

// EIP-712 encodeType hash for TransactionMetadata
// keccak256("TransactionMetadata(uint256 version,uint256 chain_id,uint256[]
// execution_resources,uint256 tip,uint256 nonce)")
const TRANSACTION_METADATA_TYPE_HASH: u256 =
    0x3e1a84b9a25a2ffe216927b61cc91a10921dabd3305985281d0bb9707b0d8310_u256;

// EIP-712 encodeType hash for Transaction (includes referenced types sorted alphabetically)
// keccak256("Transaction(Call[] calls,TransactionMetadata
// metadata)Call(...)TransactionMetadata(...)")
const TRANSACTION_TYPE_HASH: u256 =
    0x1dc45489b8d4418703686ca441c4ea8ead534ff02815a47b9059490edf3a0c68_u256;

// EIP-712 encodeType hash for CallSet (a standalone authorization over just the calls).
// keccak256("CallSet(Call[] calls)Call(uint256 address,uint256 selector,uint256[] data)")
const CALL_SET_TYPE_HASH: u256 =
    0x00e0d1180501b61e32e630264491a7c9a611d81184f8a1cf1e41e1343bb396df_u256;

// keccak("2") (version of the EIP-712 domain).
const VERSION_HASH: u256 = 0xad7c5bef027816a800da1736444fb58a807ef4c9603b7848673f7e3a68eb14a5_u256;

// keccak256("\x19Ethereum Signed Message:\n41Sign to verify that you own this account.")
// msg_hash of the account ownership message. (Fixed per all chains).
const OWNERSHIP_TRANSFER_MSG_HASH: u256 =
    0x3ce976d55131cd0bdd49f20afbded052d8e907dc6034d95cdf117a8fd7752e3c_u256;

// Transaction version validation constants
pub const MIN_TRANSACTION_VERSION: u256 = 3;
pub const QUERY_OFFSET: u256 = 0x100000000000000000000000000000000;

// ================================
// Transaction types for __validate__
// ================================

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
    push_u256(ref res, val.into());
}

/// Adds a u256 to the byte array `val.high` and then `val.low`.
fn push_u256(ref res: ByteArray, val: u256) {
    res.append_word(val.high.into(), 16);
    res.append_word(val.low.into(), 16);
}

/// Adds a span of felt252 to the byte array (as the hash of the concatenation of the felts).
fn push_felt_array(ref res: ByteArray, felts: Span<felt252>) {
    let mut byte_array: ByteArray = "";
    for x in felts {
        push_felt(ref byte_array, *x);
    }
    push_keccak(ref res, @byte_array);
}

pub fn push_keccak(ref res: ByteArray, byte_array: @ByteArray) {
    push_u256(ref res, reverse_u256(compute_keccak_byte_array(byte_array)));
}

pub fn push_call(ref res: ByteArray, call: @Call) {
    let mut byte_array: ByteArray = "";
    let Call { to, selector, calldata } = *call;
    // Push type hash.
    push_u256(ref byte_array, CALL_TYPE_HASH);

    push_felt(ref byte_array, to.into());
    push_felt(ref byte_array, selector);
    push_felt_array(ref byte_array, calldata);
    push_keccak(ref res, @byte_array);
}

/// Adds an array of Call to the byte array (as the hash of the concatenation of the Calls).
fn push_call_array(ref res: ByteArray, calls: Span<Call>) {
    let mut byte_array: ByteArray = "";
    for x in calls {
        push_call(ref byte_array, x);
    }
    push_keccak(ref res, @byte_array);
}

fn outside_execution_hash_struct(outside_execution: @OutsideExecution) -> u256 {
    let mut byte_array: ByteArray = "";

    push_u256(ref byte_array, OUTSIDE_EXECUTION_TYPE_HASH);
    let OutsideExecution {
        caller, nonce, execute_after, execute_before, calls,
    } = *outside_execution;

    push_call_array(ref byte_array, calls);
    push_felt(ref byte_array, caller.into());
    push_felt(ref byte_array, nonce);
    push_felt(ref byte_array, execute_after.into());
    push_felt(ref byte_array, execute_before.into());
    reverse_u256(compute_keccak_byte_array(@byte_array))
}

// ================================
// Transaction hashing functions
// ================================

pub fn push_metadata(ref res: ByteArray, metadata: @TransactionMetadata) {
    let mut byte_array: ByteArray = "";
    push_u256(ref byte_array, TRANSACTION_METADATA_TYPE_HASH);

    push_felt(ref byte_array, *metadata.version);
    push_felt(ref byte_array, *metadata.chain_id);
    push_felt_array(ref byte_array, *metadata.execution_resources);
    push_felt(ref byte_array, *metadata.tip);
    push_felt(ref byte_array, *metadata.nonce);

    push_keccak(ref res, @byte_array);
}

fn transaction_hash_struct(transaction: @Transaction) -> u256 {
    let mut byte_array: ByteArray = "";
    push_u256(ref byte_array, TRANSACTION_TYPE_HASH);

    push_call_array(ref byte_array, *transaction.calls);
    push_metadata(ref byte_array, *transaction.metadata);

    reverse_u256(compute_keccak_byte_array(@byte_array))
}

pub fn get_transaction_hash(transaction: @Transaction, chain_id: felt252) -> u256 {
    eip712_message_hash(:chain_id, struct_hash: transaction_hash_struct(transaction))
}

// ================================
// CallSet hashing
// ================================

/// EIP-712 `hashStruct` of a `CallSet { calls }`: the type hash followed by the hash of the
/// call array.
fn call_set_hash_struct(calls: Span<Call>) -> u256 {
    let mut byte_array: ByteArray = "";
    push_u256(ref byte_array, CALL_SET_TYPE_HASH);
    push_call_array(ref byte_array, calls);
    reverse_u256(compute_keccak_byte_array(@byte_array))
}

/// EIP-712 message hash of a `CallSet`.
pub fn get_call_set_hash(calls: Span<Call>, chain_id: felt252) -> u256 {
    eip712_message_hash(:chain_id, struct_hash: call_set_hash_struct(calls))
}

pub fn push_domain_separator(ref res: ByteArray, chain_id: felt252) {
    let mut byte_array: ByteArray = "";

    push_u256(ref byte_array, EIP712_DOMAIN_TYPE_HASH);
    // As name field we push the keccak of the Starknet chain id for execution domain separation.
    push_u256(ref byte_array, sn_chain_id_keccak());
    push_u256(ref byte_array, VERSION_HASH);

    // EIP-712 domain separator chain id (source chain id).
    push_u256(ref byte_array, chain_id.into());

    // As verifyingContract field we push the lower 128 bits of the account contract address.
    // This provides separation of the executing contract domain.
    // We can't use the full contract address because
    // it would be too long for the EIP-712 domain separator.
    // So we use the only the lower 128 bits of the contract address.
    push_u256(ref byte_array, contract_address_low());

    push_keccak(ref res, @byte_array);
}

/// EIP-712 message hash: `keccak(0x19 0x01 || domainSeparator(chain_id) || struct_hash)`.
/// The shared envelope for all typed messages (`Transaction`, `OutsideExecution`, `CallSet`).
fn eip712_message_hash(chain_id: felt252, struct_hash: u256) -> u256 {
    let mut byte_array: ByteArray = "";

    // EIP-191 header.
    byte_array.append_byte(0x19);
    byte_array.append_byte(0x1);

    push_domain_separator(ref byte_array, chain_id);
    push_u256(ref byte_array, struct_hash);

    reverse_u256(compute_keccak_byte_array(@byte_array))
}

fn contract_address_low() -> u256 {
    let address_felt: felt252 = starknet::get_contract_address().into();
    let address_u256: u256 = address_felt.into();
    u256 { low: address_u256.low, high: 0_u128 }
}

pub fn get_outside_execution_hash(outside_execution: @OutsideExecution, chain_id: felt252) -> u256 {
    eip712_message_hash(:chain_id, struct_hash: outside_execution_hash_struct(outside_execution))
}

/// Returns the eth address of the signer of the message, or None if the signature is malformed.
pub fn recover_eth_address(msg_hash: u256, signature: Signature) -> Option<EthAddress> {
    let public_key_point = recover_public_key::<Secp256k1Point>(:msg_hash, :signature)?;
    Some(public_key_point_to_eth_address(:public_key_point))
}

pub fn extract_signature(signature: Span<felt252>) -> (Signature, felt252) {
    assert(signature.len() == 6, 'INVALID_SIGNATURE_LENGTH');
    let r_high: u128 = (*signature[0]).try_into().unwrap();
    let r_low: u128 = (*signature[1]).try_into().unwrap();
    let s_high: u128 = (*signature[2]).try_into().unwrap();
    let s_low: u128 = (*signature[3]).try_into().unwrap();
    let r = u256 { low: r_low, high: r_high };
    let s = u256 { low: s_low, high: s_high };
    let v: u128 = (*signature[4]).try_into().unwrap();
    let chain_id = *signature[5];
    (Signature { r, s, y_parity: v % 2 == 0 }, chain_id)
}

/// Returns `true` if the signature is valid for the given message hash and eth address.
pub fn is_valid_eth_signature(
    msg_hash: u256, signature: Signature, eth_address: EthAddress,
) -> bool {
    recover_eth_address(:msg_hash, :signature) == Some(eth_address)
}

/// Extract signature - accepts 5 or 6 felts.
/// 5 felts: [r_high, r_low, s_high, s_low, v]
/// 6 felts: [r_high, r_low, s_high, s_low, v, chain_id] - chain_id ignored
pub fn extract_signature_flexible(signature: Span<felt252>) -> Signature {
    assert(signature.len() == 5 || signature.len() == 6, 'INVALID_SIGNATURE_LENGTH');
    let r_high: u128 = (*signature[0]).try_into().unwrap();
    let r_low: u128 = (*signature[1]).try_into().unwrap();
    let s_high: u128 = (*signature[2]).try_into().unwrap();
    let s_low: u128 = (*signature[3]).try_into().unwrap();
    let v: u128 = (*signature[4]).try_into().unwrap();
    Signature {
        r: u256 { low: r_low, high: r_high },
        s: u256 { low: s_low, high: s_high },
        y_parity: v % 2 == 0,
    }
}

/// Converts resource bounds to a span of felt252 for EIP-712 hashing.
pub fn resource_bounds_as_felts(resource_bounds: Span<ResourcesBounds>) -> Span<felt252> {
    let mut rb_felts: Array<felt252> = array![];
    for res in resource_bounds {
        rb_felts.append(*res.resource);
        rb_felts.append((*res.max_amount).into());
        rb_felts.append((*res.max_price_per_unit).into());
    }
    rb_felts.span()
}

/// Validates that the transaction version is supported (v3 or query v3).
pub fn is_tx_version_valid() -> bool {
    let tx_info = starknet::get_tx_info().unbox();
    let tx_version: u256 = tx_info.version.into();
    if tx_version >= QUERY_OFFSET {
        tx_version >= QUERY_OFFSET + MIN_TRANSACTION_VERSION
    } else {
        tx_version >= MIN_TRANSACTION_VERSION
    }
}

/// Asserts eth address ownership signature is valid.
pub fn assert_valid_owner(eth_address: EthAddress, signature: Signature) {
    let msg_hash = OWNERSHIP_TRANSFER_MSG_HASH;
    assert(
        is_valid_eth_signature(:msg_hash, :signature, :eth_address), 'INVALID_OWNERSHIP_SIGNATURE',
    );
}

fn sn_chain_id_keccak() -> u256 {
    let cid_str = felt_to_byte_array(starknet::get_tx_info().unbox().chain_id);
    reverse_u256(compute_keccak_byte_array(@cid_str))
}

pub fn reverse_u256(u256_value: u256) -> u256 {
    u256 {
        low: core::integer::u128_byte_reverse(u256_value.high),
        high: core::integer::u128_byte_reverse(u256_value.low),
    }
}

fn felt_to_byte_array(felt: felt252) -> ByteArray {
    let mut ba: ByteArray = "";
    let mut felt_num: u256 = felt.into();
    while (felt_num != 0) {
        let byte: u8 = (felt_num % 256_u256).try_into().unwrap();
        ba.append_byte(byte);
        felt_num /= 256_u256;
    }
    ba.rev()
}
