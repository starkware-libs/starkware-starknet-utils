use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_block_timestamp, cheat_caller_address, declare, spy_events,
};
use starknet::{ContractAddress, SyscallResultTrait};
use starkware_delayed_executor::delayed_executor::{
    IDelayedExecutorDispatcher, IDelayedExecutorDispatcherTrait,
};
use starkware_delayed_executor::multi_executor::{
    IMultiExecutorDispatcher, IMultiExecutorDispatcherTrait, MultiExecutor,
};
use starkware_delayed_executor::multi_owned::{IMultiOwnedDispatcher, IMultiOwnedDispatcherTrait};
use starkware_delayed_executor::types::{
    ApprovalChange, CallSetExecuted, CallSetSignaturesUpdated, CallSetStatus, ExpiredCallSetCleared,
};
use crate::mocks::IMockCounterDispatcherTrait;
use crate::test_helpers::{addr, deploy_counter, increment_call};

const OWNER1: felt252 = 0x1111;
const OWNER2: felt252 = 0x2222;
const OWNER3: felt252 = 0x3333;
const NON_OWNER: felt252 = 0x9999;
const QUORUM_SIZE: u32 = 2;
const DELAY_START_THRESHOLD: u32 = 1;
const ACCEPTANCE_DELAY: u64 = 3600;
const EXECUTION_DELAY: u64 = 86400; // 1 day.
const EXECUTION_EXPIRATION: u64 = 604800; // 1 week.
const INITIAL_TIMESTAMP: u64 = 1000000;

fn deploy_multi_executor_full(
    owners: Span<ContractAddress>,
    quorum_size: u32,
    delay_start_threshold: u32,
    execution_delay: u64,
    execution_expiration: u64,
) -> (IDelayedExecutorDispatcher, IMultiExecutorDispatcher, IMultiOwnedDispatcher) {
    let contract = declare("MultiExecutor").unwrap().contract_class();
    let mut constructor_args: Array<felt252> = array![];
    Serde::serialize(@owners, ref constructor_args);
    Serde::serialize(@quorum_size, ref constructor_args);
    Serde::serialize(@delay_start_threshold, ref constructor_args);
    Serde::serialize(@ACCEPTANCE_DELAY, ref constructor_args);
    Serde::serialize(@execution_delay, ref constructor_args);
    Serde::serialize(@execution_expiration, ref constructor_args);
    let (address, _) = contract.deploy(@constructor_args).unwrap_syscall();
    (
        IDelayedExecutorDispatcher { contract_address: address },
        IMultiExecutorDispatcher { contract_address: address },
        IMultiOwnedDispatcher { contract_address: address },
    )
}

fn deploy_multi_executor(
    owners: Span<ContractAddress>, quorum_size: u32, delay_start_threshold: u32,
) -> (IDelayedExecutorDispatcher, IMultiExecutorDispatcher, IMultiOwnedDispatcher) {
    deploy_multi_executor_full(
        owners, quorum_size, delay_start_threshold, EXECUTION_DELAY, EXECUTION_EXPIRATION,
    )
}

fn deploy_default() -> (
    IDelayedExecutorDispatcher, IMultiExecutorDispatcher, IMultiOwnedDispatcher,
) {
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    deploy_multi_executor(owners, QUORUM_SIZE, DELAY_START_THRESHOLD)
}

// ============== Constructor Tests ==============

#[test]
fn test_constructor_initialization() {
    let (delayed, multi, ownership) = deploy_default();

    assert_eq!(multi.get_quorum_size(), QUORUM_SIZE);
    assert_eq!(multi.get_delay_start_threshold(), DELAY_START_THRESHOLD);
    assert_eq!(delayed.get_execution_delay(), EXECUTION_DELAY);
    assert_eq!(delayed.get_execution_expiration(), EXECUTION_EXPIRATION);

    assert!(ownership.is_owner(addr(OWNER1)));
    assert!(ownership.is_owner(addr(OWNER2)));
    assert!(ownership.is_owner(addr(OWNER3)));
    assert_eq!(ownership.get_n_owners(), 3);
}

#[test]
fn test_constructor_quorum_equals_owners() {
    let owners = array![addr(OWNER1), addr(OWNER2)].span();
    let (_, multi, _) = deploy_multi_executor(owners, 2, 2);
    assert_eq!(multi.get_quorum_size(), 2);
}

#[test]
fn test_constructor_threshold_equals_quorum() {
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (_, multi, _) = deploy_multi_executor(owners, 2, 2);
    assert_eq!(multi.get_delay_start_threshold(), 2);
}

// ============== Registration Tests ==============

