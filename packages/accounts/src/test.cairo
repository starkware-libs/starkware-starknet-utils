use openzeppelin::interfaces::accounts::{ISRC6DispatcherTrait, ISRC6_ID};
use openzeppelin::interfaces::introspection::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use openzeppelin::interfaces::src9::{
    ISRC9_V2Dispatcher, ISRC9_V2DispatcherTrait, ISRC9_V2SafeDispatcher,
    ISRC9_V2SafeDispatcherTrait, ISRC9_V2_ID,
};
use openzeppelin::interfaces::token::erc20::IERC20DispatcherTrait;
use snforge_std::cheatcodes::CheatSpan;
use snforge_std::{
    cheat_caller_address, cheat_nonce, cheat_signature, cheat_transaction_version, load, spy_events,
};
use starknet::EthAddress;
use starkware_accounts::interface::{
    IAccount712AdminDispatcher, IAccount712AdminDispatcherTrait, ICUSTOM_SIGNATURE_VALIDATION_ID,
    ICustomSignatureValidationDispatcher, ICustomSignatureValidationDispatcherTrait,
};
use starkware_accounts::test_utils::{
    APPROVE_AMOUNT, APPROVE_SPENDER, EXECUTE_AFTER, EXECUTE_BEFORE, FIXED_UPGRADE_TARGET_CLASS_HASH,
    MOCK_ERC20_INITIAL_SUPPLY, NONCE_ATOMICITY, NONCE_EFO_UPGRADE, NONCE_MULTI_CALL,
    NONCE_SINGLE_CALL, NONCE_SPECIFIC_CALLER, PROTOCOL_ADDRESS, SPECIFIC_CALLER, TEST_ETH_ADDRESS,
    TEST_NONCE, VALIDATE_NONCE_UPGRADE, VALIDATE_NONCE_WITH_CALLS, assert_upgraded_event,
    build_outside_execution_with_calls, build_outside_execution_with_specific_caller,
    build_transfer_call, declare_register_interfaces_eic, deploy_eth712_account, deploy_mock_erc20,
    get_approve_call, get_atomicity_test_signature, get_call_set_empty_calls_signature,
    get_call_set_with_approve_signature, get_efo_upgrade_signature,
    get_invalid_outside_execution_signature, get_invalid_signature, get_multi_call_signature,
    get_outside_execution_signature, get_ownership_signature, get_signature_evm_chain_id_2,
    get_signature_wrong_contract_address, get_signature_wrong_sn_chain_name,
    get_single_call_approve_signature, get_specific_caller_signature, get_test_outside_execution,
    get_validate_empty_calls_signature, get_validate_upgrade_signature,
    get_validate_with_approve_signature, get_validate_wrong_chain_signature, setup_efo_test,
    setup_efo_test_with_erc20, setup_efo_test_with_timestamp, setup_initialized_account,
    setup_validate_test,
};
use starkware_utils_testing::test_utils::cheat_caller_address_once;


// ================================
// initialize tests
// ================================

#[test]
fn test_initialize_success() {
    let (account_address, _) = deploy_eth712_account();
    let account_contract = IAccount712AdminDispatcher { contract_address: account_address };

    // Initialize with valid signature
    account_contract.initialize(TEST_ETH_ADDRESS(), get_ownership_signature());

    // Verify eth_address was stored correctly by reading storage directly
    let stored_values = load(account_address, selector!("eth_address"), 1);
    let stored_eth_address: EthAddress = (*stored_values.at(0)).try_into().unwrap();
    assert!(stored_eth_address == TEST_ETH_ADDRESS(), "eth_address not stored correctly");

    // Verify interfaces are registered
    let src5 = ISRC5Dispatcher { contract_address: account_address };
    assert!(src5.supports_interface(ISRC9_V2_ID), "ISRC9_V2_ID not registered");
    assert!(src5.supports_interface(ISRC6_ID), "ISRC6_ID not registered");
    assert!(
        src5.supports_interface(ICUSTOM_SIGNATURE_VALIDATION_ID),
        "ICUSTOM_SIGNATURE_VALIDATION_ID not registered",
    );
}

#[test]
#[should_panic(expected: 'ALREADY_INITIALIZED')]
fn test_initialize_already_initialized_reverts() {
    let (account_address, _) = deploy_eth712_account();
    let account_contract = IAccount712AdminDispatcher { contract_address: account_address };

    // First initialization should succeed
    account_contract.initialize(TEST_ETH_ADDRESS(), get_ownership_signature());

    // Second initialization should fail
    account_contract.initialize(TEST_ETH_ADDRESS(), get_ownership_signature());
}

