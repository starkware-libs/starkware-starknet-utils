use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_block_timestamp, cheat_caller_address, declare, spy_events,
};
use starknet::ContractAddress;
use starkware_delayed_executor::common::{
    MAX_ACCEPTANCE_DELAY, MAX_N_SIGNERS, OwnershipAccepted, OwnershipNominated,
    OwnershipNominationCleared, OwnershipRevoked,
};
use starkware_delayed_executor::multi_owned::{IMultiOwnedDispatcher, IMultiOwnedDispatcherTrait};
use crate::test_helpers::addr;

const OWNER1: felt252 = 0x1111;
const OWNER2: felt252 = 0x2222;
const OWNER3: felt252 = 0x3333;
const NEW_OWNER: felt252 = 0x4444;
const ACCEPTANCE_DELAY: u64 = 3600; // 1 hour.
const INITIAL_TIMESTAMP: u64 = 10000;

fn deploy_multi_owned(
    owners: Span<ContractAddress>, owner_acceptance_delay: u64,
) -> IMultiOwnedDispatcher {
    let contract = declare("MockMultiOwned").unwrap().contract_class();
    let mut constructor_args: Array<felt252> = array![];
    Serde::serialize(@owners, ref constructor_args);
    Serde::serialize(@owner_acceptance_delay, ref constructor_args);
    let (address, _) = contract.deploy(@constructor_args).unwrap();
    IMultiOwnedDispatcher { contract_address: address }
}


fn deploy_with_three_owners() -> IMultiOwnedDispatcher {
    let owners = array![addr(OWNER1), addr(OWNER2), addr(OWNER3)].span();
    deploy_multi_owned(owners, ACCEPTANCE_DELAY)
}

// ============== Initialization Tests ==============

#[test]
fn test_initialization() {
    let contract = deploy_with_three_owners();

    assert_eq!(contract.get_n_owners(), 3);
    assert_eq!(contract.get_owner_acceptance_delay(), ACCEPTANCE_DELAY);

    assert!(contract.is_owner(addr(OWNER1)));
    assert!(contract.is_owner(addr(OWNER2)));
    assert!(contract.is_owner(addr(OWNER3)));
    assert!(!contract.is_owner(addr(NEW_OWNER)));

    assert_eq!(contract.get_owner_index(addr(OWNER1)), 1);
    assert_eq!(contract.get_owner_index(addr(OWNER2)), 2);
    assert_eq!(contract.get_owner_index(addr(OWNER3)), 3);
    assert_eq!(contract.get_owner_index(addr(NEW_OWNER)), 0);

    assert_eq!(contract.get_owner_by_index(1), addr(OWNER1));
    assert_eq!(contract.get_owner_by_index(2), addr(OWNER2));
    assert_eq!(contract.get_owner_by_index(3), addr(OWNER3));
}

#[test]
fn test_single_owner_initialization() {
    let owners = array![addr(OWNER1)].span();
    let contract = deploy_multi_owned(owners, 0);

    assert_eq!(contract.get_n_owners(), 1);
    assert!(contract.is_owner(addr(OWNER1)));
    assert_eq!(contract.get_owner_index(addr(OWNER1)), 1);
}

#[test]
fn test_max_owners_boundary() {
    let mut owners: Array<ContractAddress> = array![];
    let mut i: u32 = 0;
    while i < MAX_N_SIGNERS {
        owners.append(addr((i + 1).into()));
        i += 1;
    }
    let contract = deploy_multi_owned(owners.span(), ACCEPTANCE_DELAY);

    assert_eq!(contract.get_n_owners(), MAX_N_SIGNERS);
    assert!(contract.is_owner(addr(1)));
    assert!(contract.is_owner(addr(MAX_N_SIGNERS.into())));
}

#[test]
fn test_max_acceptance_delay_boundary() {
    let owners = array![addr(OWNER1)].span();
    let contract = deploy_multi_owned(owners, MAX_ACCEPTANCE_DELAY);

    assert_eq!(contract.get_owner_acceptance_delay(), MAX_ACCEPTANCE_DELAY);
}

// ============== View Function Edge Cases ==============