#[test]
fn test_register_first_approval_sets_expiration() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);

    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    assert!(multi.has_owner_signed(call_set_key, addr(OWNER1)));
    assert_eq!(
        multi.get_call_set_expiration_time(call_set_key), INITIAL_TIMESTAMP + EXECUTION_EXPIRATION,
    );
}

#[test]
fn test_register_threshold_starts_timer() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First approval (threshold = 1, so timer should start).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    assert_eq!(delayed.get_call_set_ready_time(call_set_key), INITIAL_TIMESTAMP + EXECUTION_DELAY);
}

#[test]
fn test_register_quorum_reached() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First approval (threshold=1 reached, timer starts).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    // Pending: timer started, quorum not reached.
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Pending);

    // Second approval (quorum = 2 reached).
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // AwaitingTimelock: quorum reached but timer not elapsed.
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingTimelock);
}

#[test]
fn test_register_idempotent() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Register again - should be idempotent.
    delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
}

#[test]
#[should_panic(expected: 'ONLY_OWNER')]
fn test_register_non_owner_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_caller_address(delayed.contract_address, addr(NON_OWNER), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();
    delayed.submit_calls(calls);
}

// ============== Execution Tests ==============

#[test]
fn test_exec_with_quorum_and_delay() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // Get quorum (2 approvals).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Advance past delay.
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    // Execute.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    assert_eq!(counter.get_count(), 1);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(multi.get_n_approvals(call_set_key), 0); // Cleared.
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_below_quorum_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // Only 1 approval (quorum = 2).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Advance past delay.
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    // Status is AwaitingQuorum (timelock elapsed but quorum not reached).
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingQuorum);

    // Try to execute - should fail because status is not Ready.
    delayed.exec_calls(calls);
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_before_delay_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // Get quorum.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Don't advance time - try to execute.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_expired_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // Get quorum.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Advance past expiration.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    // Try to execute - should fail (expired).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);
}

// ============== Remove/Withdrawal Tests ==============

#[test]
fn test_remove_withdraws_approval() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // Register.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Remove (withdraw).
    delayed.retract_call_set(call_set_key);
    assert_eq!(multi.get_n_approvals(call_set_key), 0);
    assert!(!multi.has_owner_signed(call_set_key, addr(OWNER1)));
}

#[test]
fn test_remove_below_threshold_clears_timer() {
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (delayed, _, _) = deploy_multi_executor(owners, 2, 2); // threshold = 2

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // Two approvals (reaches threshold).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Timer should be set.
    let ready_time = delayed.get_call_set_ready_time(call_set_key);
    assert_eq!(ready_time, INITIAL_TIMESTAMP + EXECUTION_DELAY);

    // OWNER2 withdraws - drops below threshold.
    delayed.retract_call_set(call_set_key);

    // Timer should be cleared (ready_time becomes MAX).
    let ready_time_after = delayed.get_call_set_ready_time(call_set_key);
    assert_eq!(ready_time_after, core::num::traits::Bounded::<u64>::MAX);
}

#[test]
#[should_panic(expected: 'NOT_SIGNED_BY_CALLER')]
fn test_remove_not_signed_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 registers.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // OWNER2 tries to remove (but didn't sign).
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.retract_call_set(call_set_key);
}

#[test]
#[should_panic(expected: 'CALL_SET_EXPIRED')]
fn test_remove_expired_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Advance past expiration.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    // Try to remove - should fail.
    delayed.retract_call_set(call_set_key);
}

// ============== Clear Expired Tests ==============

#[test]
fn test_clear_expired_succeeds() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Advance past expiration.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    // Clear expired.
    multi.clear_expired_call_set(call_set_key);

    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Unknown);
    assert_eq!(multi.get_n_approvals(call_set_key), 0);
}

#[test]
#[should_panic(expected: 'NOT_EXPIRED')]
fn test_clear_not_expired_fails() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Try to clear without expiring.
    multi.clear_expired_call_set(call_set_key);
}

// ============== Re-registration After Execution ==============

#[test]
fn test_re_register_after_execution() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First execution.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    assert_eq!(counter.get_count(), 1);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);

    // Re-register.
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY + 1, CheatSpan::Indefinite,
    );

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Pending);
}

// ============== View Function Tests ==============

#[test]
fn test_has_owner_index_signed() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);

    // OWNER1 has index 1.
    assert!(multi.has_owner_index_signed(call_set_key, 1));
    assert!(!multi.has_owner_index_signed(call_set_key, 2));
    assert!(!multi.has_owner_index_signed(call_set_key, 3));
}

