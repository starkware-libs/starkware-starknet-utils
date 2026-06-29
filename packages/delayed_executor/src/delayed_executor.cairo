//! # Delayed Executor
//!
//! Single-owner contract for time-locked execution of batched contract calls.
//! Uses OpenZeppelin's two-step ownership pattern for secure ownership transfers.
//!
//! ## Workflow
//!
//! 1. Owner calls `submit_calls` with a batch of calls to submit them.
//! 2. After `execution_delay` elapses, the call set becomes executable.
//! 3. Owner calls `exec_calls` with the same calls to execute them.
//! 4. If not executed within `execution_expiration`, the call set expires.
//!
//! Call sets are identified by the Poseidon hash of their serialized calls.

use starknet::account::Call;
use starkware_delayed_executor::common::CallSetStatus;

/// Interface for delayed execution of batched contract calls.
///
/// This interface is implemented by both `DelayedExecutor` (single-owner) and
/// `MultiExecutor` (multi-owner), though the semantics of some functions differ.
#[starknet::interface]
pub trait IDelayedExecutor<TState> {
    /// Submits a batch of calls for delayed execution.
    ///
    /// For single-owner: Creates a new call set with a delay timer.
    /// For multi-owner: Adds the caller's approval to the call set.
    ///
    /// Returns the call set key (Poseidon hash of serialized calls).
    fn submit_calls(ref self: TState, calls: Span<Call>) -> felt252;

    /// Executes a previously registered call set.
    ///
    /// Requires the call set to be in Ready status (delay elapsed, not expired).
    /// For multi-owner: Also requires quorum of approvals.
    fn exec_calls(ref self: TState, calls: Span<Call>);

    /// Retracts a call set.
    ///
    /// For single-owner: Cancels the entire call set.
    /// For multi-owner: Withdraws only the caller's approval.
    fn retract_call_set(ref self: TState, call_set_key: felt252);

    /// Returns the current status of a call set.
    fn get_call_set_status(self: @TState, call_set_key: felt252) -> CallSetStatus;

    /// Returns the timestamp when the call set becomes executable.
    ///
    /// Returns `u64::MAX` if the call set is not in Pending/Ready state.
    fn get_call_set_ready_time(self: @TState, call_set_key: felt252) -> u64;

    /// Returns the configured execution delay in seconds.
    fn get_execution_delay(self: @TState) -> u64;

    /// Returns the configured expiration window in seconds.
    fn get_execution_expiration(self: @TState) -> u64;
}