#[test]
fn test_get_owner_by_index_zero_returns_zero() {
    let contract = deploy_with_three_owners();
    let zero = addr(0);

    assert_eq!(contract.get_owner_by_index(0), zero);
}

#[test]
fn test_get_owner_by_index_out_of_range_returns_zero() {
    let contract = deploy_with_three_owners();
    let zero = addr(0);

    assert_eq!(contract.get_owner_by_index(4), zero);
    assert_eq!(contract.get_owner_by_index(100), zero);
}

#[test]
fn test_get_pending_owner_for_non_owner_returns_zero() {
    let contract = deploy_with_three_owners();
    let zero = addr(0);

    assert_eq!(contract.get_pending_owner(addr(NEW_OWNER)), zero);
}

#[test]
fn test_get_acceptance_time_for_non_pending_returns_zero() {
    let contract = deploy_with_three_owners();

    assert_eq!(contract.get_acceptance_time(addr(NEW_OWNER)), 0);
    assert_eq!(contract.get_acceptance_time(addr(OWNER1)), 0);
}

// ============== Transfer Ownership Tests ==============

#[test]
fn test_transfer_ownership_nomination() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    contract.transfer_ownership(addr(NEW_OWNER));

    assert_eq!(contract.get_pending_owner(addr(OWNER1)), addr(NEW_OWNER));
    assert_eq!(contract.get_acceptance_time(addr(NEW_OWNER)), INITIAL_TIMESTAMP + ACCEPTANCE_DELAY);
}

#[test]
fn test_transfer_to_zero_clears_pending() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    // Nominate new owner.
    contract.transfer_ownership(addr(NEW_OWNER));
    assert_eq!(contract.get_pending_owner(addr(OWNER1)), addr(NEW_OWNER));

    // Clear by transferring to zero.
    let zero = addr(0);
    contract.transfer_ownership(zero);
    assert_eq!(contract.get_pending_owner(addr(OWNER1)), zero);
    assert_eq!(contract.get_acceptance_time(addr(NEW_OWNER)), 0);
}

#[test]
fn test_re_nomination_clears_previous() {
    let contract = deploy_with_three_owners();
    let other_new: felt252 = 0x5555;

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    // First nomination.
    contract.transfer_ownership(addr(NEW_OWNER));
    assert_eq!(contract.get_pending_owner(addr(OWNER1)), addr(NEW_OWNER));

    // Re-nominate different address.
    contract.transfer_ownership(addr(other_new));
    assert_eq!(contract.get_pending_owner(addr(OWNER1)), addr(other_new));
    // Old pending should be cleared.
    assert_eq!(contract.get_acceptance_time(addr(NEW_OWNER)), 0);
}

#[test]
#[should_panic(expected: 'ONLY_OWNER')]
fn test_transfer_non_owner_fails() {
    let contract = deploy_with_three_owners();

    cheat_caller_address(contract.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(0x9999));
}

#[test]
#[should_panic(expected: 'ALREADY_OWNER')]
fn test_transfer_to_existing_owner_fails() {
    let contract = deploy_with_three_owners();

    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(OWNER2));
}

#[test]
#[should_panic(expected: 'ALREADY_OWNER')]
fn test_transfer_to_self_fails() {
    let contract = deploy_with_three_owners();

    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(OWNER1));
}

#[test]
#[should_panic(expected: 'ALREADY_PENDING')]
fn test_transfer_to_already_pending_fails() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    // OWNER1 nominates NEW_OWNER.
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(NEW_OWNER));

    // OWNER2 tries to nominate same NEW_OWNER.
    cheat_caller_address(contract.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(NEW_OWNER));
}

// ============== Accept Ownership Tests ==============

#[test]
fn test_accept_ownership_success() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    contract.transfer_ownership(addr(NEW_OWNER));

    // Advance past acceptance delay.
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );

    // Accept as new owner.
    cheat_caller_address(contract.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    contract.accept_ownership();

    // Verify ownership transferred.
    assert!(contract.is_owner(addr(NEW_OWNER)));
    assert!(!contract.is_owner(addr(OWNER1)));
    assert_eq!(contract.get_owner_index(addr(NEW_OWNER)), 1); // Inherited index.
    assert_eq!(contract.get_owner_index(addr(OWNER1)), 0);
    assert_eq!(contract.get_owner_by_index(1), addr(NEW_OWNER));

    // Pending state cleared.
    let zero = addr(0);
    assert_eq!(contract.get_pending_owner(addr(OWNER1)), zero);
}

