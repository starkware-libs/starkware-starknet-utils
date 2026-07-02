use snforge_std;
use snforge_std::cheatcodes::events::{EventSpyTrait, EventsFilterTrait};
use starknet::secp256_trait::Signature;
use starknet::syscalls::get_class_hash_at_syscall;
use starknet::{ClassHash, ContractAddress, EthAddress, SyscallResultTrait};
use starkware_accounts::account_factory::AccountFactory::{AccountClassHashChanged, AccountDeployed};
use starkware_accounts::account_factory::{
    IAccountFactoryDispatcher, IAccountFactoryDispatcherTrait,
};
use starkware_utils_testing::test_utils::{assert_expected_event_emitted, cheat_caller_address_once};
use crate::test_helpers::account_factory_utils::{
    eth_address_to_account, setup_account_factory_test_env,
};
use crate::test_helpers::constants::APP_GOVERNOR;
use crate::test_helpers::dummy_contracts::{
    declare_dummy_eth_address_contract, declare_second_dummy_eth_address_contract,
};
use crate::test_helpers::event_helpers::{get_event_by_selector, get_event_by_selector_n};


fn deploy_account_wrapper(
    account_factory_addr: ContractAddress, eth_address: EthAddress,
) -> ContractAddress {
    let account_factory = IAccountFactoryDispatcher { contract_address: account_factory_addr };
    let signature = Signature { r: 0x1012, s: 0x1012, y_parity: true };
    account_factory.deploy_account(:eth_address, :signature)
}


#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_account_factory_missing_app_governor() {
    /// Ensures restricted calls revert for non-governor.
    let account_factory_addr = setup_account_factory_test_env();
    let account_factory = IAccountFactoryDispatcher { contract_address: account_factory_addr };
    let new_hash: ClassHash = 0x3.try_into().unwrap();
    account_factory.set_account_class_hash(new_class_hash: new_hash);
}

#[test]
fn test_account_factory_set_account_class_hash() {
    /// Sets class hash for accounts; expects the hash to change and emit an event.
    let account_factory_addr = setup_account_factory_test_env();
    let account_factory = IAccountFactoryDispatcher { contract_address: account_factory_addr };
    let mut spy = snforge_std::spy_events();

    // This is the initial account class hash set by the account factory constructor in the test.
    let initial_account_class_hash = declare_dummy_eth_address_contract();

    let previous_account_class_hash = account_factory.account_class_hash();
    assert!(
        previous_account_class_hash == initial_account_class_hash, "Account class hash mismatch",
    );

    cheat_caller_address_once(
        contract_address: account_factory_addr, caller_address: APP_GOVERNOR(),
    );
    let new_account_class_hash: ClassHash = 0x3.try_into().unwrap();
    account_factory.set_account_class_hash(new_class_hash: new_account_class_hash);
    let current_account_class_hash = account_factory.account_class_hash();
    assert!(current_account_class_hash == new_account_class_hash, "Account class hash mismatch");

    // Assert event emitted
    let events = spy.get_events().emitted_by(account_factory_addr).events.span();
    let spied_event = get_event_by_selector(:events, selector: selector!("AccountClassHashChanged"))
        .unwrap();
    let expected_event = AccountClassHashChanged {
        previous_class_hash: previous_account_class_hash, new_class_hash: new_account_class_hash,
    };
    assert_expected_event_emitted(
        spied_event: spied_event,
        expected_event: expected_event,
        expected_event_selector: @selector!("AccountClassHashChanged"),
        expected_event_name: "AccountClassHashChanged",
    );
}

#[test]
fn test_account_factory_set_account_class_hash_same_value() {
    /// Calling set_account_class_hash twice with the same value should emit only one event.
    let account_factory_addr = setup_account_factory_test_env();
    let account_factory = IAccountFactoryDispatcher { contract_address: account_factory_addr };
    let mut spy = snforge_std::spy_events();

    let new_hash: ClassHash = 0xABCDEF.try_into().unwrap();

    // First call emits an event.
    cheat_caller_address_once(
        contract_address: account_factory_addr, caller_address: APP_GOVERNOR(),
    );
    account_factory.set_account_class_hash(new_class_hash: new_hash);
    let after_first = spy.get_events().emitted_by(account_factory_addr).events;
    assert!(after_first.len() == 1, "expected one event after first set");

    // Second call with the same hash should not emit another event.
    cheat_caller_address_once(
        contract_address: account_factory_addr, caller_address: APP_GOVERNOR(),
    );
    account_factory.set_account_class_hash(new_class_hash: new_hash);
    let after_second = spy.get_events().emitted_by(account_factory_addr).events;
    assert!(after_second.len() == 1, "no event expected on identical second set");
}

