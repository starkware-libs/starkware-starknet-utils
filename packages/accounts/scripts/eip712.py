"""
Shared EIP-712 hashing logic for eth_712_account scripts.

Mirrors the hashing functions in eth_712_utils.cairo. Both generate_test_signatures.py
and send_tx.py import from this module to avoid duplicating the hashing core.

Call dict format (canonical, matching Cairo's Call struct):
    {"to": int, "selector": int, "calldata": list[int]}
"""

from eth_account import Account
from web3 import Web3

# ============================================================================
# Bit masks
# ============================================================================

MASK_128 = (1 << 128) - 1
MASK_250 = (1 << 250) - 1

# ============================================================================
# EIP-712 type hashes (must match eth_712_utils.cairo)
# ============================================================================

EIP712_DOMAIN_TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f
CALL_TYPE_HASH = 0x7793b9bed3b87c6119fe923f0da4e85e1f97a03272a446514622ee7bd62ad25f
OUTSIDE_EXECUTION_TYPE_HASH = 0x57fbef2abe14202f3651b3935a8feddd357b8f83a862e046239d196ec76f281e
TRANSACTION_METADATA_TYPE_HASH = 0x3e1a84b9a25a2ffe216927b61cc91a10921dabd3305985281d0bb9707b0d8310
TRANSACTION_TYPE_HASH = 0x1dc45489b8d4418703686ca441c4ea8ead534ff02815a47b9059490edf3a0c68
# keccak256("CallSet(Call[] calls)Call(uint256 address,uint256 selector,uint256[] data)")
CALL_SET_TYPE_HASH = 0x00e0d1180501b61e32e630264491a7c9a611d81184f8a1cf1e41e1343bb396df
VERSION_HASH = 0xad7c5bef027816a800da1736444fb58a807ef4c9603b7848673f7e3a68eb14a5

# ============================================================================
# Resource identifier constants (matching Cairo felt252 short strings)
# ============================================================================

L1_GAS_ID = 0x4c315f474153       # 'L1_GAS'
L2_GAS_ID = 0x4c325f474153       # 'L2_GAS'
L1_DATA_ID = 0x4c315f44415441    # 'L1_DATA'

# ============================================================================
# SNIP-9 constants
# ============================================================================

ANY_CALLER = int.from_bytes(b"ANY_CALLER", "big")

# ============================================================================
# Keccak primitives
# ============================================================================


def keccak256(data: bytes) -> bytes:
    """Compute keccak256 hash."""
    return Web3.keccak(data)


def to_bytes32(val: int) -> bytes:
    """Convert int to 32-byte big-endian representation."""
    return val.to_bytes(32, "big")


def keccak_ints(*values: int) -> int:
    """Compute keccak256 of concatenated 32-byte representations, returning int."""
    data = b"".join(to_bytes32(v) for v in values)
    return int.from_bytes(keccak256(data), "big")


def hash_felt_array(felts: list[int]) -> int:
    """Hash an array of felts (keccak of concatenated 32-byte representations)."""
    if not felts:
        return int.from_bytes(keccak256(b""), "big")
    data = b"".join(to_bytes32(f) for f in felts)
    return int.from_bytes(keccak256(data), "big")


def selector(name: str) -> int:
    """Compute Starknet selector (sn_keccak): keccak256 masked to 250 bits."""
    h = keccak256(name.encode("utf-8"))
    return int.from_bytes(h, "big") & MASK_250


# ============================================================================
# Domain separator
# ============================================================================


def domain_separator(sn_chain_name: str, contract_address: int, evm_chain_id: int) -> int:
    """
    Compute the EIP-712 domain separator matching push_domain_separator in eth_712_utils.cairo.

    Fields:
    - name: keccak256(sn_chain_name) -- e.g. keccak("SN_MAIN")
    - version: VERSION_HASH (keccak("2"))
    - chainId: evm_chain_id
    - verifyingContract: lower 128 bits of contract_address
    """
    name_hash = int.from_bytes(keccak256(sn_chain_name.encode("utf-8")), "big")
    verifying_contract = contract_address & MASK_128
    return keccak_ints(
        EIP712_DOMAIN_TYPE_HASH, name_hash, VERSION_HASH, evm_chain_id, verifying_contract,
    )


# ============================================================================
# Call hashing
# ============================================================================


def hash_call(call: dict) -> int:
    """
    Hash a Call struct matching push_call in eth_712_utils.cairo.

    call = {"to": int, "selector": int, "calldata": list[int]}
    """
    calldata_hash = hash_felt_array(call["calldata"])
    return keccak_ints(CALL_TYPE_HASH, call["to"], call["selector"], calldata_hash)