#[test]
#[should_panic(expected: 'INVALID_OWNERSHIP_SIGNATURE')]
fn test_initialize_invalid_signature_reverts() {
    let (account_address, _) = deploy_eth712_account();
    let account_contract = IAccount712AdminDispatcher { contract_address: account_address };

    // Initialize with invalid signature
    account_contract.initialize(TEST_ETH_ADDRESS(), get_invalid_signature());
}

// ================================
// upgrade tests
// ================================

const DUMMY_CLASS_HASH: felt252 = 'DUMMY_CLASS_HASH';

#[test]
#[should_panic(expected: 'UNAUTHORIZED')]
fn test_upgrade_unauthorized_reverts() {
    let (account_address, _) = deploy_eth712_account();
    let account_contract = IAccount712AdminDispatcher { contract_address: account_address };

    // Initialize first
    account_contract.initialize(TEST_ETH_ADDRESS(), get_ownership_signature());

    // Try to upgrade from external caller (not self) - reverts before checking class hash
    account_contract.upgrade(DUMMY_CLASS_HASH.try_into().unwrap(), Option::None);
}

#[test]
fn test_upgrade_from_self_succeeds() {
    let (account_address, class_hash) = deploy_eth712_account();
    let account_contract = IAccount712AdminDispatcher { contract_address: account_address };

    // Initialize first
    account_contract.initialize(TEST_ETH_ADDRESS(), get_ownership_signature());

    // Spoof caller as self for a single call
    cheat_caller_address_once(contract_address: account_address, caller_address: account_address);

    let mut spy = spy_events();
    account_contract.upgrade(class_hash, Option::None);

    assert_upgraded_event(ref spy, account_address, class_hash.into());
}

#[test]
fn test_upgrade_with_eic() {
    let (account_address, class_hash) = deploy_eth712_account();
    let account_contract = IAccount712AdminDispatcher { contract_address: account_address };

    // Initialize first
    account_contract.initialize(TEST_ETH_ADDRESS(), get_ownership_signature());

    // Spoof caller as self for a single call
    cheat_caller_address_once(contract_address: account_address, caller_address: account_address);

    let eic_class_hash = declare_register_interfaces_eic();

    // Register a custom interface via EIC
    let custom_interface_id: felt252 = 0x12345678;
    let eic_data: Span<felt252> = array![custom_interface_id].span();

    account_contract.upgrade(class_hash, Option::Some((eic_class_hash, eic_data)));

    // Verify the custom interface was registered
    let src5 = ISRC5Dispatcher { contract_address: account_address };
    assert!(src5.supports_interface(custom_interface_id), "Custom interface not registered");
}

#[test]
fn test_upgrade_via_efo_succeeds() {
    let src9 = setup_efo_test();
    let account_address = src9.contract_address;

    // Declare the upgrade target so replace_class_syscall can find the class.
    declare_register_interfaces_eic();

    // Calldata: upgrade(target, Option::None).
    // In Cairo, Option::None has discriminant 1 (Some = 0, None = 1).
    let upgrade_call = starknet::account::Call {
        to: account_address,
        selector: selector!("upgrade"),
        calldata: array![FIXED_UPGRADE_TARGET_CLASS_HASH, 1].span() // 1 = Option::None
    };
    let outside_execution = build_outside_execution_with_calls(
        array![upgrade_call].span(), NONCE_EFO_UPGRADE,
    );

    let mut spy = spy_events();
    src9.execute_from_outside_v2(outside_execution, get_efo_upgrade_signature().span());

    assert_upgraded_event(ref spy, account_address, FIXED_UPGRADE_TARGET_CLASS_HASH);
}

