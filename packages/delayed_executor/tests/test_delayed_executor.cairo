use core::num::traits::Bounded;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_block_timestamp, cheat_caller_address, declare, spy_events,
};
use starknet::account::Call;
use starknet::{ContractAddress, SyscallResultTrait};
use starkware_delayed_executor::common::{CallSetStatus, CallSetSubmitted};
use starkware_delayed_executor::delayed_executor::{
    DelayedExecutor, IDelayedExecutorDispatcher, IDelayedExecutorDispatcherTrait,
};
use crate::mocks::IMockCounterDispatcherTrait;
use crate::test_helpers::{deploy_counter, increment_call};

const OWNER: felt252 = 0x1234;
const NON_OWNER: felt252 = 0x5678;
const DELAY: u64 = 100;
const EXPIRATION: u64 = 3600; // MIN_EXPIRATION = 1 hour.
const INITIAL_TIMESTAMP: u64 = 10000;

fn deploy_executor() -> (IDelayedExecutorDispatcher, ContractAddress) {
    let contract = declare("DelayedExecutor").unwrap().contract_class();
    let owner: ContractAddress = OWNER.try_into().unwrap();
    let mut constructor_args: Array<felt252> = array![];
    Serde::serialize(@owner, ref constructor_args);
    Serde::serialize(@DELAY, ref constructor_args);
    Serde::serialize(@EXPIRATION, ref constructor_args);
    let (address, _) = contract.deploy(@constructor_args).unwrap_syscall();
    (IDelayedExecutorDispatcher { contract_address: address }, owner)
}

// ============== Basic Flow Tests ==============

#[test]
fn test_register_and_exec_calls() {
    let (executor, owner) = deploy_executor();
    let counter = deploy_counter();
    let counter_address = counter.contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let mut spy = spy_events();

    let call = increment_call(counter_address);
    let calls: Span<Call> = array![call].span();

    let call_set_key = executor.submit_calls(calls, 0);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);

    let expected_event = DelayedExecutor::Event::CallSetSubmitted(
        CallSetSubmitted { call_set_key, allowed_time: INITIAL_TIMESTAMP + DELAY },
    );
    spy.assert_emitted(@array![(executor.contract_address, expected_event)]);

    assert_eq!(counter.get_count(), 0);

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Ready);

    executor.exec_calls(calls, 0);

    assert_eq!(counter.get_count(), 1);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Executed);
}

#[test]
fn test_get_execution_params() {
    let (executor, _) = deploy_executor();

    assert_eq!(executor.get_execution_delay(), DELAY);
    assert_eq!(executor.get_execution_expiration(), EXPIRATION);
}

// ============== CallSetStatus Tests ==============

#[test]
fn test_status_unknown_for_unregistered() {
    let (executor, _) = deploy_executor();
    let unknown_key: felt252 = 0x12345;

    assert_eq!(executor.get_call_set_status(unknown_key), CallSetStatus::Unknown);
}

#[test]
fn test_status_transitions() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let calls: Span<Call> = array![call].span();

    // Unknown before registration.
    let random_key = 0x999;
    assert_eq!(executor.get_call_set_status(random_key), CallSetStatus::Unknown);

    // Pending after registration.
    let call_set_key = executor.submit_calls(calls, 0);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);

    // Ready after delay.
    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Ready);

    // Expired after expiration window.
    cheat_block_timestamp(
        executor.contract_address,
        INITIAL_TIMESTAMP + DELAY + EXPIRATION + 1,
        CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Expired);
}

// ============== CallSetReadyTime Tests ==============

#[test]
fn test_allowed_time() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    // Unknown: returns MAX.
    let unknown_key: felt252 = 0x12345;
    assert_eq!(executor.get_call_set_status(unknown_key), CallSetStatus::Unknown);
    assert_eq!(executor.get_call_set_allowed_time(unknown_key), Bounded::<u64>::MAX);

    // Pending: returns allowed_time.
    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span(), 0);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);
    assert_eq!(executor.get_call_set_allowed_time(call_set_key), INITIAL_TIMESTAMP + DELAY);

    // Ready: still returns allowed_time.
    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(executor.get_call_set_allowed_time(call_set_key), INITIAL_TIMESTAMP + DELAY);

    // Executed: returns MAX.
    executor.exec_calls(array![call].span(), 0);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(executor.get_call_set_allowed_time(call_set_key), Bounded::<u64>::MAX);

    // Expired: register new, let it expire. Still returns the real allowed_time — expiry here is
    // derived from it, so the value stays meaningful and the caller can reconstruct the window
    // that closed. `get_call_set_status` is what distinguishes Expired from Ready.
    let resubmit_time = INITIAL_TIMESTAMP + DELAY;
    executor.submit_calls(array![call].span(), 0);
    cheat_block_timestamp(
        executor.contract_address, resubmit_time + DELAY + EXPIRATION + 100, CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Expired);
    assert_eq!(executor.get_call_set_allowed_time(call_set_key), resubmit_time + DELAY);
}

// ============== Register Behavior Tests ==============

/// Re-submitting a call set that is still active reverts rather than returning the key unchanged.
/// A no-op reporting success cannot be told apart at the call site from a real registration, and
/// the timer must not be restartable this way either.
#[test]
#[should_panic(expected: 'ALREADY_SUBMITTED')]
fn test_register_pending_reverts() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let calls: Span<Call> = array![increment_call(counter_address)].span();
    let call_set_key = executor.submit_calls(calls, 0);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);

    // Advance, but stay Pending.
    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP + 50, CheatSpan::Indefinite);
    executor.submit_calls(array![increment_call(counter_address)].span(), 0);
}