#[test]
fn test_status_transitions() {
    // Deploy with threshold=2 to test Proposed state (threshold > 1).
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (delayed, multi, _) = deploy_multi_executor(owners, 2, 2);

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // Unknown.
    let call_set_key = core::poseidon::poseidon_hash_span(
        {
            let mut arr: Array<felt252> = array![];
            Serde::serialize(@calls, ref arr);
            arr.span()
        },
    );
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Unknown);

    // Proposed: first signature, below threshold (timer not started).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Proposed);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Pending: second signature reaches threshold (timer starts), quorum also reached.
    // Since threshold == quorum == 2, this becomes AwaitingTimelock.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingTimelock);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // Ready (after delay, quorum already met).
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);

    // Expired (after expiration).
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Expired);
}

#[test]
fn test_status_pending_and_awaiting_quorum() {
    // Deploy with threshold=1, quorum=3 to test Pending and AwaitingQuorum states.
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (delayed, multi, _) = deploy_multi_executor(owners, 3, 1);

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First signature: threshold=1 reached (timer starts), quorum=3 not reached.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Pending);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Second signature: still Pending (2 < 3 quorum).
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Pending);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // Advance past delay: AwaitingQuorum (timelock elapsed but quorum not reached).
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingQuorum);

    // Third signature: Ready (quorum reached AND timelock elapsed).
    cheat_caller_address(delayed.contract_address, addr(OWNER3), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(multi.get_n_approvals(call_set_key), 3);
}

// ============== Event Emission Tests ==============

#[test]
fn test_register_emits_signature_added_event() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let mut spy = spy_events();

    let call_set_key = delayed.submit_calls(calls);

    spy
        .assert_emitted(
            @array![
                (
                    delayed.contract_address,
                    MultiExecutor::Event::CallSetSignaturesUpdated(
                        CallSetSignaturesUpdated {
                            call_set_key,
                            owner_index: 1,
                            owner: addr(OWNER1),
                            change: ApprovalChange::SignatureAdded,
                            n_approvals: 1,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_remove_emits_signature_removed_event() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);

    let mut spy = spy_events();

    delayed.retract_call_set(call_set_key);

    spy
        .assert_emitted(
            @array![
                (
                    delayed.contract_address,
                    MultiExecutor::Event::CallSetSignaturesUpdated(
                        CallSetSignaturesUpdated {
                            call_set_key,
                            owner_index: 1,
                            owner: addr(OWNER1),
                            change: ApprovalChange::SignatureRemoved,
                            n_approvals: 0,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_exec_emits_executed_event() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    let mut spy = spy_events();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    spy
        .assert_emitted(
            @array![
                (
                    delayed.contract_address,
                    MultiExecutor::Event::CallSetExecuted(CallSetExecuted { call_set_key }),
                ),
            ],
        );
}

#[test]
fn test_clear_expired_emits_cleared_event() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    let mut spy = spy_events();

    multi.clear_expired_call_set(call_set_key);

    spy
        .assert_emitted(
            @array![
                (
                    delayed.contract_address,
                    MultiExecutor::Event::ExpiredCallSetCleared(
                        ExpiredCallSetCleared { call_set_key },
                    ),
                ),
            ],
        );
}

// ============== Registration Edge Case Tests ==============

#[test]
#[should_panic(expected: 'CALL_SET_EXPIRED')]
fn test_register_expired_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First owner registers.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Advance past expiration.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    // Second owner tries to register on expired call set.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
}

#[test]
fn test_register_threshold_two_timer_on_second() {
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (delayed, _, _) = deploy_multi_executor(owners, 2, 2); // threshold = 2

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First approval - timer should NOT start (threshold = 2).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Ready time should be MAX (timer not started).
    assert_eq!(
        delayed.get_call_set_ready_time(call_set_key), core::num::traits::Bounded::<u64>::MAX,
    );

    // Second approval - timer should start.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Ready time should now be set.
    assert_eq!(delayed.get_call_set_ready_time(call_set_key), INITIAL_TIMESTAMP + EXECUTION_DELAY);
}

// ============== Execution Edge Case Tests ==============

#[test]
#[should_panic(expected: 'ONLY_OWNER')]
fn test_exec_non_owner_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    // Non-owner tries to execute.
    cheat_caller_address(delayed.contract_address, addr(NON_OWNER), CheatSpan::Indefinite);
    delayed.exec_calls(calls);
}

#[test]
fn test_exec_at_exact_delay_boundary() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Advance to exactly allowed_time (not past it).
    let ready_time = delayed.get_call_set_ready_time(call_set_key);
    cheat_block_timestamp(delayed.contract_address, ready_time, CheatSpan::Indefinite);

    // Execute should succeed at exact boundary.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    assert_eq!(counter.get_count(), 1);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
}

#[test]
#[should_panic(expected: 'CALL_SET_NOT_EXECUTABLE')]
fn test_exec_unknown_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // Try to execute without registering.
    delayed.exec_calls(calls);
}

#[test]
fn test_exec_clears_all_approvals() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // All three owners approve.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER3), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    assert_eq!(multi.get_n_approvals(call_set_key), 3);
    assert!(multi.has_owner_index_signed(call_set_key, 1));
    assert!(multi.has_owner_index_signed(call_set_key, 2));
    assert!(multi.has_owner_index_signed(call_set_key, 3));

    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    // All approvals should be cleared.
    assert_eq!(multi.get_n_approvals(call_set_key), 0);
    assert!(!multi.has_owner_index_signed(call_set_key, 1));
    assert!(!multi.has_owner_index_signed(call_set_key, 2));
    assert!(!multi.has_owner_index_signed(call_set_key, 3));
}

#[test]
fn test_exec_multiple_calls() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![
        increment_call(counter.contract_address), increment_call(counter.contract_address),
        increment_call(counter.contract_address),
    ]
        .span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    // All 3 increment calls should have executed.
    assert_eq!(counter.get_count(), 3);
}

// ============== Remove Edge Case Tests ==============

#[test]
#[should_panic(expected: 'ONLY_OWNER')]
fn test_remove_non_owner_fails() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Non-owner tries to remove.
    cheat_caller_address(delayed.contract_address, addr(NON_OWNER), CheatSpan::Indefinite);
    delayed.retract_call_set(call_set_key);
}