#[test]
fn test_accept_with_zero_delay() {
    let owners = array![addr(OWNER1)].span();
    let contract = deploy_multi_owned(owners, 0);

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    contract.transfer_ownership(addr(NEW_OWNER));

    // Can accept immediately with zero delay.
    cheat_caller_address(contract.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    contract.accept_ownership();

    assert!(contract.is_owner(addr(NEW_OWNER)));
    assert!(!contract.is_owner(addr(OWNER1)));
}

#[test]
fn test_accept_at_exact_delay_boundary() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    contract.transfer_ownership(addr(NEW_OWNER));

    // Accept at exactly acceptance_time (>= check should pass).
    let acceptance_time = contract.get_acceptance_time(addr(NEW_OWNER));
    cheat_block_timestamp(contract.contract_address, acceptance_time, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    contract.accept_ownership();

    assert!(contract.is_owner(addr(NEW_OWNER)));
    assert!(!contract.is_owner(addr(OWNER1)));
}

#[test]
#[should_panic(expected: 'NOT_PENDING_OWNER')]
fn test_accept_not_pending_fails() {
    let contract = deploy_with_three_owners();

    cheat_caller_address(contract.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    contract.accept_ownership();
}

#[test]
#[should_panic(expected: 'CANNOT_ACCEPT_YET')]
fn test_accept_before_delay_fails() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    contract.transfer_ownership(addr(NEW_OWNER));

    // Try to accept before delay elapsed.
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY - 1, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    contract.accept_ownership();
}

// ============== Index Preservation Tests ==============

#[test]
fn test_index_preserved_on_replacement() {
    let contract = deploy_with_three_owners();
    let new_owner2: felt252 = 0x5555;

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    // OWNER2 (index 2) nominates new_owner2.
    cheat_caller_address(contract.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(new_owner2));

    // Accept.
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(new_owner2), CheatSpan::Indefinite);
    contract.accept_ownership();

    // new_owner2 should have index 2.
    assert_eq!(contract.get_owner_index(addr(new_owner2)), 2);
    assert_eq!(contract.get_owner_by_index(2), addr(new_owner2));

    // Other owners unchanged.
    assert!(contract.is_owner(addr(OWNER1)));
    assert!(contract.is_owner(addr(OWNER3)));
    assert_eq!(contract.get_owner_index(addr(OWNER1)), 1);
    assert_eq!(contract.get_owner_index(addr(OWNER3)), 3);
}

// ============== Event Emission Tests ==============

#[test]
fn test_transfer_ownership_emits_nominated_event() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    let mut spy = spy_events();
    contract.transfer_ownership(addr(NEW_OWNER));

    spy
        .assert_emitted(
            @array![
                (
                    contract.contract_address,
                    crate::mocks::MockMultiOwned::Event::MultiOwnedEvent(
                        starkware_delayed_executor::multi_owned::MultiOwnedComponent::Event::OwnershipNominated(
                            OwnershipNominated {
                                current_owner: addr(OWNER1), new_owner: addr(NEW_OWNER),
                            },
                        ),
                    ),
                ),
            ],
        );
}

#[test]
fn test_transfer_to_zero_emits_cleared_event() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    contract.transfer_ownership(addr(NEW_OWNER));

    let mut spy = spy_events();
    let zero = addr(0);
    contract.transfer_ownership(zero);

    spy
        .assert_emitted(
            @array![
                (
                    contract.contract_address,
                    crate::mocks::MockMultiOwned::Event::MultiOwnedEvent(
                        starkware_delayed_executor::multi_owned::MultiOwnedComponent::Event::OwnershipNominationCleared(
                            OwnershipNominationCleared {
                                owner: addr(OWNER1), revoked: addr(NEW_OWNER),
                            },
                        ),
                    ),
                ),
            ],
        );
}

