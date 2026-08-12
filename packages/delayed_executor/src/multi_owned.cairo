//! # Multi-Owner Component
//!
//! A component for managing multiple owners with two-step ownership transfer.
//! Used by `MultiExecutor` to implement quorum-based multi-signature execution.
//!
//! ## Features
//!
//! - Fixed number of owner slots (set at initialization).
//! - Two-step ownership transfer: nomination by current owner, acceptance by nominee.
//! - Configurable acceptance delay to prevent immediate transfers.
//! - 1-based indexing for owners (index 0 means not an owner).
//!
//! ## Transfer Flow
//!
//! 1. Current owner calls `transfer_ownership(new_address)` to nominate a replacement.
//! 2. After `owner_acceptance_delay` elapses, the nominee calls `accept_ownership()`.
//! 3. The nominee takes over the owner slot, maintaining the same index.

use starknet::ContractAddress;

/// Interface for multi-owner management.
#[starknet::interface]
pub trait IMultiOwned<TState> {
    /// Returns true if the account is a current owner.
    fn is_owner(self: @TState, account: ContractAddress) -> bool;

    /// Returns the 1-based owner index, or 0 if not an owner.
    fn get_owner_index(self: @TState, account: ContractAddress) -> u32;

    /// Returns the owner address at the given 1-based index.
    fn get_owner_by_index(self: @TState, index: u32) -> ContractAddress;

    /// Returns the total number of owner slots.
    fn get_n_owners(self: @TState) -> u32;

    /// Returns the configured acceptance delay in seconds.
    fn get_owner_acceptance_delay(self: @TState) -> u64;

    /// Returns the pending nominee for a current owner, or zero if none.
    fn get_pending_owner(self: @TState, current_owner: ContractAddress) -> ContractAddress;

    /// Returns the timestamp when a pending owner can accept ownership, or 0 if not pending.
    fn get_acceptance_time(self: @TState, pending_owner: ContractAddress) -> u64;

    /// Nominates a new address to replace the caller's ownership slot.
    /// Passing zero address clears any pending nomination.
    fn transfer_ownership(ref self: TState, new_owner: ContractAddress);

    /// Accepts a pending ownership nomination (called by the nominee).
    fn accept_ownership(ref self: TState);
}

/// Multi-owner component implementing two-step ownership management.
#[starknet::component]
pub mod MultiOwnedComponent {
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use starkware_delayed_executor::common::{
        Errors, MAX_ACCEPTANCE_DELAY, MAX_N_SIGNERS, OwnershipAccepted, OwnershipNominated,
        OwnershipNominationCleared, OwnershipRevoked,
    };

    #[storage]
    pub struct Storage {
        /// Total number of owner slots.
        n_owners: u32,
        /// Required delay (seconds) between nomination and acceptance.
        owner_acceptance_delay: u64,
        /// Maps owner address to 1-based index (0 = not owner).
        owner_to_index: Map<ContractAddress, u32>,
        /// Maps 1-based index to owner address.
        index_to_owner: Map<u32, ContractAddress>,
        /// Maps pending nominee to the current owner they will replace.
        pending_to_current: Map<ContractAddress, ContractAddress>,
        /// Maps current owner to their nominated replacement.
        current_to_pending: Map<ContractAddress, ContractAddress>,
        /// Maps pending owner to the timestamp when they can accept.
        acceptance_time: Map<ContractAddress, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnershipNominated: OwnershipNominated,
        OwnershipNominationCleared: OwnershipNominationCleared,
        OwnershipAccepted: OwnershipAccepted,
        OwnershipRevoked: OwnershipRevoked,
    }

    /// Internal functions for component initialization and access control.
    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Initializes the multi-owner component with a set of owners.
        ///
        /// # Arguments
        /// * `owners` - Initial owner addresses (1 to MAX_N_SIGNERS).
        /// * `owner_acceptance_delay` - Time in seconds before a nominee can accept.
        ///
        /// # Panics
        /// - If owners list is empty or exceeds MAX_N_SIGNERS.
        /// - If any owner is the zero address.
        /// - If duplicate owners are provided.
        fn initializer(
            ref self: ComponentState<TContractState>,
            owners: Span<ContractAddress>,
            owner_acceptance_delay: u64,
        ) {
            let n = owners.len();
            assert(n > 0, Errors::NO_OWNERS);
            assert(n <= MAX_N_SIGNERS, Errors::TOO_MANY_SIGNERS);
            assert(
                owner_acceptance_delay <= MAX_ACCEPTANCE_DELAY, Errors::ACCEPTANCE_DELAY_TOO_LONG,
            );

            self.n_owners.write(n);
            self.owner_acceptance_delay.write(owner_acceptance_delay);

            let mut i: u32 = 0;
            while i < n {
                let owner = *owners.at(i);
                assert(owner.is_non_zero(), Errors::ZERO_OWNER_ADDRESS);
                assert(owner != get_contract_address(), Errors::SELF_AS_OWNER);
                assert(self.owner_to_index.read(owner) == 0, Errors::DUPLICATE_OWNER);

                let index = i + 1; // 1-based indexing.
                self.owner_to_index.write(owner, index);
                self.index_to_owner.write(index, owner);
                self.emit(OwnershipAccepted { old_owner: Zero::zero(), new_owner: owner });

                i += 1;
            };
        }