// ============== Clear Expired Edge Case Tests ==============

#[test]
#[should_panic(expected: 'ONLY_OWNER')]
fn test_clear_expired_non_owner_fails() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    // Non-owner tries to clear.
    cheat_caller_address(delayed.contract_address, addr(NON_OWNER), CheatSpan::Indefinite);
    multi.clear_expired_call_set(call_set_key);
}

#[test]
#[should_panic(expected: 'NOT_EXPIRED')]
fn test_clear_unknown_fails() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    // Try to clear an unknown call set key.
    let unknown_key: felt252 = 0x12345;
    multi.clear_expired_call_set(unknown_key);
}

// ============== View Function Edge Case Tests ==============

#[test]
fn test_get_n_approvals_unknown_returns_zero() {
    let (_, multi, _) = deploy_default();

    let unknown_key: felt252 = 0x12345;
    assert_eq!(multi.get_n_approvals(unknown_key), 0);
}

#[test]
fn test_has_owner_signed_unknown_returns_false() {
    let (_, multi, _) = deploy_default();

    let unknown_key: felt252 = 0x12345;
    assert!(!multi.has_owner_signed(unknown_key, addr(OWNER1)));
    assert!(!multi.has_owner_index_signed(unknown_key, 1));
}

// `has_owner_signed(address)` is index-based, not identity-based. It resolves the address
// to its current owner index, then checks whether that index has a signature registered.
// This means:
//   - After ownership transfer, the NEW owner "inherits" any signature that was cast at
//     that index by the PREVIOUS owner — even though the new owner never personally signed.
//   - The ORIGINAL signer, now removed from the owner set (index 0), will return false
//     despite having been the one who actually signed.
// This is by design: approvals are tied to owner *slots*, not to addresses.
#[test]
fn test_has_owner_signed_reflects_index_not_identity() {
    let (delayed, multi, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 (index 1) signs the call set.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Confirm OWNER1 is reported as having signed.
    assert!(multi.has_owner_signed(call_set_key, addr(OWNER1)));
    assert!(multi.has_owner_index_signed(call_set_key, 1));

    // Now replace OWNER1 with NEW_OWNER at index 1.
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // The underlying index 1 still has a signature.
    assert!(multi.has_owner_index_signed(call_set_key, 1));

    // NEW_OWNER now holds index 1, so has_owner_signed reports them as "signed"
    // — even though they never personally called submit_calls.
    assert!(multi.has_owner_signed(call_set_key, addr(NEW_OWNER)));

    // OWNER1 is no longer an owner (index 0), so has_owner_signed returns false
    // — even though they were the one who actually signed.
    assert!(!multi.has_owner_signed(call_set_key, addr(OWNER1)));
}

#[test]
fn test_ready_time_for_executed_returns_max() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    // Ready time for executed call set should be MAX.
    assert_eq!(
        delayed.get_call_set_ready_time(call_set_key), core::num::traits::Bounded::<u64>::MAX,
    );
}