#[test]
fn test_accept_ownership_emits_accepted_and_revoked_events() {
    let contract = deploy_with_three_owners();

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);

    contract.transfer_ownership(addr(NEW_OWNER));

    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);

    let mut spy = spy_events();
    contract.accept_ownership();

    spy
        .assert_emitted(
            @array![
                (
                    contract.contract_address,
                    crate::mocks::MockMultiOwned::Event::MultiOwnedEvent(
                        starkware_delayed_executor::multi_owned::MultiOwnedComponent::Event::OwnershipAccepted(
                            OwnershipAccepted {
                                old_owner: addr(OWNER1), new_owner: addr(NEW_OWNER),
                            },
                        ),
                    ),
                ),
            ],
        );

    spy
        .assert_emitted(
            @array![
                (
                    contract.contract_address,
                    crate::mocks::MockMultiOwned::Event::MultiOwnedEvent(
                        starkware_delayed_executor::multi_owned::MultiOwnedComponent::Event::OwnershipRevoked(
                            OwnershipRevoked { revoked_owner: addr(OWNER1) },
                        ),
                    ),
                ),
            ],
        );
}

// ============== Multi-Step Flow Tests ==============

#[test]
fn test_owner_reinstated_on_different_index() {
    let contract = deploy_with_three_owners();
    let temp_owner: felt252 = 0x5555;

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    // OWNER1 (index 1) transfers to temp_owner.
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(temp_owner));

    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(temp_owner), CheatSpan::Indefinite);
    contract.accept_ownership();

    assert!(!contract.is_owner(addr(OWNER1)));
    assert!(contract.is_owner(addr(temp_owner)));
    assert_eq!(contract.get_owner_index(addr(temp_owner)), 1);

    // Now OWNER3 (index 3) transfers to OWNER1 (reinstating OWNER1 at index 3).
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY + 1, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(OWNER3), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(OWNER1));

    cheat_block_timestamp(
        contract.contract_address,
        INITIAL_TIMESTAMP + 2 * ACCEPTANCE_DELAY + 1,
        CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.accept_ownership();

    // OWNER1 is back but now at index 3 (OWNER3's old slot).
    assert!(contract.is_owner(addr(OWNER1)));
    assert!(!contract.is_owner(addr(OWNER3)));
    assert_eq!(contract.get_owner_index(addr(OWNER1)), 3);
    assert_eq!(contract.get_owner_by_index(3), addr(OWNER1));

    // Other owners still correct.
    assert_eq!(contract.get_owner_index(addr(temp_owner)), 1);
    assert_eq!(contract.get_owner_index(addr(OWNER2)), 2);
    assert_eq!(contract.get_n_owners(), 3);
}

#[test]
fn test_owner_replaced_and_back_in_same_slot() {
    let contract = deploy_with_three_owners();
    let temp_owner: felt252 = 0x5555;

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    // OWNER2 (index 2) transfers to temp_owner.
    cheat_caller_address(contract.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(temp_owner));

    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(temp_owner), CheatSpan::Indefinite);
    contract.accept_ownership();

    assert!(!contract.is_owner(addr(OWNER2)));
    assert!(contract.is_owner(addr(temp_owner)));
    assert_eq!(contract.get_owner_index(addr(temp_owner)), 2);

    // temp_owner (now at index 2) transfers back to OWNER2.
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY + 1, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(temp_owner), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(OWNER2));

    cheat_block_timestamp(
        contract.contract_address,
        INITIAL_TIMESTAMP + 2 * ACCEPTANCE_DELAY + 1,
        CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    contract.accept_ownership();

    // OWNER2 is back at index 2.
    assert!(contract.is_owner(addr(OWNER2)));
    assert!(!contract.is_owner(addr(temp_owner)));
    assert_eq!(contract.get_owner_index(addr(OWNER2)), 2);
    assert_eq!(contract.get_owner_by_index(2), addr(OWNER2));

    // All original owners restored.
    assert!(contract.is_owner(addr(OWNER1)));
    assert!(contract.is_owner(addr(OWNER2)));
    assert!(contract.is_owner(addr(OWNER3)));
    assert_eq!(contract.get_n_owners(), 3);
}

