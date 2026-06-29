//! # Multi-Owner Executor
//!
//! A multi-signature (multisig) delayed executor requiring quorum approval before execution.
//! Combines the `MultiOwnedComponent` for ownership management with time-locked execution.
//!
//! ## Key Differences from DelayedExecutor
//!
//! - Multiple owners can sign call sets (approvals accumulate).
//! - Execution requires the CallSet to be signed by a quorum of owners.
//! - The delay timer only starts after `delay_start_threshold` approvals.
//! - Each call set has its own expiration countdown starting from the first signature.
//! - `retract_call_set` withdraws only the caller's signature, not the entire call set.
//!
//! ## Workflow
//!
//! 1. Owners call `submit_calls` to add their approval to a call set.
//! 2. Once `delay_start_threshold` approvals are reached, the delay timer begins.
//! 3. After the delay elapses, any owner can call `exec_calls` if quorum is met.
//! 4. If the call set expires before execution, owners can clear it to reclaim storage.
//!
//! ## Interfaces
//!
//! This contract implements:
//! - `IDelayedExecutor`: Common functions (submit, execute, retract, status queries).
//! - `IMultiExecutor`: Multi-owner specific functions (quorum, approvals, expiration).
//! - `IMultiOwned`: Ownership management (via embedded component).

use starknet::ContractAddress;

/// Interface for multi-owner specific functions.
///
/// Common functions (`submit_calls`, `exec_calls`, etc.) are in `IDelayedExecutor`.
#[starknet::interface]
pub trait IMultiExecutor<TState> {
    /// Clears an expired call set to free storage. Only callable on expired call sets.
    fn clear_expired_call_set(ref self: TState, call_set_key: felt252);

    /// Returns the expiration timestamp for a call set (0 if not registered).
    fn get_call_set_expiration_time(self: @TState, call_set_key: felt252) -> u64;

    /// Returns the required number of approvals for execution.
    fn get_quorum_size(self: @TState) -> u32;

    /// Returns the number of approvals needed to start the delay timer.
    fn get_delay_start_threshold(self: @TState) -> u32;

    /// Returns the current number of approvals for a call set.
    fn get_n_approvals(self: @TState, call_set_key: felt252) -> u32;

    /// Returns true if the owner slot currently held by `owner` has a signature on the call set.
    ///
    /// **Important**: This queries by index, not by identity. It resolves the owner's current
    /// index and checks whether that index has a signature registered. After an ownership
    /// transfer, the new owner inherits any signature previously cast at that index — even
    /// though they never personally signed. Conversely, the original signer (now removed)
    /// will return false because they no longer hold any index.
    fn has_owner_signed(self: @TState, call_set_key: felt252, owner: ContractAddress) -> bool;

    /// Returns true if the owner slot at the given 1-based index has a signature on the call set.
    fn has_owner_index_signed(self: @TState, call_set_key: felt252, owner_index: u32) -> bool;
}

/// Multi-owner delayed executor with quorum-based approval.
#[starknet::contract]
pub mod MultiExecutor {
    use core::num::traits::Bounded;
    use openzeppelin::utils::execution::execute_calls;
    use starknet::account::Call;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use starkware_delayed_executor::common::{
        ApprovalChange, CALL_SET_EXECUTED, CallSetExecuted, CallSetSignaturesUpdated, CallSetStatus,
        Errors, ExpiredCallSetCleared, MAX_DELAY, MAX_EXPIRATION, MIN_EXPIRATION,
        compute_call_set_key,
    };
    use starkware_delayed_executor::delayed_executor::IDelayedExecutor;
    use starkware_delayed_executor::multi_executor::IMultiExecutor;
    use starkware_delayed_executor::multi_owned::MultiOwnedComponent;

    component!(path: MultiOwnedComponent, storage: multi_owned, event: MultiOwnedEvent);

