//! # Delayed Executor Package
//!
//! This package provides time-locked execution of batched contract calls (call sets) on Starknet.
//! It implements a security pattern where proposed transactions must wait through a delay period
//! before execution, giving stakeholders time to review and potentially veto malicious actions.
//!
//! ## Executors
//!
//! Two executor variants are provided:
//!
//! - **DelayedExecutor**: Single-owner executor using OpenZeppelin's two-step ownership.
//!   The owner submits call sets, waits for the delay, then executes.
//!
//! - **MultiExecutor**: Multi-owner (multisig) executor requiring a quorum of owners to approve.
//!   Uses the `MultiOwnedComponent` for ownership management. Implements both `IDelayedExecutor`
//!   (common functions) and `IMultiExecutor` (multi-owner specific functions).
//!
//! ## Key Concepts
//!
//! - **Call Set**: A batch of contract calls identified by a Poseidon hash of the serialized calls.
//! - **Execution Delay**: Minimum time between submission and execution eligibility.
//! - **Expiration**: Maximum time window during which a submitted call set can be executed.
//! - **Quorum**: (MultiExecutor) Minimum number of owner approvals required to execute.
//! - **Delay Start Threshold**: (MultiExecutor) Number of approvals needed to start the delay
//! timer.

/// Shared constants, types, events, errors, and helpers.
pub mod common;
/// Single-owner delayed executor contract.
pub mod delayed_executor;

/// Multi-owner delayed executor contract with quorum-based approval.
pub mod multi_executor;

/// Multi-owner management component with two-step ownership transfer.
pub mod multi_owned;