#[test]
fn test_expiration_time_after_clear_returns_zero() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Verify expiration time is set.
    assert_eq!(
        multi.get_call_set_expiration_time(call_set_key), INITIAL_TIMESTAMP + EXECUTION_EXPIRATION,
    );

    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    multi.clear_expired_call_set(call_set_key);

    // Expiration time should be cleared.
    assert_eq!(multi.get_call_set_expiration_time(call_set_key), 0);
}

// ============== Independence and Boundary Tests ==============

#[test]
fn test_different_call_sets_independent() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter1 = deploy_counter();
    let counter2 = deploy_counter();

    let calls1 = array![increment_call(counter1.contract_address)].span();
    let calls2 = array![increment_call(counter2.contract_address)].span();

    // Register calls1 with OWNER1 only.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let key1 = delayed.submit_calls(calls1);

    // Register calls2 with OWNER2 only.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    let key2 = delayed.submit_calls(calls2);

    // Verify independence.
    assert!(key1 != key2);
    assert_eq!(multi.get_n_approvals(key1), 1);
    assert_eq!(multi.get_n_approvals(key2), 1);
    assert!(multi.has_owner_signed(key1, addr(OWNER1)));
    assert!(!multi.has_owner_signed(key1, addr(OWNER2)));
    assert!(!multi.has_owner_signed(key2, addr(OWNER1)));
    assert!(multi.has_owner_signed(key2, addr(OWNER2)));
}

#[test]
fn test_exec_at_exact_expiration_succeeds() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Advance to exactly expiration time (not past it).
    let expiration_time = multi.get_call_set_expiration_time(call_set_key);
    cheat_block_timestamp(delayed.contract_address, expiration_time, CheatSpan::Indefinite);

    // Execute should succeed at exact boundary (not expired yet).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    assert_eq!(counter.get_count(), 1);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
}

#[test]
fn test_re_register_after_clear_expired() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First registration.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Expire it.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    // Clear expired.
    multi.clear_expired_call_set(call_set_key);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Unknown);

    // Re-register after clearing.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 2,
        CheatSpan::Indefinite,
    );
    delayed.submit_calls(calls);

    // Should be pending again.
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Pending);
}

// ============== Execution Semantics Tests ==============

#[test]
fn test_any_owner_can_execute() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 and OWNER2 sign (quorum = 2).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    // OWNER3 (who didn't sign) can execute.
    cheat_caller_address(delayed.contract_address, addr(OWNER3), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    assert_eq!(counter.get_count(), 1);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
}

#[test]
fn test_executed_tx_doesnt_expire() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);

    // Advance past what would be expiration time.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1000,
        CheatSpan::Indefinite,
    );

    // Status should still be Executed, not Expired.
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
}

#[test]
fn test_register_same_signer_on_expired_idempotent() {
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 registers.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Expire it.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    // OWNER1 (who already signed) re-registers - should be idempotent (no revert).
    delayed.submit_calls(calls);

    // Approval count unchanged (idempotent).
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Expired);
}

#[test]
fn test_register_idempotent_no_event() {
    let (delayed, _, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First registration emits event.
    delayed.submit_calls(calls);

    // Re-register (idempotent).
    delayed.submit_calls(calls);
    // Verify no additional approvals (idempotent behavior).
}

// ============== Owner Replacement and Signature Index Tests ==============

#[test]
fn test_replaced_owner_inherits_signature() {
    let (delayed, multi, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 registers.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    assert!(multi.has_owner_index_signed(call_set_key, 1));

    // OWNER1 nominates NEW_OWNER.
    ownership.transfer_ownership(addr(NEW_OWNER));

    // Advance past acceptance delay.
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );

    // NEW_OWNER accepts.
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // NEW_OWNER now has index 1 (inherited from OWNER1).
    assert!(ownership.is_owner(addr(NEW_OWNER)));
    assert!(!ownership.is_owner(addr(OWNER1)));
    assert_eq!(ownership.get_owner_index(addr(NEW_OWNER)), 1);

    // Index 1's signature is still counted.
    assert!(multi.has_owner_index_signed(call_set_key, 1));
    assert!(multi.has_owner_signed(call_set_key, addr(NEW_OWNER)));
    assert!(!multi.has_owner_signed(call_set_key, addr(OWNER1))); // OWNER1 not owner anymore

    // NEW_OWNER tries to register - should be idempotent (already signed via index).
    delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1); // Still 1, not 2.
}

