#!/usr/bin/env python3
"""
Generate EIP-712 signatures for the starkware_accounts test cases.

This script generates signatures that match the hashing logic in src/eth_712_utils.cairo
and writes them directly into ../src/test_utils.cairo between marker comments:

    // GENERATED-SIGNATURES-START (by scripts/generate_test_signatures.py -- do not edit manually)
    ... generated functions ...
    // GENERATED-SIGNATURES-END

The script is idempotent: running it again on an already-correct file produces no changes.
If the signing logic or test parameters change, re-running the script updates test_utils.cairo.

Setup:
    cd packages/accounts/scripts
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt

Usage:
    python generate_test_signatures.py

Dependencies: eth-account, web3 (see requirements.txt)
"""

import pathlib
import re

from eip712 import (
    ANY_CALLER,
    MASK_128,
    call_set_msg_hash,
    outside_execution_msg_hash,
    resource_bounds_to_felts,
    selector,
    sign_and_split,
    transaction_msg_hash,
)

# ============================================================================
# Test constants (must match test_utils.cairo)
# ============================================================================

PRIVATE_KEY = "0xa6d86467b6ec9e161649b27edfd8519e75a2e1cf5f4c309c628706e6999780e8"

EXPECTED_CONTRACT_ADDRESS = 0x07120acc07120acc07120acc07120acc
ERC20_MOCK_ADDRESS = 0x0e2c200e2c200e2c200e2c200e2c2000

# Re-run this script after recompiling if RegisterInterfacesEIC changes.
FIXED_UPGRADE_TARGET_CLASS_HASH = 0x116b817c8fd4d03b340edb899d0c074b1c36ba9b643af1422bd5ed6ee0d555d

EXECUTE_AFTER = 1000
EXECUTE_BEFORE = 3000
TEST_NONCE = 1
ETH_CHAIN_ID = 1
SN_CHAIN_ID = "SN_MAIN"

TEST_SPENDER = 0x1234
TEST_RECIPIENT = 0x5678
SPECIFIC_CALLER = 0xCAFE
WRONG_CONTRACT_ADDRESS = 0xDEAD

# ============================================================================
# Signing helpers
# ============================================================================


def sign_outside_execution(
    oe: dict,
    contract_address: int,
    evm_chain_id: int = ETH_CHAIN_ID,
    sn_chain_name: str = SN_CHAIN_ID,
) -> dict:
    """Sign an OutsideExecution and return 6-felt signature dict."""
    msg_hash = outside_execution_msg_hash(oe, sn_chain_name, contract_address, evm_chain_id)
    return sign_and_split(msg_hash, PRIVATE_KEY, evm_chain_id)


def sign_transaction(
    calls: list[dict],
    metadata: dict,
    contract_address: int,
    evm_chain_id: int = ETH_CHAIN_ID,
    sn_chain_name: str = SN_CHAIN_ID,
) -> dict:
    """Sign a Transaction (__validate__) and return 6-felt signature dict."""
    msg_hash = transaction_msg_hash(calls, metadata, sn_chain_name, contract_address, evm_chain_id)
    return sign_and_split(msg_hash, PRIVATE_KEY, evm_chain_id)


def sign_call_set(
    calls: list[dict],
    contract_address: int,
    additional_data: list[int] = None,
    evm_chain_id: int = ETH_CHAIN_ID,
    sn_chain_name: str = SN_CHAIN_ID,
) -> dict:
    """Sign a CallSet and return 6-felt signature dict."""
    msg_hash = call_set_msg_hash(
        calls, additional_data or [], sn_chain_name, contract_address, evm_chain_id,
    )
    return sign_and_split(msg_hash, PRIVATE_KEY, evm_chain_id)


# ============================================================================
# __validate__ metadata
# ============================================================================

VALIDATE_TX_VERSION = 3
VALIDATE_NONCE = 0
VALIDATE_TIP = 0
VALIDATE_SN_CHAIN_ID = int.from_bytes(SN_CHAIN_ID.encode("ascii"), "big")
VALIDATE_RESOURCE_BOUNDS = resource_bounds_to_felts(
    l1_gas_amount=100, l1_gas_price=1000,
    l2_gas_amount=200, l2_gas_price=2000,
    l1_data_amount=300, l1_data_price=3000,
)


def build_validate_metadata(nonce: int = VALIDATE_NONCE) -> dict:
    """Build TransactionMetadata dict for __validate__ tests."""
    return {
        "version": VALIDATE_TX_VERSION,
        "chain_id": VALIDATE_SN_CHAIN_ID,
        "execution_resources": VALIDATE_RESOURCE_BOUNDS,
        "tip": VALIDATE_TIP,
        "nonce": nonce,
    }


# ============================================================================
# EFO test case generators
# ============================================================================