#[test]
fn test_owner_index_swap() {
    let contract = deploy_with_three_owners();
    let temp_a: felt252 = 0x5555;
    let temp_b: felt252 = 0x6666;

    // Initial state: OWNER1=index1, OWNER2=index2, OWNER3=index3.
    assert_eq!(contract.get_owner_index(addr(OWNER1)), 1);
    assert_eq!(contract.get_owner_index(addr(OWNER2)), 2);

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    // Step 1: OWNER1 transfers to temp_a (temp_a gets index 1).
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(temp_a));

    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(temp_a), CheatSpan::Indefinite);
    contract.accept_ownership();

    // Step 2: OWNER2 transfers to temp_b (temp_b gets index 2).
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY + 1, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(temp_b));

    cheat_block_timestamp(
        contract.contract_address,
        INITIAL_TIMESTAMP + 2 * ACCEPTANCE_DELAY + 1,
        CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(temp_b), CheatSpan::Indefinite);
    contract.accept_ownership();

    // Step 3: temp_a (index 1) transfers to OWNER2 (OWNER2 gets index 1).
    cheat_block_timestamp(
        contract.contract_address,
        INITIAL_TIMESTAMP + 2 * ACCEPTANCE_DELAY + 2,
        CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(temp_a), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(OWNER2));

    cheat_block_timestamp(
        contract.contract_address,
        INITIAL_TIMESTAMP + 3 * ACCEPTANCE_DELAY + 2,
        CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    contract.accept_ownership();

    // Step 4: temp_b (index 2) transfers to OWNER1 (OWNER1 gets index 2).
    cheat_block_timestamp(
        contract.contract_address,
        INITIAL_TIMESTAMP + 3 * ACCEPTANCE_DELAY + 3,
        CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(temp_b), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(OWNER1));

    cheat_block_timestamp(
        contract.contract_address,
        INITIAL_TIMESTAMP + 4 * ACCEPTANCE_DELAY + 3,
        CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.accept_ownership();

    // Final state: indices swapped - OWNER1=index2, OWNER2=index1.
    assert_eq!(contract.get_owner_index(addr(OWNER1)), 2);
    assert_eq!(contract.get_owner_index(addr(OWNER2)), 1);
    assert_eq!(contract.get_owner_by_index(1), addr(OWNER2));
    assert_eq!(contract.get_owner_by_index(2), addr(OWNER1));

    // OWNER3 unchanged.
    assert_eq!(contract.get_owner_index(addr(OWNER3)), 3);
    assert!(contract.is_owner(addr(OWNER1)));
    assert!(contract.is_owner(addr(OWNER2)));
    assert!(contract.is_owner(addr(OWNER3)));
    assert_eq!(contract.get_n_owners(), 3);
}

#[test]
fn test_sequential_ownership_transfer() {
    let contract = deploy_with_three_owners();
    let owner_b: felt252 = 0x5555;
    let owner_c: felt252 = 0x6666;

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    // OWNER1 (A) nominates B.
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(owner_b));

    // B accepts.
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(owner_b), CheatSpan::Indefinite);
    contract.accept_ownership();

    assert!(contract.is_owner(addr(owner_b)));
    assert!(!contract.is_owner(addr(OWNER1)));

    // B nominates C.
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY + 1, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(owner_b), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(owner_c));

    // C accepts.
    cheat_block_timestamp(
        contract.contract_address,
        INITIAL_TIMESTAMP + 2 * ACCEPTANCE_DELAY + 1,
        CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(owner_c), CheatSpan::Indefinite);
    contract.accept_ownership();

    assert!(contract.is_owner(addr(owner_c)));
    assert!(!contract.is_owner(addr(owner_b)));
    assert_eq!(contract.get_owner_index(addr(owner_c)), 1); // Preserved from original OWNER1 slot.
}

#[test]
fn test_n_owners_constant_after_transfers() {
    let contract = deploy_with_three_owners();

    assert_eq!(contract.get_n_owners(), 3);

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    // Transfer OWNER1 -> NEW_OWNER.
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(NEW_OWNER));

    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );
    cheat_caller_address(contract.contract_address, addr(NEW_OWNER), CheatSpan::Indefinite);
    contract.accept_ownership();

    // n_owners should remain 3 (replacement, not addition).
    assert_eq!(contract.get_n_owners(), 3);
}

