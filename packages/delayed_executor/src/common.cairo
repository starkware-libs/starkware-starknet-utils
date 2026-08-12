//! # Shared Module
//!
//! This module contains constants, enums, events, error definitions, and shared helpers
//! used across the delayed executor contracts and multi-owned component.

use core::poseidon::poseidon_hash_span;
use starknet::ContractAddress;
use starknet::account::Call;

// ============== Utility Functions ==============

/// Computes the call set key as the Poseidon hash of the serialized calls and a salt.
pub fn compute_call_set_key(calls: Span<Call>, salt: felt252) -> felt252 {
    let mut serialized: Array<felt252> = array![];
    calls.serialize(ref serialized);
    serialized.append(salt);
    poseidon_hash_span(serialized.span())
}

// ============== Constants ==============

/// Sentinel value stored in `call_set_allowed_time` to indicate a call set has been executed.
/// Using 1 instead of 0 allows distinguishing executed from unregistered call sets.
pub const CALL_SET_EXECUTED: u64 = 1;

/// Maximum allowed execution delay (28 days in seconds).
pub const MAX_DELAY: u64 = 2419200;

/// Minimum allowed expiration window (1 hour in seconds).
pub const MIN_EXPIRATION: u64 = 3600;

/// Maximum allowed expiration window (52 weeks in seconds).
pub const MAX_EXPIRATION: u64 = 31449600;

/// Maximum number of signers for multi-owner executor.
pub const MAX_N_SIGNERS: u32 = 63;

/// Maximum acceptance delay for ownership transfer (14 days in seconds).
pub const MAX_ACCEPTANCE_DELAY: u64 = 1209600;

/// Status of a call set.
///
/// For single-owner (DelayedExecutor): Unknown → Pending → Ready → Executed/Expired
/// For multi-owner (MultiExecutor): All states apply based on signature and timelock conditions.
#[derive(Drop, Copy, PartialEq, Debug, Serde)]
pub enum CallSetStatus {
    /// Call set has never been registered (no signatures).
    Unknown,
    /// (MultiExecutor only) Has signatures but below threshold; timer not started.
    Proposed,
    /// Timer started but not elapsed, and quorum not yet reached.
    /// For single-owner: Always in this state after registration until delay elapses.
    /// For multi-owner: Threshold reached but quorum not reached, waiting for time and/or
    /// signatures.
    Pending,
    /// (MultiExecutor only) Quorum reached but timelock not elapsed; waiting for time.
    AwaitingTimelock,
    /// (MultiExecutor only) Timelock elapsed but quorum not reached; waiting for signatures.
    AwaitingQuorum,
    /// Ready for execution: timelock elapsed, quorum reached (or single-owner), not expired.
    Ready,
    /// Call set has passed its expiration window.
    Expired,
    /// Call set has been executed.
    Executed,
}

// ============== DelayedExecutor Events ==============

/// Emitted when a call set is submitted (single-owner executor).
#[derive(Drop, starknet::Event)]
pub struct CallSetSubmitted {
    /// Poseidon hash identifying the call set.
    #[key]
    pub call_set_key: felt252,
    /// Timestamp after which the call set is allowed to be executed.
    pub allowed_time: u64,
}

/// Emitted when a call set is successfully executed.
#[derive(Drop, starknet::Event)]
pub struct CallSetExecuted {
    /// Poseidon hash identifying the executed call set.
    #[key]
    pub call_set_key: felt252,
}

/// Emitted when a call set is retracted/cancelled (single-owner executor).
#[derive(Drop, starknet::Event)]
pub struct CallSetRetracted {
    /// Poseidon hash identifying the retracted call set.
    #[key]
    pub call_set_key: felt252,
}

// ============== MultiOwned Events ==============

/// Emitted when an owner nominates a new address to replace them.
#[derive(Drop, starknet::Event)]
pub struct OwnershipNominated {
    /// Address of the owner initiating the transfer.
    #[key]
    pub current_owner: ContractAddress,
    /// Address nominated to become the new owner.
    #[key]
    pub new_owner: ContractAddress,
}

/// Emitted when a pending ownership nomination is cleared (cancelled or replaced).
#[derive(Drop, starknet::Event)]
pub struct OwnershipNominationCleared {
    /// Address of the current owner whose nomination was cleared.
    #[key]
    pub owner: ContractAddress,
    /// Address of the pending owner that was removed.
    #[key]
    pub revoked: ContractAddress,
}

/// Emitted when a nominated address accepts ownership.
#[derive(Drop, starknet::Event)]
pub struct OwnershipAccepted {
    /// Address of the owner being replaced.
    #[key]
    pub old_owner: ContractAddress,
    /// Address of the new owner.
    #[key]
    pub new_owner: ContractAddress,
}

/// Emitted when an owner is removed from the owner set.
#[derive(Drop, starknet::Event)]
pub struct OwnershipRevoked {
    /// Address of the revoked owner.
    #[key]
    pub revoked_owner: ContractAddress,
}

// ============== MultiExecutor Types ==============

/// Indicates whether an approval was added or removed.
#[derive(Drop, Copy, PartialEq, Debug, Serde)]
pub enum ApprovalChange {
    /// An owner added their signature/approval to the call set.
    SignatureAdded,
    /// An owner removed their signature/approval from the call set.
    SignatureRemoved,
}

// ============== MultiExecutor Events ==============

/// Emitted when an owner signs or unsigns a call set (multi-owner executor).
#[derive(Drop, starknet::Event)]
pub struct CallSetSignaturesUpdated {
    /// Poseidon hash identifying the call set.
    #[key]
    pub call_set_key: felt252,
    /// 1-based index of the owner in the owner set.
    pub owner_index: u32,
    /// Address of the owner who changed their approval.
    pub owner: ContractAddress,
    /// Whether approval was added or removed.
    pub change: ApprovalChange,
    /// Total number of approvals after this change.
    pub n_approvals: u32,
}