    #[abi(embed_v0)]
    impl MultiOwnedImpl = MultiOwnedComponent::MultiOwnedImpl<ContractState>;
    impl MultiOwnedInternalImpl = MultiOwnedComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        /// Multi-owner component storage.
        #[substorage(v0)]
        multi_owned: MultiOwnedComponent::Storage,
        /// Delay (seconds) from threshold reached until execution is allowed.
        execution_delay: u64,
        /// Window (seconds) from first signature until call set expires.
        execution_expiration: u64,
        /// Minimum approvals required to execute a call set.
        quorum_size: u32,
        /// Number of approvals needed to start the delay timer.
        delay_start_threshold: u32,
        /// Maps call_set_key to the timestamp after which it is allowed to be executed (time-wise).
        /// 0 = not yet reached threshold, CALL_SET_EXECUTED = already executed.
        call_set_allowed_time: Map<felt252, u64>,
        /// Maps call_set_key to the expiration timestamp.
        call_set_expiration: Map<felt252, u64>,
        /// Maps call_set_key to the number of owner approvals.
        call_set_n_approvals: Map<felt252, u32>,
        /// Maps (call_set_key, owner_index) to whether that owner has approved.
        call_set_approvers: Map<(felt252, u32), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        MultiOwnedEvent: MultiOwnedComponent::Event,
        CallSetSignaturesUpdated: CallSetSignaturesUpdated,
        CallSetExecuted: CallSetExecuted,
        ExpiredCallSetCleared: ExpiredCallSetCleared,
    }

    /// Initializes the multi-executor.
    ///
    /// # Arguments
    /// * `owners` - Initial owner addresses.
    /// * `quorum_size` - Minimum approvals needed to execute (1 to len(owners)).
    /// * `delay_start_threshold` - Approvals needed to start delay timer (1 to quorum_size).
    /// * `owner_acceptance_delay` - Delay for ownership transfers (see MultiOwnedComponent).
    /// * `execution_delay` - Delay from threshold to execution eligibility (max: 28 days).
    /// * `execution_expiration` - Window from first signature to expiration (1 hour to 52 weeks).
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owners: Span<ContractAddress>,
        quorum_size: u32,
        delay_start_threshold: u32,
        owner_acceptance_delay: u64,
        execution_delay: u64,
        execution_expiration: u64,
    ) {
        assert(quorum_size > 0, Errors::EMPTY_QUORUM);
        assert(quorum_size <= owners.len(), Errors::QUORUM_TOO_BIG);
        assert(
            delay_start_threshold > 0 && delay_start_threshold <= quorum_size,
            Errors::ILLEGAL_THRESHOLD,
        );
        assert(execution_delay <= MAX_DELAY, Errors::DELAY_TOO_LONG);
        assert(execution_expiration >= MIN_EXPIRATION, Errors::EXPIRATION_TOO_SHORT);
        assert(execution_expiration <= MAX_EXPIRATION, Errors::EXPIRATION_TOO_LONG);

        self.multi_owned.initializer(owners, owner_acceptance_delay);
        self.quorum_size.write(quorum_size);
        self.delay_start_threshold.write(delay_start_threshold);
        self.execution_delay.write(execution_delay);
        self.execution_expiration.write(execution_expiration);
    }

    #[abi(embed_v0)]
    impl DelayedExecutorImpl of IDelayedExecutor<ContractState> {
        fn submit_calls(ref self: ContractState, calls: Span<Call>) -> felt252 {
            self.multi_owned.assert_only_owner();

            let caller = get_caller_address();
            let owner_index = self.multi_owned.get_owner_index(caller);
            let call_set_key = compute_call_set_key(calls);

            // Idempotent: if already signed, return early.
            if self.call_set_approvers.read((call_set_key, owner_index)) {
                return call_set_key;
            }

            let status = self.get_call_set_status(call_set_key);

            // Cannot sign an expired call set.
            assert(status != CallSetStatus::Expired, Errors::CALL_SET_EXPIRED);

            // If previously executed, reset state so it can be re-signed.
            if status == CallSetStatus::Executed {
                self.call_set_allowed_time.write(call_set_key, 0);
            }

            // Add approval.
            self.call_set_approvers.write((call_set_key, owner_index), true);
            let n_approvals = self.call_set_n_approvals.read(call_set_key) + 1;
            self.call_set_n_approvals.write(call_set_key, n_approvals);

            // If threshold reached, start the delay timer.
            if n_approvals == self.delay_start_threshold.read() {
                let allowed_time = get_block_timestamp() + self.execution_delay.read();
                self.call_set_allowed_time.write(call_set_key, allowed_time);
            }

            // If first signer, set expiration time.
            if n_approvals == 1 {
                let expiration = get_block_timestamp() + self.execution_expiration.read();
                self.call_set_expiration.write(call_set_key, expiration);
            }

            self
                .emit(
                    CallSetSignaturesUpdated {
                        call_set_key,
                        owner_index,
                        owner: caller,
                        change: ApprovalChange::SignatureAdded,
                        n_approvals,
                    },
                );

            call_set_key
        }

        fn exec_calls(ref self: ContractState, calls: Span<Call>) {
            self.multi_owned.assert_only_owner();

            let call_set_key = compute_call_set_key(calls);
            let status = self.get_call_set_status(call_set_key);

            assert(status == CallSetStatus::Ready, Errors::CALL_SET_NOT_EXECUTABLE);

            let n_approvals = self.call_set_n_approvals.read(call_set_key);
            assert(n_approvals >= self.quorum_size.read(), Errors::QUORUM_NOT_REACHED);

            // Clear state and mark as executed.
            self._clear_call_set(call_set_key, true);

            execute_calls(calls);

            self.emit(CallSetExecuted { call_set_key });
        }

        fn retract_call_set(ref self: ContractState, call_set_key: felt252) {
            self.multi_owned.assert_only_owner();

            let caller = get_caller_address();
            let owner_index = self.multi_owned.get_owner_index(caller);

            // Can only retract if caller has signed.
            assert(
                self.call_set_approvers.read((call_set_key, owner_index)),
                Errors::NOT_SIGNED_BY_CALLER,
            );

            // Cannot change approvals of an expired call set.
            let status = self.get_call_set_status(call_set_key);
            assert(status != CallSetStatus::Expired, Errors::CALL_SET_EXPIRED);

            // Retract approval.
            self.call_set_approvers.write((call_set_key, owner_index), false);
            let n_approvals = self.call_set_n_approvals.read(call_set_key) - 1;
            self.call_set_n_approvals.write(call_set_key, n_approvals);

            // If dropped below threshold, clear allowed_time.
            if n_approvals == self.delay_start_threshold.read() - 1 {
                self.call_set_allowed_time.write(call_set_key, 0);
            }

            // If all approvals withdrawn, clear expiration to return to Unknown.
            if n_approvals == 0 {
                self.call_set_expiration.write(call_set_key, 0);
            }

            self
                .emit(
                    CallSetSignaturesUpdated {
                        call_set_key,
                        owner_index,
                        owner: caller,
                        change: ApprovalChange::SignatureRemoved,
                        n_approvals,
                    },
                );
        }

        fn get_call_set_status(self: @ContractState, call_set_key: felt252) -> CallSetStatus {
            let allowed_time = self.call_set_allowed_time.read(call_set_key);
            let n_approvals = self.call_set_n_approvals.read(call_set_key);

            if allowed_time == CALL_SET_EXECUTED {
                return CallSetStatus::Executed;
            }

            if self._is_expired(call_set_key) {
                return CallSetStatus::Expired;
            }

            if n_approvals == 0 {
                return CallSetStatus::Unknown;
            }

            // Has approvals but DelayStartThreshold was not reached (timer not started).
            if allowed_time == 0 {
                return CallSetStatus::Proposed;
            }

            let now = get_block_timestamp();
            let quorum = self.quorum_size.read();
            let timelock_elapsed = now >= allowed_time;
            let quorum_reached = n_approvals >= quorum;

            // Quorum reached, ExecutionDelay passed: CallSet is ready for execution.
            if timelock_elapsed && quorum_reached {
                return CallSetStatus::Ready;
            }

            if timelock_elapsed {
                // DelayStartThreshold reached, ExecutionDelay passed but Quorum not reached.
                return CallSetStatus::AwaitingQuorum;
            }

            // Quorum of signers reached but ExecutionDelay didn't elapse yet.
            if quorum_reached {
                return CallSetStatus::AwaitingTimelock;
            }

            // DelayStartThreshold reached (i.e. timer started).
            // But ExecutionDelay didn't elapse, and Quorum of signers was not reached.
            CallSetStatus::Pending
        }

        fn get_call_set_allowed_time(self: @ContractState, call_set_key: felt252) -> u64 {
            let status = self.get_call_set_status(call_set_key);
            match status {
                // Timer has started for these states; return the allowed_time.
                CallSetStatus::Pending | CallSetStatus::AwaitingTimelock |
                CallSetStatus::AwaitingQuorum |
                CallSetStatus::Ready => { self.call_set_allowed_time.read(call_set_key) },
                // Timer not started or call set not active.
                CallSetStatus::Unknown | CallSetStatus::Proposed | CallSetStatus::Executed |
                CallSetStatus::Expired => { Bounded::<u64>::MAX },
            }
        }

        fn get_execution_delay(self: @ContractState) -> u64 {
            self.execution_delay.read()
        }

        fn get_execution_expiration(self: @ContractState) -> u64 {
            self.execution_expiration.read()
        }
    }

    #[abi(embed_v0)]
    impl MultiExecutorImpl of IMultiExecutor<ContractState> {
        fn clear_expired_call_set(ref self: ContractState, call_set_key: felt252) {
            self.multi_owned.assert_only_owner();
            let status = self.get_call_set_status(call_set_key);
            assert(status == CallSetStatus::Expired, Errors::NOT_EXPIRED);
            self._clear_call_set(call_set_key, false);
            self.emit(ExpiredCallSetCleared { call_set_key });
        }

        fn get_call_set_expiration_time(self: @ContractState, call_set_key: felt252) -> u64 {
            self.call_set_expiration.read(call_set_key)
        }

        fn get_quorum_size(self: @ContractState) -> u32 {
            self.quorum_size.read()
        }

        fn get_delay_start_threshold(self: @ContractState) -> u32 {
            self.delay_start_threshold.read()
        }

        fn get_n_approvals(self: @ContractState, call_set_key: felt252) -> u32 {
            self.call_set_n_approvals.read(call_set_key)
        }

        fn has_owner_signed(
            self: @ContractState, call_set_key: felt252, owner: ContractAddress,
        ) -> bool {
            let owner_index = self.multi_owned.get_owner_index(owner);
            self.has_owner_index_signed(call_set_key, owner_index)
        }

        fn has_owner_index_signed(
            self: @ContractState, call_set_key: felt252, owner_index: u32,
        ) -> bool {
            self.call_set_approvers.read((call_set_key, owner_index))
        }
    }

    /// Private helper functions for call set management.
    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        /// Returns true if the call set has expired based on its expiration timestamp.
        fn _is_expired(self: @ContractState, call_set_key: felt252) -> bool {
            let expiration = self.call_set_expiration.read(call_set_key);
            if expiration == 0 {
                return false;
            }
            get_block_timestamp() > expiration
        }

        /// Clears all call set state (approvals, timers).
        /// If `executed` is true, marks as CALL_SET_EXECUTED; otherwise resets to 0.
        fn _clear_call_set(ref self: ContractState, call_set_key: felt252, executed: bool) {
            self._erase_approvals(call_set_key);
            let marked_state = if executed {
                CALL_SET_EXECUTED
            } else {
                0
            };
            self.call_set_allowed_time.write(call_set_key, marked_state);
            self.call_set_expiration.write(call_set_key, 0);
        }

        /// Clears all individual owner approvals and resets approval count to 0.
        fn _erase_approvals(ref self: ContractState, call_set_key: felt252) {
            let n_owners = self.multi_owned.get_n_owners();
            let mut i: u32 = 1;
            while i <= n_owners {
                self.call_set_approvers.write((call_set_key, i), false);
                i += 1;
            }
            self.call_set_n_approvals.write(call_set_key, 0);
        }
    }
}
