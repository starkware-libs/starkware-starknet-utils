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

See [`docs/`](./docs) for the full specification and design notes.