        /// Asserts that the caller is a current owner.
        fn assert_only_owner(self: @ComponentState<TContractState>) {
            let caller = get_caller_address();
            assert(self.is_owner(caller), Errors::ONLY_OWNER);
        }
    }

    #[embeddable_as(MultiOwnedImpl)]
    impl MultiOwned<
        TContractState, +HasComponent<TContractState>,
    > of super::IMultiOwned<ComponentState<TContractState>> {
        fn is_owner(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            let owner_index = self.owner_to_index.read(account);
            if owner_index == 0 {
                return false;
            }
            // Sanity check: verify consistency between maps.
            let stored_owner = self.index_to_owner.read(owner_index);
            assert(stored_owner == account, Errors::OWNER_MAP_INCONSISTENCY);
            true
        }

        fn get_owner_index(self: @ComponentState<TContractState>, account: ContractAddress) -> u32 {
            self.owner_to_index.read(account)
        }

        fn get_owner_by_index(
            self: @ComponentState<TContractState>, index: u32,
        ) -> ContractAddress {
            self.index_to_owner.read(index)
        }

        fn get_n_owners(self: @ComponentState<TContractState>) -> u32 {
            self.n_owners.read()
        }

        fn get_owner_acceptance_delay(self: @ComponentState<TContractState>) -> u64 {
            self.owner_acceptance_delay.read()
        }

        fn get_pending_owner(
            self: @ComponentState<TContractState>, current_owner: ContractAddress,
        ) -> ContractAddress {
            self.current_to_pending.read(current_owner)
        }

        fn get_acceptance_time(
            self: @ComponentState<TContractState>, pending_owner: ContractAddress,
        ) -> u64 {
            self.acceptance_time.read(pending_owner)
        }

        fn transfer_ownership(
            ref self: ComponentState<TContractState>, new_owner: ContractAddress,
        ) {
            let current_owner = get_caller_address();
            assert(self.is_owner(current_owner), Errors::ONLY_OWNER);
            assert(!self.is_owner(new_owner), Errors::ALREADY_OWNER);
            assert(new_owner != get_contract_address(), Errors::SELF_AS_OWNER);

            // new_owner must not be pending for this or another owner.
            assert(self.pending_to_current.read(new_owner).is_zero(), Errors::ALREADY_PENDING);

            // Clear any existing pending nomination for current_owner.
            self._clear_pending_owner(current_owner);

            if new_owner.is_non_zero() {
                self.pending_to_current.write(new_owner, current_owner);
                let acceptance_time_val = get_block_timestamp()
                    + self.owner_acceptance_delay.read();
                self.acceptance_time.write(new_owner, acceptance_time_val);
                self.current_to_pending.write(current_owner, new_owner);
                self.emit(OwnershipNominated { current_owner, new_owner });
            }
        }

        fn accept_ownership(ref self: ComponentState<TContractState>) {
            let new_owner = get_caller_address();
            let replaced_owner = self.pending_to_current.read(new_owner);

            assert(replaced_owner.is_non_zero(), Errors::NOT_PENDING_OWNER);

            // Sanity.
            assert(
                self.current_to_pending.read(replaced_owner) == new_owner,
                Errors::INCONSISTENT_REPLACEMENT,
            );
            assert(self.is_owner(replaced_owner), Errors::REPLACED_NOT_OWNER);
            assert(!self.is_owner(new_owner), Errors::ALREADY_OWNER);

            assert(
                get_block_timestamp() >= self.acceptance_time.read(new_owner),
                Errors::CANNOT_ACCEPT_YET,
            );

            self._accept_ownership(new_owner, replaced_owner);
        }
    }

    /// Private helper functions for ownership management.
    #[generate_trait]
    impl PrivateImpl<
        TContractState, +HasComponent<TContractState>,
    > of PrivateTrait<TContractState> {
        /// Clears any pending nomination for the given owner.
        /// Emits OwnershipNominationCleared if there was a pending nomination.
        fn _clear_pending_owner(ref self: ComponentState<TContractState>, owner: ContractAddress) {
            let pending = self.current_to_pending.read(owner);
            if pending.is_zero() {
                return;
            }

            self.current_to_pending.write(owner, Zero::zero());
            self.pending_to_current.write(pending, Zero::zero());
            self.acceptance_time.write(pending, 0);
            self.emit(OwnershipNominationCleared { owner, revoked: pending });
        }

        /// Completes ownership transfer: replaces old owner with new owner at the same index.
        fn _accept_ownership(
            ref self: ComponentState<TContractState>,
            new_owner: ContractAddress,
            replaced_owner: ContractAddress,
        ) {
            let owner_index = self.owner_to_index.read(replaced_owner);

            // Sanity.
            assert(owner_index != 0, Errors::INVALID_OWNER_INDEX);
            assert(new_owner.is_non_zero(), Errors::ZERO_OWNER_ADDRESS);

            self._clear_pending_owner(replaced_owner);

            self.owner_to_index.write(new_owner, owner_index);
            self.owner_to_index.write(replaced_owner, 0);
            self.index_to_owner.write(owner_index, new_owner);

            self.emit(OwnershipAccepted { old_owner: replaced_owner, new_owner });
            self.emit(OwnershipRevoked { revoked_owner: replaced_owner });
        }
    }
}
