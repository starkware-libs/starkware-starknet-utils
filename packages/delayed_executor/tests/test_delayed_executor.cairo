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

    let call_set_key = executor.submit_calls(calls);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);

    let expected_event = DelayedExecutor::Event::CallSetSubmitted(
        CallSetSubmitted { call_set_key, enable_time: INITIAL_TIMESTAMP + DELAY },
    );
    spy.assert_emitted(@array![(executor.contract_address, expected_event)]);

    assert_eq!(counter.get_count(), 0);

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Ready);

    executor.exec_calls(calls);

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
    let call_set_key = executor.submit_calls(calls);
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
fn test_ready_time() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    // Unknown: returns MAX.
    let unknown_key: felt252 = 0x12345;
    assert_eq!(executor.get_call_set_status(unknown_key), CallSetStatus::Unknown);
    assert_eq!(executor.get_call_set_ready_time(unknown_key), Bounded::<u64>::MAX);

    // Pending: returns enable_time.
    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span());
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);
    assert_eq!(executor.get_call_set_ready_time(call_set_key), INITIAL_TIMESTAMP + DELAY);

    // Ready: still returns enable_time.
    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(executor.get_call_set_ready_time(call_set_key), INITIAL_TIMESTAMP + DELAY);

    // Executed: returns MAX.
    executor.exec_calls(array![call].span());
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(executor.get_call_set_ready_time(call_set_key), Bounded::<u64>::MAX);

    // Expired: register new, let it expire, returns MAX.
    executor.submit_calls(array![call].span());
    cheat_block_timestamp(
        executor.contract_address,
        INITIAL_TIMESTAMP + DELAY + DELAY + EXPIRATION + 100,
        CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Expired);
    assert_eq!(executor.get_call_set_ready_time(call_set_key), Bounded::<u64>::MAX);
}

// ============== Register Behavior Tests ==============

#[test]
fn test_register_pending_is_nop() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let calls: Span<Call> = array![call].span();

    let call_set_key = executor.submit_calls(calls);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);

    // Advance time but stay in pending.
    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP + 50, CheatSpan::Indefinite);

    // Spy to check no new event.
    let mut spy = spy_events();

    // Re-register same calls - should be NOP.
    let call2 = increment_call(counter_address);
    let calls2: Span<Call> = array![call2].span();
    let call_set_key2 = executor.submit_calls(calls2);

    assert_eq!(call_set_key, call_set_key2);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Pending);

    // No event should be emitted for NOP.
    spy
        .assert_not_emitted(
            @array![
                (
                    executor.contract_address,
                    DelayedExecutor::Event::CallSetSubmitted(
                        CallSetSubmitted {
                            call_set_key, enable_time: INITIAL_TIMESTAMP + 50 + DELAY,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_register_ready_is_nop() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let calls: Span<Call> = array![call].span();

    let call_set_key = executor.submit_calls(calls);

    // Advance to Ready status.
    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Ready);

    // Spy to check no new event.
    let mut spy = spy_events();

    // Re-register same calls while Ready - should be NOP.
    let call2 = increment_call(counter_address);
    let call_set_key2 = executor.submit_calls(array![call2].span());

    assert_eq!(call_set_key, call_set_key2);
    assert_eq!(
        executor.get_call_set_status(call_set_key), CallSetStatus::Ready,
    ); // Still Ready, not reset to Pending.

    // No event should be emitted for NOP.
    spy
        .assert_not_emitted(
            @array![
                (
                    executor.contract_address,
                    DelayedExecutor::Event::CallSetSubmitted(
                        CallSetSubmitted {
                            call_set_key, enable_time: INITIAL_TIMESTAMP + DELAY + DELAY,
                        },
                    ),
                ),
            ],
        );
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

    let call_set_key = executor.submit_calls(calls);

    // Execute it.
    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span());
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(counter.get_count(), 1);

    // Re-register same calls after execution.
    let new_timestamp = INITIAL_TIMESTAMP + DELAY + 100;
    cheat_block_timestamp(executor.contract_address, new_timestamp, CheatSpan::Indefinite);

    let call3 = increment_call(counter_address);
    let call_set_key2 = executor.submit_calls(array![call3].span());
    assert_eq!(call_set_key, call_set_key2); // Same key.
    assert_eq!(
        executor.get_call_set_status(call_set_key), CallSetStatus::Pending,
    ); // Now pending again.

    // Execute again.
    cheat_block_timestamp(executor.contract_address, new_timestamp + DELAY, CheatSpan::Indefinite);
    let call4 = increment_call(counter_address);
    executor.exec_calls(array![call4].span());
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

    let call_set_key = executor.submit_calls(calls);

    // Let it expire.
    let expired_time = INITIAL_TIMESTAMP + DELAY + EXPIRATION + 100;
    cheat_block_timestamp(executor.contract_address, expired_time, CheatSpan::Indefinite);
    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Expired);

    // Re-register - should create fresh registration.
    let call2 = increment_call(counter_address);
    let call_set_key2 = executor.submit_calls(array![call2].span());
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
    let call_set_key = executor.submit_calls(array![call].span());

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
    let call_set_key = executor.submit_calls(array![call].span());

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
    let call_set_key = executor.submit_calls(array![call].span());

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );
    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span());

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
    let call_set_key = executor.submit_calls(array![call].span());

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
    let _call_set_key = executor.submit_calls(array![call].span());

    // Try to exec while still pending.
    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span());
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_unknown_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    executor.exec_calls(array![call].span()); // Never registered.
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_expired_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span());

    let expired_time = INITIAL_TIMESTAMP + DELAY + EXPIRATION + 100;
    cheat_block_timestamp(executor.contract_address, expired_time, CheatSpan::Indefinite);

    assert_eq!(executor.get_call_set_status(call_set_key), CallSetStatus::Expired);

    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span());
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_twice_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let _call_set_key = executor.submit_calls(array![call].span());

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );

    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span()); // First exec succeeds.

    let call3 = increment_call(counter_address);
    executor.exec_calls(array![call3].span()); // Second exec fails.
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
    executor.submit_calls(array![call].span());
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_exec_non_owner_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let _call_set_key = executor.submit_calls(array![call].span());

    cheat_block_timestamp(
        executor.contract_address, INITIAL_TIMESTAMP + DELAY, CheatSpan::Indefinite,
    );

    let non_owner: ContractAddress = NON_OWNER.try_into().unwrap();
    cheat_caller_address(executor.contract_address, non_owner, CheatSpan::Indefinite);

    let call2 = increment_call(counter_address);
    executor.exec_calls(array![call2].span());
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_remove_non_owner_fails() {
    let (executor, owner) = deploy_executor();
    let counter_address = deploy_counter().contract_address;

    cheat_block_timestamp(executor.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(executor.contract_address, owner, CheatSpan::Indefinite);

    let call = increment_call(counter_address);
    let call_set_key = executor.submit_calls(array![call].span());

    let non_owner: ContractAddress = NON_OWNER.try_into().unwrap();
    cheat_caller_address(executor.contract_address, non_owner, CheatSpan::Indefinite);

    executor.retract_call_set(call_set_key);
}