/// Same once Ready: the delay has elapsed but the set is still live, so re-submitting is an error
/// rather than a way to restart the timer on an executable batch.
#[test]
#[should_panic(expected: 'ALREADY_SUBMITTED')]
fn test_register_ready_reverts() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call_set_key = executor.submit_calls(array![increment_call(counter_address)].span(), 0);

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Ready);

    executor.submit_calls(array![increment_call(counter_address)].span(), 0);
}

/// The salt is the supported way to queue a second instance of an identical batch, and it stays
/// available while the first is active — so ALREADY_SUBMITTED blocks the accident, not the use
/// case.
#[test]
fn test_register_same_calls_different_salt_succeeds_while_pending() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let key_a = executor.submit_calls(array![increment_call(counter_address)].span(), 0);
    let key_b = executor.submit_calls(array![increment_call(counter_address)].span(), 1);

    assert!(key_a != key_b);
    assert_eq!(executor.get_call_set_status(key_a), CallSetStatus::Pending);
    assert_eq!(executor.get_call_set_status(key_b), CallSetStatus::Pending);
}

#[test]
fn test_register_executed_creates_new() {
    let (executor, owner) = deploy_executor();
    let counter = deploy_counter();
    let counter_address = counter.contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let calls: Span<Call> = array![call].span();

    let call_set_key = executor.submit_calls(calls, 0);

    // Execute it.
    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span(), 0);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(counter.get_count(), 1);

    // Re-register same calls after execution.
    let new_timestamp = INITIAL_TIMESTAMP + DELAY + 100;
    cheat_block_timestamp(executor.contract_address, new_timestamp, CheatSpan::Indefinite);

    let call3 = increment_call(counter_address);
    let call_set_key2 = executor.submit_calls(array![call3].span(), 0);
    assert_eq!(call_set_key, call_set_key2); // Same key.
    assert_eq!(
        executor.get_call_set_status(call_set_key), CallSetStatus::Pending,
    ); // Now pending again.

    // Execute again.
    cheat_block_timestamp(executor.contract_address, new_timestamp + DELAY, CheatSpan::Indefinite);
    let call4 = increment_call(counter_address);
    executor.exec_calls(array![call4].span(), 0);
    assert_eq!(counter.get_count(), 2);
}

#[test]
fn test_register_expired_creates_new() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let calls: Span<Call> = array![call].span();

    let call_set_key = executor.submit_calls(calls, 0);

    // Let it expire.
    let expired_time = INITIAL_TIMESTAMP + DELAY + EXPIRATION + 100;
    cheat_block_timestamp(executor.contract_address, expired_time, CheatSpan::Indefinite);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Expired);

    // Re-register - should create fresh registration.
    let call2 = increment_call(counter_address);
    let call_set_key2 = executor.submit_calls(array![call2].span(), 0);
    assert_eq!(call_set_key, call_set_key2);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);
}

// ============== Remove Tests ==============

#[test]
fn test_remove_pending() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span(), 0);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);

    executor.retract_call_set(call_set_key);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Unknown);
}

#[test]
fn test_remove_ready() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span(), 0);

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Ready);

    executor.retract_call_set(call_set_key);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Unknown);
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_RETRACTABLE')]
fn test_remove_unknown_fails() {
    let (executor, owner) = deploy_executor();

    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let unknown_key: felt252 = 0x12345;
    executor.retract_call_set(unknown_key);
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_RETRACTABLE')]
fn test_remove_executed_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span(), 0);

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span(), 0);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Executed);

    executor.retract_call_set(call_set_key); // Should fail.
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_RETRACTABLE')]
fn test_remove_expired_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span(), 0);

    let expired_time = INITIAL_TIMESTAMP + DELAY + EXPIRATION + 100;
    cheat_block_timestamp(executor.contract_address, expired_time, CheatSpan::Indefinite);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Expired);

    executor.retract_call_set(call_set_key); // Should fail.
}

// ============== Exec Tests ==============

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_pending_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let _call_set_key = executor.submit_calls(array![call].span(), 0);

    // Try to exec while still pending.
    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span(), 0);
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_unknown_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    executor.exec_calls(array![call].span(), 0); // Never registered.
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_expired_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span(), 0);

    let expired_time = INITIAL_TIMESTAMP + DELAY + EXPIRATION + 100;
    cheat_block_timestamp(executor.contract_address, expired_time, CheatSpan::Indefinite);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Expired);

    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span(), 0);
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_twice_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let _call_set_key = executor.submit_calls(array![call].span(), 0);

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );

    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span(), 0); // First exec succeeds.

    let call3 = increment_call(counter_address);
    executor.exec_calls(array![call3].span(), 0); // Second exec fails.
}

// ============== Access Control Tests ==============

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_register_non_owner_fails() {
    let (executor, _owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    let non_owner: ContractAddress = NON_OWNER.try_into().unwrap();
    cheat_caller_address(executor.contract_address, non_owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    executor.submit_calls(array![call].span(), 0);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_exec_non_owner_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let _call_set_key = executor.submit_calls(array![call].span(), 0);

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );

    let non_owner: ContractAddress = NON_OWNER.try_into().unwrap();
    cheat_caller_address(executor.contract_address, non_owner, CheatSpan::Indefinite);

    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span(), 0);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_remove_non_owner_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span(), 0);

    let non_owner: ContractAddress = NON_OWNER.try_into().unwrap();
    cheat_caller_address(executor.contract_address, non_owner, CheatSpan::Indefinite);

    executor.retract_call_set(call_set_key);
}