#[test]
fn test_deploy_account_deploys_once_and_reuses() {
    /// deploy_account:
    /// - first call lazily deploys and upgrades an account contract for a given Eth address;
    /// - a second call with the same parameters reuses the same contract and class hash.
    let account_factory_addr = setup_account_factory_test_env();
    let account_factory = IAccountFactoryDispatcher { contract_address: account_factory_addr };
    let mut spy = snforge_std::spy_events();

    let eth_address: EthAddress = '0x1012'.try_into().unwrap();

    // Compute the expected account address using the same derivation logic as the contract.
    let expected_account = eth_address_to_account(
        account_factory: account_factory_addr, :eth_address,
    );

    // First call: lazily deploys the primer, upgrades it to the account_class_hash, and
    // leaves the account contract at the expected address.
    let account_address = deploy_account_wrapper(:account_factory_addr, :eth_address);
    assert!(account_address == expected_account, "unexpected account address after first deploy");
    let class_hash_after_first = get_class_hash_at_syscall(account_address).unwrap_syscall();
    let expected_class_hash = account_factory.account_class_hash();
    assert!(
        class_hash_after_first == expected_class_hash,
        "unexpected class hash after first deploy_account",
    );

    let first_events = spy.get_events().emitted_by(account_factory_addr).events.span();
    let spied_event = get_event_by_selector(
        events: first_events, selector: selector!("AccountDeployed"),
    )
        .unwrap();
    let expected_event = AccountDeployed {
        account_class_hash: class_hash_after_first, eth_address, account_address,
    };
    assert_expected_event_emitted(
        spied_event: spied_event,
        expected_event: expected_event,
        expected_event_selector: @selector!("AccountDeployed"),
        expected_event_name: "AccountDeployed",
    );

    // Second call with the same parameters should reuse the same account and leave the
    // class hash unchanged.
    let second_account_address = deploy_account_wrapper(:account_factory_addr, :eth_address);
    assert!(second_account_address == account_address, "account address changed on reuse");
    let class_hash_after_second = get_class_hash_at_syscall(account_address).unwrap_syscall();
    assert!(
        class_hash_after_second == class_hash_after_first,
        "class hash should remain the same on subsequent deploy_account calls",
    );
    let events_after_second = spy.get_events().emitted_by(account_factory_addr).events;
    assert!(
        events_after_second.len() == 1, "no additional AccountDeployed event expected on reuse",
    );
}