def _build_oe(calls: list[dict], nonce: int, caller: int = ANY_CALLER) -> dict:
    """Build an OutsideExecution dict with default timestamps."""
    return {
        "caller": caller,
        "nonce": nonce,
        "execute_after": EXECUTE_AFTER,
        "execute_before": EXECUTE_BEFORE,
        "calls": calls,
    }


def _approve_call(token: int, spender: int, amount: int) -> dict:
    return {
        "to": token,
        "selector": selector("approve"),
        "calldata": [spender, amount & MASK_128, amount >> 128],
    }


def _transfer_call(token: int, recipient: int, amount: int) -> dict:
    return {
        "to": token,
        "selector": selector("transfer"),
        "calldata": [recipient, amount & MASK_128, amount >> 128],
    }


def _upgrade_call(contract_address: int, class_hash: int) -> dict:
    return {
        "to": contract_address,
        "selector": selector("upgrade"),
        "calldata": [class_hash, 1],  # 1 = Option::None in Cairo
    }


def generate_basic_outside_execution(
    contract_address: int,
    nonce: int = TEST_NONCE,
    evm_chain_id: int = ETH_CHAIN_ID,
    sn_chain_name: str = SN_CHAIN_ID,
) -> dict:
    """EFO signature for basic OutsideExecution with empty calls."""
    oe = _build_oe([], nonce)
    return sign_outside_execution(oe, contract_address, evm_chain_id, sn_chain_name)


def generate_wrong_sn_chain_name(contract_address: int) -> dict:
    """EFO signature with SN_SEPOLIA (will fail against SN_MAIN domain)."""
    return generate_basic_outside_execution(contract_address, sn_chain_name="SN_SEPOLIA")


def generate_wrong_contract_address() -> dict:
    """EFO signature with a wrong contract address."""
    return generate_basic_outside_execution(WRONG_CONTRACT_ADDRESS)


def generate_single_call_approve_test(
    contract_address: int, token: int, spender: int, amount: int, nonce: int,
) -> dict:
    """EFO signature for single approve call."""
    oe = _build_oe([_approve_call(token, spender, amount)], nonce)
    return sign_outside_execution(oe, contract_address)


def generate_multi_call_test(
    contract_address: int, token: int, spender: int, recipient: int,
    approve_amount: int, transfer_amount: int, nonce: int,
) -> dict:
    """EFO signature for approve + transfer."""
    calls = [
        _approve_call(token, spender, approve_amount),
        _transfer_call(token, recipient, transfer_amount),
    ]
    oe = _build_oe(calls, nonce)
    return sign_outside_execution(oe, contract_address)


def generate_atomicity_test(
    contract_address: int, token: int, spender: int, recipient: int,
    approve_amount: int, transfer_amount: int, nonce: int,
) -> dict:
    """EFO signature for atomicity test (approve succeeds, transfer fails)."""
    calls = [
        _approve_call(token, spender, approve_amount),
        _transfer_call(token, recipient, transfer_amount),
    ]
    oe = _build_oe(calls, nonce)
    return sign_outside_execution(oe, contract_address)


def generate_specific_caller_test(contract_address: int, caller: int, nonce: int) -> dict:
    """EFO signature with a specific caller (not ANY_CALLER), empty calls."""
    oe = _build_oe([], nonce, caller=caller)
    return sign_outside_execution(oe, contract_address)


def generate_efo_upgrade_test(
    contract_address: int, class_hash: int, nonce: int,
) -> dict:
    """EFO signature for upgrade(class_hash, Option::None)."""
    oe = _build_oe([_upgrade_call(contract_address, class_hash)], nonce)
    return sign_outside_execution(oe, contract_address)


# ============================================================================
# __validate__ test case generators
# ============================================================================


def generate_validate_empty_calls(contract_address: int, nonce: int = VALIDATE_NONCE) -> dict:
    """__validate__ signature with empty calls."""
    return sign_transaction([], build_validate_metadata(nonce), contract_address)


def generate_call_set_empty_calls(contract_address: int) -> dict:
    """CallSet signature with empty calls.

    The CallSet message has no tx metadata — it depends only on the domain and the calls.
    """
    return sign_call_set([], contract_address)


def generate_call_set_with_approve(
    contract_address: int, token: int, spender: int, amount: int,
) -> dict:
    """CallSet signature over a single approve call."""
    call = _approve_call(token, spender, amount)
    return sign_call_set([call], contract_address)


def generate_call_set_with_additional_data(
    contract_address: int, token: int, spender: int, amount: int, additional_data: list[int],
) -> dict:
    """CallSet signature over a single approve call plus non-empty additional_data."""
    call = _approve_call(token, spender, amount)
    return sign_call_set([call], contract_address, additional_data=additional_data)