/// Emitted when the delay timer starts
#[derive(Drop, starknet::Event)]
pub struct CallSetTimerStarted {
    /// Poseidon hash identifying the call set.
    #[key]
    pub call_set_key: felt252,
    /// Timestamp after which the call set is allowed to be executed.
    pub allowed_time: u64,
    /// Deadline for call set execution. re-anchored to threshold crossing.
    pub expiration: u64,
}

/// Emitted when an expired call set is cleared to free storage.
#[derive(Drop, starknet::Event)]
pub struct ExpiredCallSetCleared {
    /// Poseidon hash identifying the cleared call set.
    #[key]
    pub call_set_key: felt252,
}

// ============== Errors ==============

/// Error constants used across the package.
pub mod Errors {
    // --- DelayedExecutor errors ---
    /// Execution delay exceeds MAX_DELAY.
    pub const DELAY_TOO_LONG: felt252 = 'DELAY_TOO_LONG';
    /// Expiration window is below MIN_EXPIRATION.
    pub const EXPIRATION_TOO_SHORT: felt252 = 'EXPIRATION_TOO_SHORT';
    /// Expiration window exceeds MAX_EXPIRATION.
    pub const EXPIRATION_TOO_LONG: felt252 = 'EXPIRATION_TOO_LONG';
    /// Expiration delay must exceed execution delay.
    pub const EXPIRATION_BELOW_DELAY: felt252 = 'EXPIRATION_BELOW_DELAY';
    /// Call set is not in Pending/Ready state (cannot be retracted).
    pub const CALL_SET_NOT_RETRACTABLE: felt252 = 'CALL_SET_NOT_RETRACTABLE';
    /// Call set is not in Ready state (cannot be executed).
    pub const CALL_SET_NOT_EXECUTABLE: felt252 = 'CALL_SET_NOT_EXECUTABLE';
    /// Reached a call set status that is unreachable for the single-owner executor.
    pub const UNREACHABLE_STATE: felt252 = 'UNREACHABLE_STATE';

    // --- MultiOwned errors ---
    /// Number of owners exceeds MAX_N_SIGNERS.
    pub const TOO_MANY_SIGNERS: felt252 = 'TOO_MANY_SIGNERS';
    /// Owner list is empty.
    pub const NO_OWNERS: felt252 = 'NO_OWNERS';
    /// Zero address provided as owner.
    pub const ZERO_OWNER_ADDRESS: felt252 = 'ZERO_OWNER_ADDRESS';
    /// Same address appears multiple times in owner list.
    pub const DUPLICATE_OWNER: felt252 = 'DUPLICATE_OWNER';
    /// Acceptance delay exceeds MAX_ACCEPTANCE_DELAY.
    pub const ACCEPTANCE_DELAY_TOO_LONG: felt252 = 'ACCEPTANCE_DELAY_TOO_LONG';
    /// Caller is not an owner.
    pub const ONLY_OWNER: felt252 = 'ONLY_OWNER';
    /// Address is already an owner.
    pub const ALREADY_OWNER: felt252 = 'ALREADY_OWNER';
    /// Address is already pending for another owner.
    pub const ALREADY_PENDING: felt252 = 'ALREADY_PENDING';
    /// Caller is not the pending owner.
    pub const NOT_PENDING_OWNER: felt252 = 'NOT_PENDING_OWNER';
    /// Acceptance delay has not elapsed yet.
    pub const CANNOT_ACCEPT_YET: felt252 = 'CANNOT_ACCEPT_YET';
    /// Owner index map and reverse map disagree (internal invariant violation).
    pub const OWNER_MAP_INCONSISTENCY: felt252 = 'OWNER_MAP_INCONSISTENCY';
    /// Nominee/owner pending pointers disagree (internal invariant violation).
    pub const INCONSISTENT_REPLACEMENT: felt252 = 'INCONSISTENT_REPLACEMENT';
    /// Owner being replaced is no longer an owner.
    pub const REPLACED_NOT_OWNER: felt252 = 'REPLACED_NOT_OWNER';
    /// Owner index is zero (invalid; indices are 1-based).
    pub const INVALID_OWNER_INDEX: felt252 = 'INVALID_OWNER_INDEX';
    /// The executor's own address may never hold an owner slot.
    pub const SELF_AS_OWNER: felt252 = 'SELF_AS_OWNER';

    // --- MultiExecutor errors ---
    /// Quorum size is zero.
    pub const EMPTY_QUORUM: felt252 = 'EMPTY_QUORUM';
    /// Quorum size exceeds number of owners.
    pub const QUORUM_TOO_BIG: felt252 = 'QUORUM_TOO_BIG';
    /// Delay start threshold is invalid (must be 1..=quorum).
    pub const ILLEGAL_THRESHOLD: felt252 = 'ILLEGAL_THRESHOLD';
    /// Call set has expired (cannot sign or modify).
    pub const CALL_SET_EXPIRED: felt252 = 'CALL_SET_EXPIRED';
    /// Caller has not signed this call set.
    pub const NOT_SIGNED_BY_CALLER: felt252 = 'NOT_SIGNED_BY_CALLER';
    /// Call set is not expired (cannot clear).
    pub const NOT_EXPIRED: felt252 = 'NOT_EXPIRED';
    /// Not enough approvals to execute.
    pub const QUORUM_NOT_REACHED: felt252 = 'QUORUM_NOT_REACHED';
}