def hash_call_array(calls: list[dict]) -> int:
    """Hash an array of Calls (keccak of concatenated call hashes)."""
    if not calls:
        return int.from_bytes(keccak256(b""), "big")
    data = b"".join(to_bytes32(hash_call(c)) for c in calls)
    return int.from_bytes(keccak256(data), "big")


# ============================================================================
# OutsideExecution hashing
# ============================================================================


def hash_outside_execution(oe: dict) -> int:
    """
    Hash OutsideExecution struct matching outside_execution_hash_struct in eth_712_utils.cairo.

    Field order: type_hash, hash(calls), caller, nonce, execute_after, execute_before.
    """
    calls_hash = hash_call_array(oe.get("calls", []))
    return keccak_ints(
        OUTSIDE_EXECUTION_TYPE_HASH,
        calls_hash,
        oe["caller"],
        oe["nonce"],
        oe["execute_after"],
        oe["execute_before"],
    )


def outside_execution_msg_hash(
    oe: dict, sn_chain_name: str, contract_address: int, evm_chain_id: int,
) -> int:
    """Compute the full EIP-712 message hash for an OutsideExecution."""
    ds = domain_separator(sn_chain_name, contract_address, evm_chain_id)
    sh = hash_outside_execution(oe)
    data = b"\x19\x01" + to_bytes32(ds) + to_bytes32(sh)
    return int.from_bytes(keccak256(data), "big")


# ============================================================================
# Transaction hashing (__validate__)
# ============================================================================


def hash_transaction_metadata(metadata: dict) -> int:
    """Hash TransactionMetadata struct matching push_metadata in eth_712_utils.cairo."""
    exec_hash = hash_felt_array(metadata["execution_resources"])
    return keccak_ints(
        TRANSACTION_METADATA_TYPE_HASH,
        metadata["version"],
        metadata["chain_id"],
        exec_hash,
        metadata["tip"],
        metadata["nonce"],
    )


def hash_transaction(calls: list[dict], metadata: dict) -> int:
    """Hash Transaction struct matching transaction_hash_struct in eth_712_utils.cairo."""
    calls_hash = hash_call_array(calls)
    metadata_hash = hash_transaction_metadata(metadata)
    return keccak_ints(TRANSACTION_TYPE_HASH, calls_hash, metadata_hash)


def transaction_msg_hash(
    calls: list[dict],
    metadata: dict,
    sn_chain_name: str,
    contract_address: int,
    evm_chain_id: int,
) -> int:
    """Compute the full EIP-712 message hash for a Transaction (__validate__)."""
    ds = domain_separator(sn_chain_name, contract_address, evm_chain_id)
    sh = hash_transaction(calls, metadata)
    data = b"\x19\x01" + to_bytes32(ds) + to_bytes32(sh)
    return int.from_bytes(keccak256(data), "big")


# ============================================================================
# CallSet hashing
# ============================================================================


def hash_call_set(calls: list[dict]) -> int:
    """Hash CallSet struct matching call_set_hash_struct in eth_712_utils.cairo."""
    return keccak_ints(CALL_SET_TYPE_HASH, hash_call_array(calls))


def call_set_msg_hash(
    calls: list[dict], sn_chain_name: str, contract_address: int, evm_chain_id: int,
) -> int:
    """Compute the full EIP-712 message hash for a CallSet."""
    ds = domain_separator(sn_chain_name, contract_address, evm_chain_id)
    sh = hash_call_set(calls)
    data = b"\x19\x01" + to_bytes32(ds) + to_bytes32(sh)
    return int.from_bytes(keccak256(data), "big")


# ============================================================================
# Signature utilities
# ============================================================================


def sign_and_split(msg_hash: int, private_key, evm_chain_id: int) -> dict:
    """
    Sign a pre-computed hash and split into 6-felt dict.

    Returns: {"r_high", "r_low", "s_high", "s_low", "v", "chain_id"}
    """
    signed = Account.unsafe_sign_hash(msg_hash.to_bytes(32, "big"), private_key)
    return {
        "r_high": signed.r >> 128,
        "r_low": signed.r & MASK_128,
        "s_high": signed.s >> 128,
        "s_low": signed.s & MASK_128,
        "v": signed.v,
        "chain_id": evm_chain_id,
    }


def resource_bounds_to_felts(
    l1_gas_amount: int, l1_gas_price: int,
    l2_gas_amount: int, l2_gas_price: int,
    l1_data_amount: int, l1_data_price: int,
) -> list[int]:
    """Convert resource bounds to 9-felt array matching resource_bounds_as_felts in Cairo."""
    return [
        L1_GAS_ID, l1_gas_amount, l1_gas_price,
        L2_GAS_ID, l2_gas_amount, l2_gas_price,
        L1_DATA_ID, l1_data_amount, l1_data_price,
    ]