def generate_validate_with_approve(
    contract_address: int, token: int, spender: int, amount: int, nonce: int = VALIDATE_NONCE,
) -> dict:
    """__validate__ signature with a single approve call."""
    call = _approve_call(token, spender, amount)
    return sign_transaction([call], build_validate_metadata(nonce), contract_address)


def generate_validate_wrong_chain(contract_address: int, nonce: int = VALIDATE_NONCE) -> dict:
    """__validate__ signature with SN_SEPOLIA (will fail against SN_MAIN domain)."""
    return sign_transaction(
        [], build_validate_metadata(nonce), contract_address, sn_chain_name="SN_SEPOLIA",
    )


def generate_validate_upgrade(contract_address: int, class_hash: int, nonce: int) -> dict:
    """__validate__ signature for upgrade(class_hash, Option::None)."""
    call = _upgrade_call(contract_address, class_hash)
    return sign_transaction([call], build_validate_metadata(nonce), contract_address)


# ============================================================================
# Cairo code generation
# ============================================================================

MARKER_START = "// GENERATED-SIGNATURES-START (by scripts/generate_test_signatures.py -- do not edit manually)"
MARKER_END = "// GENERATED-SIGNATURES-END"


def format_signature_cairo(sig: dict, fn_name: str, doc: str) -> str:
    """Format a single signature as a Cairo function (scarb fmt compatible)."""
    r_high = f"0x{sig['r_high']:032x}"
    r_low = f"0x{sig['r_low']:032x}"
    s_high = f"0x{sig['s_high']:032x}"
    s_low = f"0x{sig['s_low']:032x}"
    v = str(sig["v"])
    chain_id = str(sig["chain_id"])
    return (
        f"/// {doc}\n"
        f"pub fn {fn_name}() -> Array<felt252> {{\n"
        f"    array![\n"
        f"        {r_high}, {r_low},\n"
        f"        {s_high}, {s_low}, {v}, {chain_id},\n"
        f"    ]\n"
        f"}}"
    )