/// Single-owner delayed executor contract.
///
/// Allows the owner to submit batches of contract calls that can only be executed
/// after a configurable delay period. This provides a security window for stakeholders
/// to review pending transactions before execution.
#[starknet::contract]
pub mod DelayedExecutor {
    use core::num::traits::Bounded;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::utils::execution::execute_calls;
    use starknet::account::Call;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp};
    use starkware_delayed_executor::common::{
        CALL_SET_EXECUTED, CallSetExecuted, CallSetRetracted, CallSetStatus, CallSetSubmitted,
        Errors, MAX_DELAY, MAX_EXPIRATION, MIN_EXPIRATION, compute_call_set_key,
    };
    use starkware_delayed_executor::delayed_executor::IDelayedExecutor;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableTwoStepMixinImpl =
        OwnableComponent::OwnableTwoStepMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        /// OpenZeppelin Ownable component storage.
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        /// Minimum delay (in seconds) between registration and execution eligibility.
        execution_delay: u64,
        /// Time window (in seconds) during which execution is allowed after delay.
        execution_expiration: u64,
        /// Maps call_set_key to the timestamp when it becomes executable.
        /// Value of 0 means unregistered, CALL_SET_EXECUTED means already executed.
        call_set_allowed_time: Map<felt252, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        CallSetSubmitted: CallSetSubmitted,
        CallSetExecuted: CallSetExecuted,
        CallSetRetracted: CallSetRetracted,
    }

    /// Initializes the delayed executor.
    ///
    /// # Arguments
    /// * `owner` - Initial owner address.
    /// * `execution_delay` - Delay in seconds before call sets can be executed (max: 28 days).
    /// * `execution_expiration` - Window in seconds during which execution is allowed (1 hour to 52
    /// weeks).
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        execution_delay: u64,
        execution_expiration: u64,
    ) {
        assert(execution_delay <= MAX_DELAY, Errors::DELAY_TOO_LONG);
        assert(execution_expiration >= MIN_EXPIRATION, Errors::EXPIRATION_TOO_SHORT);
        assert(execution_expiration <= MAX_EXPIRATION, Errors::EXPIRATION_TOO_LONG);

        self.ownable.initializer(owner);
        self.execution_delay.write(execution_delay);
        self.execution_expiration.write(execution_expiration);
    }

    #[abi(embed_v0)]
    impl DelayedExecutorImpl of IDelayedExecutor<ContractState> {
        fn submit_calls(ref self: ContractState, calls: Span<Call>) -> felt252 {
            self.ownable.assert_only_owner();

            let call_set_key = compute_call_set_key(calls);
            let status = self.get_call_set_status(call_set_key);

            match status {
                CallSetStatus::Pending | CallSetStatus::Ready => {
                    // NOP: already registered and active, don't reset timer.
                    return call_set_key;
                },
                CallSetStatus::Unknown | CallSetStatus::Executed |
                CallSetStatus::Expired => {
                    // (Re-)register: set new enable_time.
                    let enable_time = get_block_timestamp() + self.execution_delay.read();
                    self.call_set_allowed_time.write(call_set_key, enable_time);
                    self.emit(CallSetSubmitted { call_set_key, enable_time });
                    return call_set_key;
                },
                // These states are not applicable for single-owner executor.
                CallSetStatus::Proposed | CallSetStatus::AwaitingTimelock |
                CallSetStatus::AwaitingQuorum => core::panic_with_felt252(
                    Errors::UNREACHABLE_STATE,
                ),
            }
        }

        fn exec_calls(ref self: ContractState, calls: Span<Call>) {
            self.ownable.assert_only_owner();

            let call_set_key = compute_call_set_key(calls);
            let status = self.get_call_set_status(call_set_key);

            assert(status == CallSetStatus::Ready, Errors::CALL_SET_NOT_EXECUTABLE);

            self.call_set_allowed_time.write(call_set_key, CALL_SET_EXECUTED);

            execute_calls(calls);

            self.emit(CallSetExecuted { call_set_key });
        }

        fn retract_call_set(ref self: ContractState, call_set_key: felt252) {
            self.ownable.assert_only_owner();

            let status = self.get_call_set_status(call_set_key);

            // Only Pending/Ready call sets can be retracted.
            assert(
                status == CallSetStatus::Pending || status == CallSetStatus::Ready,
                Errors::CALL_SET_NOT_RETRACTABLE,
            );

            self.call_set_allowed_time.write(call_set_key, 0);
            self.emit(CallSetRetracted { call_set_key });
        }

        fn get_call_set_status(self: @ContractState, call_set_key: felt252) -> CallSetStatus {
            let allowed_time = self.call_set_allowed_time.read(call_set_key);

            if allowed_time == 0 {
                return CallSetStatus::Unknown;
            }

            if allowed_time == CALL_SET_EXECUTED {
                return CallSetStatus::Executed;
            }

            let now = get_block_timestamp();
            let expiration_time = allowed_time + self.execution_expiration.read();

            if now > expiration_time {
                return CallSetStatus::Expired;
            }

            if now >= allowed_time {
                return CallSetStatus::Ready;
            }

            CallSetStatus::Pending
        }

        fn get_call_set_ready_time(self: @ContractState, call_set_key: felt252) -> u64 {
            let status = self.get_call_set_status(call_set_key);
            match status {
                CallSetStatus::Pending |
                CallSetStatus::Ready => self.call_set_allowed_time.read(call_set_key),
                CallSetStatus::Unknown | CallSetStatus::Executed |
                CallSetStatus::Expired => Bounded::<u64>::MAX,
                CallSetStatus::Proposed | CallSetStatus::AwaitingTimelock |
                CallSetStatus::AwaitingQuorum => core::panic_with_felt252(
                    Errors::UNREACHABLE_STATE,
                ),
            }
        }

        fn get_execution_delay(self: @ContractState) -> u64 {
            self.execution_delay.read()
        }

        fn get_execution_expiration(self: @ContractState) -> u64 {
            self.execution_expiration.read()
        }
    }
}