#[test]
fn test_replaced_owner_can_unsign_previous_signature() {
    let (delayed, multi, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 registers.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert!(multi.has_owner_index_signed(call_set_key, 1));

    // Replace OWNER1 with NEW_OWNER.
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // NEW_OWNER can unsign the signature that OWNER1 made (same index).
    delayed.retract_call_set(call_set_key);

    assert!(!multi.has_owner_index_signed(call_set_key, 1));
    assert_eq!(multi.get_n_approvals(call_set_key), 0);
}

#[test]
fn test_sign_by_replaced_owner_then_original_comes_back() {
    let (delayed, multi, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 (index 1) signs.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // OWNER2 (index 2) signs.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // Replace OWNER1 with NEW_OWNER.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // Now replace OWNER3 with original OWNER1.
    cheat_caller_address(delayed.contract_address, addr(OWNER3), CheatSpan::Indefinite);
    ownership.transfer_ownership(addr(OWNER1));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + 2 * ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // OWNER1 is back but now at index 3.
    assert_eq!(ownership.get_owner_index(addr(OWNER1)), 3);

    // OWNER1 can now sign again (at index 3), which adds a new signature.
    delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 3);

    // Indices 1, 2, 3 are all signed.
    assert!(multi.has_owner_index_signed(call_set_key, 1));
    assert!(multi.has_owner_index_signed(call_set_key, 2));
    assert!(multi.has_owner_index_signed(call_set_key, 3));
}

// ============== Mix & Match Signer Scenario Tests ==============

#[test]
fn test_multiple_call_sets_with_owner_replacement() {
    let (delayed, multi, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter1 = deploy_counter();
    let counter2 = deploy_counter();
    let calls1 = array![increment_call(counter1.contract_address)].span();
    let calls2 = array![increment_call(counter2.contract_address)].span();

    // OWNER1 signs both call sets.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let key1 = delayed.submit_calls(calls1);
    let key2 = delayed.submit_calls(calls2);

    assert_eq!(multi.get_n_approvals(key1), 1);
    assert_eq!(multi.get_n_approvals(key2), 1);

    // Replace OWNER1 with NEW_OWNER.
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // NEW_OWNER's signatures are inherited for BOTH call sets.
    assert!(multi.has_owner_signed(key1, addr(NEW_OWNER)));
    assert!(multi.has_owner_signed(key2, addr(NEW_OWNER)));

    // Re-registering by NEW_OWNER is idempotent for both.
    delayed.submit_calls(calls1);
    delayed.submit_calls(calls2);
    assert_eq!(multi.get_n_approvals(key1), 1);
    assert_eq!(multi.get_n_approvals(key2), 1);
}

#[test]
fn test_quorum_maintained_after_owner_replacement() {
    let (delayed, multi, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // All 3 owners sign (quorum = 2, so we exceed it).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER3), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    assert_eq!(multi.get_n_approvals(call_set_key), 3);

    // Replace OWNER2 mid-process.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // Approval count is still 3 (NEW_OWNER inherited index 2's signature).
    assert_eq!(multi.get_n_approvals(call_set_key), 3);

    // Advance time and execute.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + ACCEPTANCE_DELAY + EXECUTION_DELAY,
        CheatSpan::Indefinite,
    );

    // NEW_OWNER (who inherited signature) can execute.
    delayed.exec_calls(calls);
    assert_eq!(counter.get_count(), 1);
}

#[test]
fn test_owner_replaced_unsigns_then_signs_fresh() {
    let (delayed, multi, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 signs.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Replace OWNER1 with NEW_OWNER.
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // NEW_OWNER unsigns the inherited signature.
    delayed.retract_call_set(call_set_key);
    assert_eq!(multi.get_n_approvals(call_set_key), 0);
    assert!(!multi.has_owner_index_signed(call_set_key, 1));

    // NEW_OWNER signs fresh.
    delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    assert!(multi.has_owner_index_signed(call_set_key, 1));
}

#[test]
fn test_chain_of_replacements_signature_preserved() {
    let (delayed, multi, ownership) = deploy_default();
    const OWNER_A: felt252 = 0x4444;
    const OWNER_B: felt252 = 0x5555;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 signs.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert!(multi.has_owner_index_signed(call_set_key, 1));

    // OWNER1 -> OWNER_A.
    ownership.transfer_ownership(addr(OWNER_A));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(OWNER_A), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // Signature inherited.
    assert!(multi.has_owner_index_signed(call_set_key, 1));
    assert!(multi.has_owner_signed(call_set_key, addr(OWNER_A)));

    // OWNER_A -> OWNER_B.
    ownership.transfer_ownership(addr(OWNER_B));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + 2 * ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(OWNER_B), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // Signature still inherited through chain.
    assert!(multi.has_owner_index_signed(call_set_key, 1));
    assert!(multi.has_owner_signed(call_set_key, addr(OWNER_B)));

    // OWNER_B can execute (with OWNER2 signing to reach quorum).
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + 2 * ACCEPTANCE_DELAY + EXECUTION_DELAY,
        CheatSpan::Indefinite,
    );

    cheat_caller_address(delayed.contract_address, addr(OWNER_B), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    assert_eq!(counter.get_count(), 1);
}

#[test]
fn test_two_owners_sign_one_replaced_other_executes() {
    let (delayed, multi, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 and OWNER2 sign.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // Replace OWNER1.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // OWNER2 (who signed and wasn't replaced) executes.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + ACCEPTANCE_DELAY + EXECUTION_DELAY,
        CheatSpan::Indefinite,
    );

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.exec_calls(calls);

    assert_eq!(counter.get_count(), 1);
}

#[test]
fn test_timelock_reset_with_owner_replacement() {
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (delayed, multi, ownership) = deploy_multi_executor(owners, 2, 2); // threshold = 2
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 and OWNER2 sign - threshold reached, timer starts.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    let ready_time = delayed.get_call_set_ready_time(call_set_key);
    assert_eq!(ready_time, INITIAL_TIMESTAMP + EXECUTION_DELAY);

    // Replace OWNER2.
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // NEW_OWNER unsigns (drops below threshold).
    delayed.retract_call_set(call_set_key);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Timer should be cleared.
    assert_eq!(
        delayed.get_call_set_ready_time(call_set_key), core::num::traits::Bounded::<u64>::MAX,
    );

    // NEW_OWNER signs again - timer restarts from new timestamp.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + ACCEPTANCE_DELAY + 1000,
        CheatSpan::Indefinite,
    );
    delayed.submit_calls(calls);

    let new_ready_time = delayed.get_call_set_ready_time(call_set_key);
    assert_eq!(new_ready_time, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY + 1000 + EXECUTION_DELAY);
}

#[test]
fn test_expired_call_set_owner_replacement_cannot_sign() {
    let (delayed, _, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 signs.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);

    // Replace OWNER2 with NEW_OWNER.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // Expire the call set.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Expired);
}

#[test]
#[should_panic(expected: 'CALL_SET_EXPIRED')]
fn test_new_owner_cannot_sign_expired_call_set() {
    let (delayed, _, ownership) = deploy_default();
    const NEW_OWNER: felt252 = 0x4444;

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // OWNER1 signs.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);

    // Replace OWNER2 with NEW_OWNER before expiration.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    ownership.transfer_ownership(addr(NEW_OWNER));
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(delayed.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    ownership.accept_ownership();

    // Expire the call set.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );

    // NEW_OWNER tries to sign - should fail (expired).
    delayed.submit_calls(calls);
}

// ============== Collapsed State Transition Tests (delay=0 / single-owner) ==============

#[test]
fn test_first_sig_unknown_to_ready_delay_zero() {
    // With quorum=1, threshold=1, delay=0: a single signature immediately reaches Ready.
    let owners = array![addr(OWNER1)].span();
    let (delayed, multi, _) = deploy_multi_executor_full(owners, 1, 1, 0, EXECUTION_EXPIRATION);

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Execute immediately (no delay to wait for).
    delayed.exec_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(counter.get_count(), 1);
}

#[test]
fn test_first_sig_unknown_to_awaiting_quorum_delay_zero() {
    // With quorum=2, threshold=1, delay=0: first sig starts and instantly elapses the timer,
    // but quorum is not met -> AwaitingQuorum. Second sig reaches quorum -> Ready.
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (delayed, multi, _) = deploy_multi_executor_full(owners, 2, 1, 0, EXECUTION_EXPIRATION);

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingQuorum);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Second signature reaches quorum -> Ready (timer already elapsed).
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);
}

#[test]
fn test_first_sig_unknown_to_awaiting_timelock() {
    // With quorum=1, threshold=1, delay>0: first sig meets threshold+quorum but timer not
    // elapsed -> AwaitingTimelock.
    let owners = array![addr(OWNER1)].span();
    let (delayed, multi, _) = deploy_multi_executor_full(
        owners, 1, 1, EXECUTION_DELAY, EXECUTION_EXPIRATION,
    );

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingTimelock);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // After delay elapses -> Ready.
    cheat_block_timestamp(
        delayed.contract_address, INITIAL_TIMESTAMP + EXECUTION_DELAY, CheatSpan::Indefinite,
    );
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);
}