def generate_all_signatures() -> list[str]:
    """Generate all signature functions as Cairo code strings."""
    addr = EXPECTED_CONTRACT_ADDRESS
    token = ERC20_MOCK_ADDRESS
    spender = TEST_SPENDER
    recipient = TEST_RECIPIENT

    NONCE_SINGLE_CALL = 100
    NONCE_MULTI_CALL = 101
    NONCE_ATOMICITY = 102
    NONCE_SPECIFIC_CALLER = 103
    NONCE_EFO_UPGRADE = 200
    VALIDATE_NONCE_WITH_CALLS = 1
    VALIDATE_NONCE_UPGRADE = 2
    APPROVE_AMOUNT = 500
    TRANSFER_AMOUNT = 100
    INITIAL_SUPPLY = 1000
    CALL_SET_ADDITIONAL_DATA = [0xA, 0xB]

    blocks: list[str] = []

    # --- EFO: basic (empty calls) ---

    sig = generate_basic_outside_execution(addr)
    blocks.append(format_signature_cairo(
        sig, "get_outside_execution_signature",
        "EFO signature: empty calls, nonce=1, chain_id=1.",
    ))

    sig = generate_basic_outside_execution(addr, evm_chain_id=2)
    blocks.append(format_signature_cairo(
        sig, "get_signature_evm_chain_id_2",
        "EFO signature: empty calls, nonce=1, chain_id=2.",
    ))

    sig = generate_wrong_sn_chain_name(addr)
    blocks.append(format_signature_cairo(
        sig, "get_signature_wrong_sn_chain_name",
        "EFO signature signed with SN_SEPOLIA domain (fails against SN_MAIN).",
    ))

    sig = generate_wrong_contract_address()
    blocks.append(format_signature_cairo(
        sig, "get_signature_wrong_contract_address",
        "EFO signature signed with wrong contract address (domain mismatch).",
    ))

    # --- EFO: with ERC20 calls ---

    sig = generate_single_call_approve_test(addr, token, spender, APPROVE_AMOUNT, NONCE_SINGLE_CALL)
    blocks.append(format_signature_cairo(
        sig, "get_single_call_approve_signature",
        f"EFO signature: approve(0x1234, 500), nonce={NONCE_SINGLE_CALL}.",
    ))

    sig = generate_multi_call_test(
        addr, token, spender, recipient, APPROVE_AMOUNT, TRANSFER_AMOUNT, NONCE_MULTI_CALL,
    )
    blocks.append(format_signature_cairo(
        sig, "get_multi_call_signature",
        f"EFO signature: approve(500) + transfer(100), nonce={NONCE_MULTI_CALL}.",
    ))

    sig = generate_atomicity_test(
        addr, token, spender, recipient, APPROVE_AMOUNT, INITIAL_SUPPLY + 1, NONCE_ATOMICITY,
    )
    blocks.append(format_signature_cairo(
        sig, "get_atomicity_test_signature",
        f"EFO signature: approve(500) + transfer(1001, fails), nonce={NONCE_ATOMICITY}.",
    ))

    sig = generate_specific_caller_test(addr, SPECIFIC_CALLER, NONCE_SPECIFIC_CALLER)
    blocks.append(format_signature_cairo(
        sig, "get_specific_caller_signature",
        f"EFO signature: specific caller=0xCAFE, nonce={NONCE_SPECIFIC_CALLER}, empty calls.",
    ))

    # --- __validate__ ---

    sig = generate_validate_empty_calls(addr)
    blocks.append(format_signature_cairo(
        sig, "get_validate_empty_calls_signature",
        "__validate__ signature: empty calls, nonce=0.",
    ))

    sig = generate_validate_with_approve(addr, token, spender, APPROVE_AMOUNT, VALIDATE_NONCE_WITH_CALLS)
    blocks.append(format_signature_cairo(
        sig, "get_validate_with_approve_signature",
        "__validate__ signature: approve(0x1234, 500), nonce=1.",
    ))

    sig = generate_validate_wrong_chain(addr)
    blocks.append(format_signature_cairo(
        sig, "get_validate_wrong_chain_signature",
        "__validate__ signature signed with SN_SEPOLIA domain (fails against SN_MAIN).",
    ))

    # --- CallSet ---

    sig = generate_call_set_empty_calls(addr)
    blocks.append(format_signature_cairo(
        sig, "get_call_set_empty_calls_signature",
        "CallSet signature: empty calls.",
    ))

    sig = generate_call_set_with_approve(addr, token, spender, APPROVE_AMOUNT)
    blocks.append(format_signature_cairo(
        sig, "get_call_set_with_approve_signature",
        "CallSet signature: approve(0x1234, 500).",
    ))

    sig = generate_call_set_with_additional_data(
        addr, token, spender, APPROVE_AMOUNT, CALL_SET_ADDITIONAL_DATA,
    )
    blocks.append(format_signature_cairo(
        sig, "get_call_set_with_additional_data_signature",
        f"CallSet signature: approve(0x1234, 500) with additional_data={CALL_SET_ADDITIONAL_DATA}.",
    ))

    # --- Upgrade ---

    sig = generate_efo_upgrade_test(addr, FIXED_UPGRADE_TARGET_CLASS_HASH, NONCE_EFO_UPGRADE)
    blocks.append(format_signature_cairo(
        sig, "get_efo_upgrade_signature",
        f"EFO signature: upgrade(FIXED_UPGRADE_TARGET_CLASS_HASH, None), nonce={NONCE_EFO_UPGRADE}.",
    ))

    sig = generate_validate_upgrade(addr, FIXED_UPGRADE_TARGET_CLASS_HASH, VALIDATE_NONCE_UPGRADE)
    blocks.append(format_signature_cairo(
        sig, "get_validate_upgrade_signature",
        f"__validate__ signature: upgrade(FIXED_UPGRADE_TARGET_CLASS_HASH, None), nonce={VALIDATE_NONCE_UPGRADE}.",
    ))

    return blocks


# ============================================================================
# File I/O
# ============================================================================


def build_generated_block(blocks: list[str]) -> str:
    """Wrap signature functions in marker comments."""
    result = MARKER_START + "\n"
    for block in blocks:
        result += "\n" + block + "\n"
    result += MARKER_END + "\n"
    return result


def write_signatures_to_file(cairo_path: str, generated_block: str) -> bool:
    """
    Replace the marker-delimited section in the Cairo file with the generated block.
    Returns True if the file was changed.
    """
    with open(cairo_path, "r") as f:
        content = f.read()

    pattern = re.compile(
        re.escape(MARKER_START) + r".*?" + re.escape(MARKER_END) + r"\n?",
        re.DOTALL,
    )

    if not pattern.search(content):
        raise ValueError(
            f"Markers not found in {cairo_path}. "
            f"Expected '{MARKER_START}' and '{MARKER_END}'."
        )

    new_content = pattern.sub(generated_block, content)

    if new_content == content:
        return False

    with open(cairo_path, "w") as f:
        f.write(new_content)
    return True


# ============================================================================
# Main
# ============================================================================


def main():
    """Generate all test signatures and write them into test_utils.cairo."""
    script_dir = pathlib.Path(__file__).resolve().parent
    cairo_path = (script_dir / ".." / "src" / "test_utils.cairo").resolve()

    print("Generating signatures...")
    blocks = generate_all_signatures()
    generated_block = build_generated_block(blocks)

    print(f"Writing to {cairo_path}")
    changed = write_signatures_to_file(str(cairo_path), generated_block)

    if changed:
        print("File updated.")
    else:
        print("No changes (file already up to date).")


if __name__ == "__main__":
    main()