#[test]
fn test_upgrade_via_real_tx_succeeds() {
    let (account, account_address) = setup_validate_test();

    // Declare the upgrade target so replace_class_syscall can find the class.
    declare_register_interfaces_eic();

    cheat_nonce(account_address, VALIDATE_NONCE_UPGRADE, CheatSpan::Indefinite);
    cheat_signature(
        account_address, get_validate_upgrade_signature().span(), CheatSpan::Indefinite,
    );

    // Calldata: upgrade(target, Option::None).
    // In Cairo, Option::None has discriminant 1 (Some = 0, None = 1).
    let upgrade_call = starknet::account::Call {
        to: account_address,
        selector: selector!("upgrade"),
        calldata: array![FIXED_UPGRADE_TARGET_CLASS_HASH, 1].span() // 1 = Option::None
    };

    // Validate the signed upgrade transaction
    let result = account.__validate__(array![upgrade_call]);
    assert!(result == starknet::VALIDATED, "Expected VALIDATED for upgrade tx");

    // Execute via protocol (zero address caller).
    // Use once-variant so the cheat doesn't also apply to the re-entrant upgrade call,
    // which expects account_address as its caller (assert_only_self).
    cheat_caller_address_once(
        contract_address: account_address, caller_address: PROTOCOL_ADDRESS.try_into().unwrap(),
    );
    let mut spy = spy_events();
    account.__execute__(array![upgrade_call]);

    assert_upgraded_event(ref spy, account_address, FIXED_UPGRADE_TARGET_CLASS_HASH);
}

// ================================
// is_valid_signature tests (ISRC6)
// ================================

#[test]
fn test_is_valid_signature_truncated_hash_returns_invalid() {
    let account = setup_initialized_account();

    // Use the ownership message hash (truncated to fit felt252) and signature (5-felt format)
    // Original: 0x3ce976d55131cd0bdd49f20afbded052d8e907dc6034d95cdf117a8fd7752e3c
    // Only lower 251 bits fit in felt252
    let msg_hash: felt252 = 0x3ce976d55131cd0bdd49f20afbded052d8e907dc6034d95cdf117a8fd7752e;
    let signature = array![
        0xe994c0e202b390bddaffacf04bdea826, // r_high
        0xda47d5165a4577a024d18b8d61c5fe53, // r_low
        0x2e117624d8cc474d0641c3168944eb67, // s_high
        0x46dd0af587023ccad738aa0a82b05f98, // s_low
        28 // v
    ];

    let result = account.is_valid_signature(msg_hash, signature);
    assert!(result == 0, "Signature invalid for truncated hash");
}

#[test]
fn test_is_valid_signature_with_chain_id_valid() {
    let account = setup_initialized_account();

    // Known good felt252 hash + signature for TEST_ETH_ADDRESS.
    // Vector verified against on-chain is_valid_signature.
    let msg_hash: felt252 = 0x9ef76cafa86fee7f1360c5df0868875116d63c2a5eaad26bd23a9a045321b;
    let signature = array![
        0x93fd5f812fbbe930977ca8ac1d7c1a1b, // r_high
        0x2602e266add21880b89061774eab3f55, // r_low
        0x1fb7aa49412cbcd146b1fcc1834dcbba, // s_high
        0xefc75ce10df130b47fd99ba747cae707, // s_low
        27, // v
        1 // chain_id (ignored for is_valid_signature)
    ];

    let result = account.is_valid_signature(msg_hash, signature);
    assert!(result == starknet::VALIDATED, "Expected VALIDATED for known-good signature");
}