#[test]
fn test_multiple_simultaneous_nominations() {
    let contract = deploy_with_three_owners();
    let new_owner1: felt252 = 0x5555;
    let new_owner2: felt252 = 0x6666;

    cheat_block_timestamp(contract.contract_address, INITIAL_TIMESTAMP, CheatSpan::Indefinite);

    // OWNER1 nominates new_owner1.
    cheat_caller_address(contract.contract_address, addr(OWNER1), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(new_owner1));

    // OWNER2 nominates new_owner2.
    cheat_caller_address(contract.contract_address, addr(OWNER2), CheatSpan::Indefinite);
    contract.transfer_ownership(addr(new_owner2));

    // Both nominations are pending.
    assert_eq!(contract.get_pending_owner(addr(OWNER1)), addr(new_owner1));
    assert_eq!(contract.get_pending_owner(addr(OWNER2)), addr(new_owner2));

    // Both can accept.
    cheat_block_timestamp(
        contract.contract_address, INITIAL_TIMESTAMP + ACCEPTANCE_DELAY, CheatSpan::Indefinite,
    );

    cheat_caller_address(contract.contract_address, addr(new_owner1), CheatSpan::Indefinite);
    contract.accept_ownership();

    cheat_caller_address(contract.contract_address, addr(new_owner2), CheatSpan::Indefinite);
    contract.accept_ownership();

    assert!(contract.is_owner(addr(new_owner1)));
    assert!(contract.is_owner(addr(new_owner2)));
    assert!(!contract.is_owner(addr(OWNER1)));
    assert!(!contract.is_owner(addr(OWNER2)));
    assert!(contract.is_owner(addr(OWNER3))); // Unchanged.
    assert_eq!(contract.get_n_owners(), 3);
}

// ============== Constructor Validation Unit Tests ==============
// Uses contract_state_for_testing to test initializer panics directly.

mod constructor_validation {
    use starknet::ContractAddress;
    use starkware_delayed_executor::common::{MAX_ACCEPTANCE_DELAY, MAX_N_SIGNERS};
    use starkware_delayed_executor::multi_owned::MultiOwnedComponent::InternalTrait;
    use crate::mocks::MockMultiOwned;
    use crate::test_helpers::addr;

    #[test]
    #[should_panic(expected: 'NO_OWNERS')]
    fn test_no_owners_fails() {
        let mut state = MockMultiOwned::contract_state_for_testing();
        let owners: Array<ContractAddress> = array![];
        state.multi_owned.initializer(owners.span(), 3600);
    }

    #[test]
    #[should_panic(expected: 'TOO_MANY_SIGNERS')]
    fn test_too_many_signers_fails() {
        let mut state = MockMultiOwned::contract_state_for_testing();
        let mut owners: Array<ContractAddress> = array![];
        let mut i: u32 = 0;
        while i <= MAX_N_SIGNERS {
            owners.append(addr((i + 1).into()));
            i += 1;
        }
        state.multi_owned.initializer(owners.span(), 3600);
    }

    #[test]
    #[should_panic(expected: 'ZERO_OWNER_ADDRESS')]
    fn test_zero_address_owner_fails() {
        let mut state = MockMultiOwned::contract_state_for_testing();
        let zero = addr(0);
        let owners = array![addr(0x1111), zero];
        state.multi_owned.initializer(owners.span(), 3600);
    }

    #[test]
    #[should_panic(expected: 'DUPLICATE_OWNER')]
    fn test_duplicate_owner_fails() {
        let mut state = MockMultiOwned::contract_state_for_testing();
        let owners = array![addr(0x1111), addr(0x2222), addr(0x1111)];
        state.multi_owned.initializer(owners.span(), 3600);
    }

    #[test]
    #[should_panic(expected: 'ACCEPTANCE_DELAY_TOO_LONG')]
    fn test_acceptance_delay_too_long_fails() {
        let mut state = MockMultiOwned::contract_state_for_testing();
        let owners = array![addr(0x1111)];
        state.multi_owned.initializer(owners.span(), MAX_ACCEPTANCE_DELAY + 1);
    }
}