#[test]
fn test_after_change_account_class_hash_reuses_existing_account() {
    /// After changing the account class hash:
    /// - existing accounts keep their contract address and class hash;
    /// - subsequent deploy_account calls reuse the same account.
    let account_factory_addr = setup_account_factory_test_env();
    let account_factory = IAccountFactoryDispatcher { contract_address: account_factory_addr };

    let eth_address: EthAddress = '0x1012'.try_into().unwrap();
    let expected_account = eth_address_to_account(
        account_factory: account_factory_addr, :eth_address,
    );

    // First call: deploys and upgrades to the initial account_class_hash.
    let account_address = deploy_account_wrapper(:account_factory_addr, :eth_address);
    assert!(account_address == expected_account, "unexpected account address after first deploy");
    let class_hash_after_first = get_class_hash_at_syscall(account_address).unwrap_syscall();
    let initial_class_hash = account_factory.account_class_hash();
    assert!(
        class_hash_after_first == initial_class_hash,
        "class hash should be the same as the account class hash after first call",
    );

    // Change the account class hash for future users (existing account should not move).
    let new_hash: ClassHash = declare_second_dummy_eth_address_contract();
    cheat_caller_address_once(
        contract_address: account_factory_addr, caller_address: APP_GOVERNOR(),
    );
    account_factory.set_account_class_hash(new_class_hash: new_hash);

    // Second call with the same parameters should reuse the same account and leave the
    // class hash unchanged.
    let mut second_spy = snforge_std::spy_events();
    let second_account_address = deploy_account_wrapper(:account_factory_addr, :eth_address);
    assert!(second_account_address == account_address, "account address changed on reuse");
    let class_hash_after_second = get_class_hash_at_syscall(account_address).unwrap_syscall();
    assert!(
        class_hash_after_second == class_hash_after_first,
        "class hash should remain the same on subsequent deploy_account calls",
    );
    let second_events = second_spy.get_events().emitted_by(account_factory_addr).events.span();
    let account_deployed_second = get_event_by_selector(
        events: second_events, selector: selector!("AccountDeployed"),
    );
    assert!(
        account_deployed_second.is_none(),
        "no AccountDeployed event expected on reuse with unchanged account",
    );
}
#[test]
fn test_change_account_class_hash_affects_only_new_users() {
    /// Changing the account class hash:
    /// - causes subsequent users (new Eth addresses) to get a different account address and class
    ///   hash;
    /// - both old and new accounts still point to the expected implementation.
    let account_factory_addr = setup_account_factory_test_env();
    let account_factory = IAccountFactoryDispatcher { contract_address: account_factory_addr };
    let mut spy = snforge_std::spy_events();

    let eth_address: EthAddress = '0x1012'.try_into().unwrap();
    let expected_account = eth_address_to_account(
        account_factory: account_factory_addr, :eth_address,
    );

    // First call: deploys and upgrades to the initial account_class_hash.
    let first_account_address = deploy_account_wrapper(:account_factory_addr, :eth_address);
    assert!(
        first_account_address == expected_account, "unexpected account address after first deploy",
    );
    let class_hash_after_first = get_class_hash_at_syscall(first_account_address).unwrap_syscall();
    let initial_class_hash = account_factory.account_class_hash();
    assert!(
        class_hash_after_first == initial_class_hash,
        "class hash should be the same as the account class hash after first call",
    );

    // Change the account class hash for future users (existing account should not move or change
    // class hash).
    let new_hash = declare_second_dummy_eth_address_contract();
    cheat_caller_address_once(
        contract_address: account_factory_addr, caller_address: APP_GOVERNOR(),
    );
    account_factory.set_account_class_hash(new_class_hash: new_hash);

    // Build parameters for a *new* Eth address so the contract derives a second account.
    let new_eth_address: EthAddress = '0x1013'.try_into().unwrap();
    let expected_new_account = eth_address_to_account(
        account_factory: account_factory_addr, eth_address: new_eth_address,
    );

    let new_account_address = deploy_account_wrapper(
        :account_factory_addr, eth_address: new_eth_address,
    );
    assert!(
        new_account_address == expected_new_account,
        "new account should be derived as expected from new Eth address",
    );
    let class_hash_new_account = get_class_hash_at_syscall(new_account_address).unwrap_syscall();
    assert!(
        class_hash_new_account == new_hash, "new account should have the updated class
    hash",
    );

    // Verify the second AccountDeployed event (the one for the new account).
    let events = spy.get_events().emitted_by(contract_address: account_factory_addr).events.span();
    let spied_event = get_event_by_selector_n(:events, selector: selector!("AccountDeployed"), n: 1)
        .unwrap();
    let expected_event = AccountDeployed {
        account_class_hash: new_hash,
        eth_address: new_eth_address,
        account_address: new_account_address,
    };
    assert_expected_event_emitted(
        spied_event: spied_event,
        expected_event: expected_event,
        expected_event_selector: @selector!("AccountDeployed"),
        expected_event_name: "AccountDeployed",
    );

    // Check that the original account doesn't change even though the account class hash has
    // changed.
    let prev_account_address = deploy_account_wrapper(:account_factory_addr, :eth_address);
    assert!(prev_account_address == expected_account, "original account should not change");
    let class_hash_prev_account = get_class_hash_at_syscall(prev_account_address).unwrap_syscall();
    assert!(
        class_hash_prev_account == initial_class_hash,
        "original account should keep its original class hash",
    );
}