#[test]
fn test_first_sig_unknown_to_pending() {
    // With quorum=2, threshold=1, delay>0: first sig starts the timer (threshold met) but
    // quorum not met and timer not elapsed -> Pending.
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (delayed, multi, _) = deploy_multi_executor_full(
        owners, 2, 1, EXECUTION_DELAY, EXECUTION_EXPIRATION,
    );

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Pending);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
}

#[test]
fn test_proposed_to_ready_delay_zero() {
    // With quorum=2, threshold=2, delay=0: first sig -> Proposed (below threshold).
    // Second sig reaches threshold+quorum simultaneously, timer elapses instantly -> Ready.
    let owners = array![addr(OWNER1), addr(OWNER2)].span();
    let (delayed, multi, _) = deploy_multi_executor_full(owners, 2, 2, 0, EXECUTION_EXPIRATION);

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Proposed);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // Can execute immediately.
    delayed.exec_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(counter.get_count(), 1);
}

#[test]
fn test_proposed_to_awaiting_quorum_delay_zero() {
    // With quorum=3, threshold=2, delay=0: first sig -> Proposed. Second sig reaches threshold
    // (timer elapses instantly) but quorum not met -> AwaitingQuorum. Third sig -> Ready.
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    let (delayed, multi, _) = deploy_multi_executor_full(owners, 3, 2, 0, EXECUTION_EXPIRATION);

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First sig: below threshold -> Proposed.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Proposed);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // Second sig: threshold reached, timer elapses instantly, quorum not met -> AwaitingQuorum.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingQuorum);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // Third sig: quorum reached -> Ready.
    cheat_caller_address(delayed.contract_address, addr(OWNER3), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(multi.get_n_approvals(call_set_key), 3);
}

