use core::num::traits::Zero;
use starknet::storage::{
    Mutable, MutableVecTrait, StoragePath, StoragePathMutableConversion, StoragePointerReadAccess,
    StoragePointerWriteAccess, Vec, VecTrait,
};
use starkware_utils::trace::errors::TraceErrors;

/// `Trace` struct, for checkpointing values as they change at different points in
/// time, and later looking up past values by block timestamp.
#[starknet::storage_node]
pub struct Trace {
    checkpoints: Vec<Checkpoint>,
}

// TODO: Implement StorePacking trait for Checkpoint.
#[derive(Copy, Drop, Serde, starknet::Store)]
struct Checkpoint {
    key: u64,
    value: u128,
}

pub impl CheckpointIntoPair of Into<Checkpoint, (u64, u128)> {
    fn into(self: Checkpoint) -> (u64, u128) {
        (self.key, self.value)
    }
}

#[generate_trait]
pub impl TraceImpl of TraceTrait {
    /// Retrieves the most recent checkpoint from the trace structure.
    ///
    /// # Returns
    /// A tuple containing:
    /// - `u64`: Timestamp/key of the latest checkpoint
    /// - `u128`: Value stored in the latest checkpoint
    ///
    /// # Panics
    /// If the trace structure is empty (no checkpoints exist)
    ///
    /// # Note
    /// This will return the last inserted checkpoint that maintains the structure's
    /// invariant of non-decreasing keys.
    fn latest(self: StoragePath<Trace>) -> Result<(u64, u128), TraceErrors> {
        let checkpoints = self.checkpoints;
        let len = checkpoints.len();
        if len == 0 {
            return Result::Err(TraceErrors::EMPTY_TRACE);
        }
        let checkpoint = checkpoints[len - 1].read();
        Result::Ok(checkpoint.into())
    }

    /// Retrieves the penultimate checkpoint from the trace structure.
    /// Penultimate checkpoint is the second last checkpoint in the trace.
    fn penultimate(self: StoragePath<Trace>) -> Result<(u64, u128), TraceErrors> {
        let checkpoints = self.checkpoints;
        let len = checkpoints.len();
        if len <= 1 {
            return Result::Err(TraceErrors::PENULTIMATE_NOT_EXIST);
        }
        let checkpoint = checkpoints[len - 2].read();
        Result::Ok(checkpoint.into())
    }

    /// Returns the antepenultimate checkpoint from the trace structure.
    /// Antepenultimate checkpoint is the third last checkpoint in the trace.
    fn antepenultimate(self: StoragePath<Trace>) -> Result<(u64, u128), TraceErrors> {
        let checkpoints = self.checkpoints;
        let len = checkpoints.len();
        if len <= 2 {
            return Result::Err(TraceErrors::ANTEPENULTIMATE_NOT_EXIST);
        }
        let checkpoint = checkpoints[len - 3].read();
        Result::Ok(checkpoint.into())
    }

    /// Returns the total number of checkpoints.
    fn length(self: StoragePath<Trace>) -> u64 {
        self.checkpoints.len()
    }

    /// Returns the checkpoint at the given position.
    /// # Returns
    /// A tuple containing:
    /// - `u64`: Timestamp/key of the checkpoint
    /// - `u128`: Value stored in the checkpoint
    ///
    /// # Panics
    /// If the position is out of bounds.
    fn at(self: StoragePath<Trace>, pos: u64) -> (u64, u128) {
        let checkpoints = self.checkpoints;
        let len = checkpoints.len();
        assert!(pos < len, "{}", TraceErrors::INDEX_OUT_OF_BOUNDS);
        let checkpoint = checkpoints[pos].read();
        (checkpoint.key, checkpoint.value)
    }

    /// Returns `true` is the trace is empty.
    fn is_empty(self: StoragePath<Trace>) -> bool {
        self.length().is_zero()
    }
}

#[generate_trait]
pub impl MutableTraceImpl of MutableTraceTrait {
    /// Inserts a (`key`, `value`) pair into a Trace so that it is stored as the checkpoint,
    /// either by inserting a new checkpoint, or by updating the last one.
    fn insert(self: StoragePath<Mutable<Trace>>, key: u64, value: u128) {
        let checkpoints = self.checkpoints;
        let len = checkpoints.len();
        if len.is_zero() {
            checkpoints.push(Checkpoint { key, value });
            return;
        }

        // Update or append new checkpoint.
        let mut last = checkpoints[len - 1].read();
        if last.key == key {
            last.value = value;
            checkpoints[len - 1].write(last);
        } else {
            // Checkpoint keys must be non-decreasing.
            assert!(last.key < key, "{}", TraceErrors::UNORDERED_INSERTION);
            checkpoints.push(Checkpoint { key, value });
        }
    }

    /// Retrieves the most recent checkpoint from the trace structure.
    ///
    /// # Returns
    /// A tuple containing:
    /// - `u64`: Timestamp/key of the latest checkpoint
    /// - `u128`: Value stored in the latest checkpoint
    ///
    /// # Panics
    /// If the trace structure is empty (no checkpoints exist)
    ///
    /// # Note
    /// This will return the last inserted checkpoint that maintains the structure's
    /// invariant of non-decreasing keys.
    fn latest(self: StoragePath<Mutable<Trace>>) -> Result<(u64, u128), TraceErrors> {
        self.as_non_mut().latest()
    }

    /// Retrieves the penultimate checkpoint from the trace structure.
    /// Penultimate checkpoint is the second last checkpoint in the trace.
    fn penultimate(self: StoragePath<Mutable<Trace>>) -> Result<(u64, u128), TraceErrors> {
        self.as_non_mut().penultimate()
    }

    /// Returns the antepenultimate checkpoint from the trace structure.
    /// Antepenultimate checkpoint is the third last checkpoint in the trace.
    fn antepenultimate(self: StoragePath<Mutable<Trace>>) -> Result<(u64, u128), TraceErrors> {
        self.as_non_mut().antepenultimate()
    }

    /// Returns the total number of checkpoints.
    fn length(self: StoragePath<Mutable<Trace>>) -> u64 {
        self.as_non_mut().length()
    }

    /// Returns the checkpoint at the given position.
    /// # Returns
    /// A tuple containing:
    /// - `u64`: Timestamp/key of the checkpoint
    /// - `u128`: Value stored in the checkpoint
    ///
    /// # Panics
    /// If the position is out of bounds.
    fn at(self: StoragePath<Mutable<Trace>>, pos: u64) -> (u64, u128) {
        self.as_non_mut().at(pos)
    }

    /// Returns `true` is the trace is empty.
    fn is_empty(self: StoragePath<Mutable<Trace>>) -> bool {
        self.as_non_mut().is_empty()
    }
}
