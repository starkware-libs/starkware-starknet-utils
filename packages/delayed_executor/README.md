# Delayed Executor

Time-locked execution of batched contract calls ("call sets") on Starknet. Proposed
transactions must wait through a delay period before they can be executed, giving
stakeholders a window to review and, if needed, veto them.

This package provides two deployable contracts and one reusable component:

- **`DelayedExecutor`** — single-owner executor using OpenZeppelin's two-step ownership.
  The owner submits a call set, waits for the configured delay, then executes it.
- **`MultiExecutor`** — multi-owner (multisig) executor requiring a quorum of owner
  approvals. The delay timer starts once a configurable approval threshold is reached.
- **`MultiOwnedComponent`** — multi-owner management component with two-step ownership
  transfer and 1-based owner indexing, used by `MultiExecutor`.

## Key concepts

- **Call set** — a batch of calls identified by the Poseidon hash of its serialized calls.
- **Execution delay** — minimum time between submission and execution eligibility.
- **Expiration** — window after which a submitted call set can no longer be executed.
- **Quorum** — (`MultiExecutor`) minimum number of approvals required to execute.

## Usage

The basic `DelayedExecutor` flow — submit a call set, wait out the delay, then execute:

```cairo
// 1. Submit the batch of calls. Returns the call set key; status becomes Pending.
let call_set_key = executor.submit_calls(calls);

// 2. Once block_timestamp >= get_call_set_allowed_time(key), status becomes Ready.
let status = executor.get_call_set_status(call_set_key); // Ready

// 3. Any time before expiration, execute (or retract to cancel).
executor.exec_calls(calls);      // status -> Executed
// executor.retract_call_set(call_set_key); // status -> Unknown
```

`MultiExecutor` follows the same flow, except each owner calls `submit_calls` to add their
approval and the delay timer only starts once `delay_start_threshold` approvals are reached.

See [`docs/SPEC.md`](./docs/SPEC.md) for the full specification, state machines, and design notes.