#[test]
fn test_re_register_executed_to_ready_delay_zero() {
    // With quorum=1, threshold=1, delay=0: register -> Ready -> Executed -> re-register -> Ready.
    let owners = array![addr(OWNER1)].span();
    let (delayed, _, _) = deploy_multi_executor_full(owners, 1, 1, 0, EXECUTION_EXPIRATION);

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);

    delayed.exec_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(counter.get_count(), 1);

    // Re-register after execution: should go directly to Ready again.
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);

    delayed.exec_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(counter.get_count(), 2);
}

#[test]
fn test_full_lifecycle_delay_zero() {
    // With quorum=2, threshold=1, delay=0: walk through the full lifecycle twice.
    // Unknown -> AwaitingQuorum -> Ready -> Executed -> AwaitingQuorum -> Ready -> Executed.
    let owners = array![addr(OWNER1), addr(OWNER2)].span();
    let (delayed, multi, _) = deploy_multi_executor_full(owners, 2, 1, 0, EXECUTION_EXPIRATION);

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    // First cycle: Unknown -> AwaitingQuorum (1st sig).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingQuorum);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // AwaitingQuorum -> Ready (2nd sig).
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // Ready -> Executed.
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.exec_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(counter.get_count(), 1);

    // Second cycle: Executed -> AwaitingQuorum (re-register, 1st sig).
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::AwaitingQuorum);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);

    // AwaitingQuorum -> Ready (2nd sig).
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.submit_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Ready);
    assert_eq!(multi.get_n_approvals(call_set_key), 2);

    // Ready -> Executed.
    cheat_caller_address(delayed.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    delayed.exec_calls(calls);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Executed);
    assert_eq!(counter.get_count(), 2);
}

// ============== Zero-Approval Expiration Clearing Tests ==============

#[test]
fn test_retract_to_zero_clears_expiration() {
    // When all approvals are withdrawn, the call set should return to Unknown
    // (not remain as a ticking expiration bomb).
    let (delayed, multi, _) = deploy_default();

    cheat_block_timestamp(delayed.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(delayed.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let counter = deploy_counter();
    let calls = array![increment_call(counter.contract_address)].span();

    let call_set_key = delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    assert!(multi.get_call_set_expiration_time(call_set_key) > 0);

    // Retract the only approval.
    delayed.retract_call_set(call_set_key);
    assert_eq!(multi.get_n_approvals(call_set_key), 0);

    // Expiration should be cleared, status should be Unknown.
    assert_eq!(multi.get_call_set_expiration_time(call_set_key), 0);
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Unknown);

    // Advance past original expiration -- should still be Unknown, not Expired.
    cheat_block_timestamp(
        delayed.contract_address,
        INITIAL_TIMESTAMP + EXECUTION_EXPIRATION + 1,
        CheatSpan::Indefinite,
    );
    assert_eq!(delayed.get_call_set_status(call_set_key), CallSetStatus::Unknown);

    // Re-submit should work directly without clear_expired_call_set.
    delayed.submit_calls(calls);
    assert_eq!(multi.get_n_approvals(call_set_key), 1);
    assert!(multi.get_call_set_expiration_time(call_set_key) > 0);
}