#[test]
fn test_is_valid_signature_invalid() {
    let account = setup_initialized_account();

    // Wrong hash
    let msg_hash: felt252 = 0x1234567890;
    let signature = array![
        0xe994c0e202b390bddaffacf04bdea826, // r_high
        0xda47d5165a4577a024d18b8d61c5fe53, // r_low
        0x2e117624d8cc474d0641c3168944eb67, // s_high
        0x46dd0af587023ccad738aa0a82b05f98, // s_low
        28 // v
    ];

    let result = account.is_valid_signature(msg_hash, signature);
    assert!(result == 0, "Signature should be invalid for wrong hash");
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE_LENGTH')]
fn test_is_valid_signature_too_short_reverts() {
    let account = setup_initialized_account();
    account.is_valid_signature(0x1234, array![0x1, 0x2, 0x3, 0x4]);
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE_LENGTH')]
fn test_is_valid_signature_too_long_reverts() {
    let account = setup_initialized_account();
    account.is_valid_signature(0x1234, array![0x1, 0x2, 0x3, 0x4, 28, 1, 0x99]);
}

// ================================
// execute_from_outside_v2 tests
// ================================

#[test]
fn test_execute_from_outside_success() {
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();
    let signature = get_outside_execution_signature();

    // Execute - this should succeed
    src9.execute_from_outside_v2(outside_execution, signature.span());

    // Verify nonce is now used
    assert!(!src9.is_valid_outside_execution_nonce(TEST_NONCE), "Nonce should be marked as used");
}

#[test]
#[should_panic(expected: 'EXECUTED_TOO_EARLY')]
fn test_execute_from_outside_too_early_reverts() {
    let src9 = setup_efo_test_with_timestamp(EXECUTE_AFTER - 1);
    let outside_execution = get_test_outside_execution();
    let signature = get_outside_execution_signature();

    src9.execute_from_outside_v2(outside_execution, signature.span());
}

#[test]
#[should_panic(expected: 'EXECUTED_TOO_LATE')]
fn test_execute_from_outside_too_late_reverts() {
    let src9 = setup_efo_test_with_timestamp(EXECUTE_BEFORE + 1);
    let outside_execution = get_test_outside_execution();
    let signature = get_outside_execution_signature();

    src9.execute_from_outside_v2(outside_execution, signature.span());
}

#[test]
#[should_panic(expected: 'DUPLICATE_NONCE')]
fn test_execute_from_outside_duplicate_nonce_reverts() {
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();
    let signature = get_outside_execution_signature();

    // First execution should succeed
    src9.execute_from_outside_v2(outside_execution, signature.span());

    // Second execution with same nonce should fail
    src9.execute_from_outside_v2(outside_execution, signature.span());
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn test_execute_from_outside_invalid_signature_reverts() {
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();
    let invalid_signature = get_invalid_outside_execution_signature();

    src9.execute_from_outside_v2(outside_execution, invalid_signature.span());
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE_LENGTH')]
fn test_execute_from_outside_short_signature_reverts() {
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();

    src9.execute_from_outside_v2(outside_execution, array![0x1, 0x2, 0x3, 0x4, 28].span());
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE_LENGTH')]
fn test_execute_from_outside_long_signature_reverts() {
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();

    src9.execute_from_outside_v2(outside_execution, array![0x1, 0x2, 0x3, 0x4, 28, 1, 0x99].span());
}

#[test]
fn test_is_valid_outside_execution_nonce() {
    let (account_address, _) = deploy_eth712_account();
    let account_contract = IAccount712AdminDispatcher { contract_address: account_address };

    // Initialize the account
    account_contract.initialize(TEST_ETH_ADDRESS(), get_ownership_signature());

    let src9 = ISRC9_V2Dispatcher { contract_address: account_address };

    // Fresh nonces should be valid
    assert!(src9.is_valid_outside_execution_nonce(1), "Nonce 1 should be valid");
    assert!(src9.is_valid_outside_execution_nonce(2), "Nonce 2 should be valid");
    assert!(src9.is_valid_outside_execution_nonce(12345), "Nonce 12345 should be valid");
}

// ================================
// Domain separator validation tests
// ================================

#[test]
fn test_execute_from_outside_different_evm_chain_id_succeeds() {
    // NOTE: The EVM chain ID is passed WITH the signature (signature[5]) and is used
    // to compute the message hash. This means signatures from different EVM chains
    // are valid as long as they were signed with the correct domain separator.
    // This is by design - it allows signing from multiple EVM chains.
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();

    // Signature generated with EVM chain ID 2 - valid because contract uses chain_id from signature
    let chain_id_2_signature = get_signature_evm_chain_id_2();

    src9.execute_from_outside_v2(outside_execution, chain_id_2_signature.span());
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn test_execute_from_outside_mismatched_chain_id_in_signature_reverts() {
    // Test that passing a different chain_id in the signature than what was used
    // to generate the signature causes validation to fail.
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();

    // Get valid signature (generated with chain_id=1) but change chain_id to 2
    let sig = get_outside_execution_signature();
    let tampered_signature = array![
        *sig.at(0), *sig.at(1), *sig.at(2), *sig.at(3), *sig.at(4),
        2 // chain_id = 2 (but signature was generated with chain_id=1)
    ];

    // Fails because contract computes hash with chain_id=2 but signature used chain_id=1
    src9.execute_from_outside_v2(outside_execution, tampered_signature.span());
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn test_execute_from_outside_wrong_sn_chain_name_reverts() {
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();

    // Signature generated with SN_SEPOLIA instead of SN_MAIN - domain name hash mismatch
    let wrong_sn_chain_signature = get_signature_wrong_sn_chain_name();

    src9.execute_from_outside_v2(outside_execution, wrong_sn_chain_signature.span());
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn test_execute_from_outside_wrong_contract_address_reverts() {
    let src9 = setup_efo_test();
    let outside_execution = get_test_outside_execution();

    // Signature generated with wrong contract address - verifyingContract mismatch
    let wrong_contract_signature = get_signature_wrong_contract_address();

    src9.execute_from_outside_v2(outside_execution, wrong_contract_signature.span());
}

/// Test helper: arbitrary address for recipient in tests.
fn TEST_RECIPIENT() -> starknet::ContractAddress {
    0x5678_felt252.try_into().unwrap()
}

// ================================
// execute_from_outside_v2 tests with actual calls
// ================================

#[test]
fn test_execute_from_outside_single_call_succeeds() {
    let (src9, _, token) = setup_efo_test_with_erc20();

    let approve_call = get_approve_call();
    let outside_execution = build_outside_execution_with_calls(
        array![approve_call].span(), NONCE_SINGLE_CALL,
    );

    src9.execute_from_outside_v2(outside_execution, get_single_call_approve_signature().span());

    let spender: starknet::ContractAddress = APPROVE_SPENDER.try_into().unwrap();
    let allowance = token.allowance(src9.contract_address, spender);
    assert!(allowance == APPROVE_AMOUNT, "Approval not set correctly");
}

#[test]
fn test_execute_from_outside_multi_call_succeeds() {
    let (src9, token_address, token) = setup_efo_test_with_erc20();

    let approve_call = get_approve_call();
    let transfer_amount: u256 = 100_u256;
    let transfer_call = build_transfer_call(token_address, TEST_RECIPIENT(), transfer_amount);
    let outside_execution = build_outside_execution_with_calls(
        array![approve_call, transfer_call].span(), NONCE_MULTI_CALL,
    );

    let account_address = src9.contract_address;
    let initial_account_balance = token.balance_of(account_address);
    let initial_recipient_balance = token.balance_of(TEST_RECIPIENT());

    src9.execute_from_outside_v2(outside_execution, get_multi_call_signature().span());

    let spender: starknet::ContractAddress = APPROVE_SPENDER.try_into().unwrap();
    assert!(token.allowance(account_address, spender) == APPROVE_AMOUNT, "Approval failed");
    assert!(
        token.balance_of(account_address) == initial_account_balance - transfer_amount,
        "Account balance not reduced",
    );
    assert!(
        token.balance_of(TEST_RECIPIENT()) == initial_recipient_balance + transfer_amount,
        "Recipient balance not increased",
    );
}

/// Test that when one call in a multi-call execution fails, the entire execution fails.
/// NOTE: Starknet guarantees atomicity at the protocol level - all state changes are rolled
/// back when a transaction fails. However, snforge's test environment doesn't fully simulate
/// this rollback behavior, so we can only verify that the error is properly propagated.
#[test]
#[feature("safe_dispatcher")]
fn test_execute_from_outside_multi_call_failure_propagates() {
    let (src9, token_address, _) = setup_efo_test_with_erc20();

    let approve_call = get_approve_call();
    let transfer_amount: u256 = MOCK_ERC20_INITIAL_SUPPLY + 1_u256;
    let transfer_call = build_transfer_call(token_address, TEST_RECIPIENT(), transfer_amount);
    let outside_execution = build_outside_execution_with_calls(
        array![approve_call, transfer_call].span(), NONCE_ATOMICITY,
    );

    // Due cairo test limitations, we cannot verify that the state changes are rolled back.
    // So we just verify that the error is propagated.

    // Use safe dispatcher to verify the error is propagated
    let safe_src9 = ISRC9_V2SafeDispatcher { contract_address: src9.contract_address };
    let result = safe_src9
        .execute_from_outside_v2(outside_execution, get_atomicity_test_signature().span());

    // Verify that the execution failed (error from second call propagates)
    assert!(result.is_err(), "Expected call to fail due to insufficient balance");
}

/// Test execute_from_outside_v2 with a specific caller (not ANY_CALLER).
/// The execution should succeed when called by the exact specified caller.
#[test]
fn test_execute_from_outside_specific_caller_succeeds() {
    let src9 = setup_efo_test();

    let specific_caller: starknet::ContractAddress = SPECIFIC_CALLER.try_into().unwrap();
    let outside_execution = build_outside_execution_with_specific_caller(
        NONCE_SPECIFIC_CALLER, specific_caller,
    );

    // Spoof caller to be the specific caller
    cheat_caller_address_once(src9.contract_address, specific_caller);

    // Should succeed because caller matches
    src9.execute_from_outside_v2(outside_execution, get_specific_caller_signature().span());
}

/// Test execute_from_outside_v2 with a specific caller, but called from wrong address.
/// The execution should revert when the actual caller doesn't match.
#[test]
#[should_panic(expected: 'INVALID_CALLER')]
fn test_execute_from_outside_wrong_caller_reverts() {
    let src9 = setup_efo_test();

    let specific_caller: starknet::ContractAddress = SPECIFIC_CALLER.try_into().unwrap();
    let wrong_caller: starknet::ContractAddress = 0xDEAD.try_into().unwrap();
    let outside_execution = build_outside_execution_with_specific_caller(
        NONCE_SPECIFIC_CALLER, specific_caller,
    );

    // Spoof caller to be a DIFFERENT address than specified
    cheat_caller_address_once(src9.contract_address, wrong_caller);

    // Should fail because caller doesn't match
    src9.execute_from_outside_v2(outside_execution, get_specific_caller_signature().span());
}

// ================================
// __validate__ tests
// ================================

#[test]
fn test_validate_success() {
    let (account, account_address) = setup_validate_test();
    let sig = get_validate_empty_calls_signature();
    cheat_signature(account_address, sig.span(), CheatSpan::Indefinite);

    let result = account.__validate__(array![]);
    assert!(result == starknet::VALIDATED, "Expected VALIDATED");
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn test_validate_invalid_signature_reverts() {
    let (account, account_address) = setup_validate_test();
    let garbage_sig = array![0x1, 0x2, 0x3, 0x4, 28, 1];
    cheat_signature(account_address, garbage_sig.span(), CheatSpan::Indefinite);

    account.__validate__(array![]);
}

// ================================
// Custom signature validation (is_custom_signature_valid) tests
// ================================

#[test]
fn test_is_custom_signature_valid_empty_calls_success() {
    // Validates the EIP-712 `CallSet { calls }` message (NOT the transaction message).
    let (_, account_address) = setup_validate_test();
    let custom = ICustomSignatureValidationDispatcher { contract_address: account_address };

    let sig = get_call_set_empty_calls_signature();
    let result = custom.is_custom_signature_valid(array![].span(), sig.span());
    assert!(result == starknet::VALIDATED, "Expected VALIDATED");
}

#[test]
fn test_is_custom_signature_valid_with_calls_success() {
    // The signature binds the actual calls: a `CallSet` over [approve(...)] must validate.
    let (_, account_address) = setup_validate_test();
    let custom = ICustomSignatureValidationDispatcher { contract_address: account_address };

    let sig = get_call_set_with_approve_signature();
    let result = custom.is_custom_signature_valid(array![get_approve_call()].span(), sig.span());
    assert!(result == starknet::VALIDATED, "Expected VALIDATED");
}

#[test]
fn test_is_custom_signature_valid_wrong_calls_returns_zero() {
    // A `CallSet` signature over empty calls must NOT validate a different call set.
    let (_, account_address) = setup_validate_test();
    let custom = ICustomSignatureValidationDispatcher { contract_address: account_address };

    let sig = get_call_set_empty_calls_signature();
    let result = custom.is_custom_signature_valid(array![get_approve_call()].span(), sig.span());
    assert!(result == 0, "Expected 0 for a mismatched call set");
}

#[test]
fn test_is_custom_signature_valid_rejects_transaction_signature() {
    // A signature over the __validate__ `Transaction` message must NOT validate as a `CallSet`
    // (different message, different domain-bound hash) — no cross-message replay.
    let (_, account_address) = setup_validate_test();
    let custom = ICustomSignatureValidationDispatcher { contract_address: account_address };

    let tx_sig = get_validate_empty_calls_signature();
    let result = custom.is_custom_signature_valid(array![].span(), tx_sig.span());
    assert!(result == 0, "Transaction-message signature must not validate as a CallSet");
}

#[test]
fn test_is_custom_signature_valid_invalid_returns_zero() {
    // A bad signature must return 0 (NOT revert) — unlike __validate__, the caller decides.
    let (_, account_address) = setup_validate_test();
    let custom = ICustomSignatureValidationDispatcher { contract_address: account_address };

    let garbage_sig = array![0x1, 0x2, 0x3, 0x4, 28, 1];
    let result = custom.is_custom_signature_valid(array![].span(), garbage_sig.span());
    assert!(result == 0, "Expected 0 for invalid signature");
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn test_validate_wrong_chain_id_reverts() {
    let (account, account_address) = setup_validate_test();
    // Signature was generated with SN_SEPOLIA domain, but chain_id is cheated to SN_MAIN
    let sig = get_validate_wrong_chain_signature();
    cheat_signature(account_address, sig.span(), CheatSpan::Indefinite);

    account.__validate__(array![]);
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn test_validate_wrong_nonce_reverts() {
    let (account, account_address) = setup_validate_test();
    // Signature was generated with nonce=0, but we cheat nonce to 999
    let sig = get_validate_empty_calls_signature();
    cheat_signature(account_address, sig.span(), CheatSpan::Indefinite);
    cheat_nonce(account_address, 999, CheatSpan::Indefinite);

    account.__validate__(array![]);
}

#[test]
fn test_validate_with_approve_call() {
    let (account, account_address) = setup_validate_test();
    let sig = get_validate_with_approve_signature();
    cheat_signature(account_address, sig.span(), CheatSpan::Indefinite);
    cheat_nonce(account_address, VALIDATE_NONCE_WITH_CALLS, CheatSpan::Indefinite);

    let approve_call = get_approve_call();

    let result = account.__validate__(array![approve_call]);
    assert!(result == starknet::VALIDATED, "Expected VALIDATED with approve call");
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE_LENGTH')]
fn test_validate_short_signature_reverts() {
    let (account, account_address) = setup_validate_test();
    cheat_signature(account_address, array![0x1, 0x2, 0x3, 0x4, 28].span(), CheatSpan::Indefinite);

    account.__validate__(array![]);
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE_LENGTH')]
fn test_validate_long_signature_reverts() {
    let (account, account_address) = setup_validate_test();
    cheat_signature(
        account_address, array![0x1, 0x2, 0x3, 0x4, 28, 1, 0x99].span(), CheatSpan::Indefinite,
    );

    account.__validate__(array![]);
}

// ================================
// __execute__ tests
// ================================

#[test]
fn test_execute_from_protocol_succeeds() {
    let (account, account_address) = setup_validate_test();
    cheat_caller_address(
        account_address, PROTOCOL_ADDRESS.try_into().unwrap(), CheatSpan::Indefinite,
    );
    cheat_transaction_version(account_address, 3, CheatSpan::Indefinite);

    account.__execute__(array![]);
}

#[test]
#[should_panic(expected: 'INVALID_CALLER')]
fn test_execute_invalid_caller_reverts() {
    let (account, account_address) = setup_validate_test();
    let external_caller: starknet::ContractAddress = 0xDEAD_felt252.try_into().unwrap();
    cheat_caller_address(account_address, external_caller, CheatSpan::Indefinite);
    cheat_transaction_version(account_address, 3, CheatSpan::Indefinite);

    account.__execute__(array![]);
}

#[test]
#[should_panic(expected: 'INVALID_CALLER')]
fn test_execute_from_self_reverts() {
    let (account, account_address) = setup_validate_test();
    // Self-calls are no longer allowed (protocol-only, matching OZ)
    cheat_caller_address(account_address, account_address, CheatSpan::Indefinite);
    cheat_transaction_version(account_address, 3, CheatSpan::Indefinite);

    account.__execute__(array![]);
}

#[test]
#[should_panic(expected: 'INVALID_TX_VERSION')]
fn test_execute_invalid_tx_version_reverts() {
    let (account, account_address) = setup_validate_test();
    cheat_caller_address(
        account_address, PROTOCOL_ADDRESS.try_into().unwrap(), CheatSpan::Indefinite,
    );
    cheat_transaction_version(account_address, 1, CheatSpan::Indefinite);

    account.__execute__(array![]);
}

#[test]
fn test_execute_with_erc20_call() {
    let (account, account_address) = setup_validate_test();
    let (_, token) = deploy_mock_erc20(account_address);

    cheat_caller_address(
        account_address, PROTOCOL_ADDRESS.try_into().unwrap(), CheatSpan::Indefinite,
    );
    cheat_transaction_version(account_address, 3, CheatSpan::Indefinite);

    let approve_call = get_approve_call();
    account.__execute__(array![approve_call]);

    let spender: starknet::ContractAddress = APPROVE_SPENDER.try_into().unwrap();
    let allowance = token.allowance(account_address, spender);
    assert!(allowance == APPROVE_AMOUNT, "Approval not set correctly");
}
