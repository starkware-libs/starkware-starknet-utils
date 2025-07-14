use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
};
use starknet::ContractAddress;
use starkware_utils::components::blacklist::interface::{
    IBlacklistDispatcher, IBlacklistDispatcherTrait,
};
use starkware_utils::components::blacklist::mock_contract::blacklist_mock_contract as MockBlacklistContract;
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils_testing::constants::{GOVERNANCE_ADMIN, SECURITY_ADMIN, SECURITY_AGENT};
use starkware_utils_testing::test_utils::{cheat_caller_address_once, set_default_roles};

const USER: ContractAddress = 'USER'.try_into().unwrap();

fn deploy_mock_blacklist_contract() -> IBlacklistDispatcher {
    let contract = *declare("blacklist_mock_contract").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![GOVERNANCE_ADMIN.into()]).unwrap();
    set_default_roles(contract: contract_address, governance_admin: GOVERNANCE_ADMIN);
    IBlacklistDispatcher { contract_address }
}

#[test]
fn test_add_to_blacklist_by_security_agent() {
    let dispatcher = deploy_mock_blacklist_contract();
    let roles_dispatcher = IRolesDispatcher { contract_address: dispatcher.contract_address };
    roles_dispatcher.register_security_agent(SECURITY_AGENT);
    cheat_caller_address_once(dispatcher.contract_address, SECURITY_AGENT);
    let mut spy = spy_events();
    assert!(dispatcher.add_to_blacklist(USER), "add_to_blacklist should return true");
    assert!(dispatcher.is_blacklisted(USER), "User should be blacklisted");
    spy
        .assert_emitted(
            @array![
                (
                    dispatcher.contract_address,
                    MockBlacklistContract::Event::BlacklistEvent(
                        starkware_utils::components::blacklist::blacklist::blacklist::Event::Blacklisted(
                            starkware_utils::components::blacklist::events::Blacklisted {
                                account: USER,
                            },
                        ),
                    ),
                ),
            ],
        );
}

#[test]
fn test_remove_from_blacklist_by_security_admin() {
    let dispatcher = deploy_mock_blacklist_contract();
    let roles_dispatcher = IRolesDispatcher { contract_address: dispatcher.contract_address };
    roles_dispatcher.register_security_agent(SECURITY_AGENT);
    roles_dispatcher.register_security_admin(SECURITY_ADMIN);
    cheat_caller_address_once(dispatcher.contract_address, SECURITY_AGENT);
    dispatcher.add_to_blacklist(USER);
    cheat_caller_address_once(dispatcher.contract_address, SECURITY_ADMIN);
    let mut spy = spy_events();
    assert!(dispatcher.remove_from_blacklist(USER), "remove_from_blacklist should return true");
    assert!(!dispatcher.is_blacklisted(USER), "User should not be blacklisted");
    spy
        .assert_emitted(
            @array![
                (
                    dispatcher.contract_address,
                    MockBlacklistContract::Event::BlacklistEvent(
                        starkware_utils::components::blacklist::blacklist::blacklist::Event::Unblacklisted(
                            starkware_utils::components::blacklist::events::Unblacklisted {
                                account: USER,
                            },
                        ),
                    ),
                ),
            ],
        );
}

#[test]
fn test_is_blacklisted() {
    let dispatcher = deploy_mock_blacklist_contract();
    let roles_dispatcher = IRolesDispatcher { contract_address: dispatcher.contract_address };
    roles_dispatcher.register_security_agent(SECURITY_AGENT);
    cheat_caller_address_once(dispatcher.contract_address, SECURITY_AGENT);
    dispatcher.add_to_blacklist(USER);
    assert!(dispatcher.is_blacklisted(USER), "User should be blacklisted");
    roles_dispatcher.register_security_admin(SECURITY_ADMIN);
    cheat_caller_address_once(dispatcher.contract_address, SECURITY_ADMIN);
    dispatcher.remove_from_blacklist(USER);
    assert!(!dispatcher.is_blacklisted(USER), "User should not be blacklisted");
}

#[test]
#[should_panic(expected: "ONLY_SECURITY_AGENT")]
fn test_add_to_blacklist_wrong_role_panics() {
    let dispatcher = deploy_mock_blacklist_contract();
    cheat_caller_address_once(dispatcher.contract_address, USER);
    dispatcher.add_to_blacklist(USER);
}

#[test]
#[should_panic(expected: "ONLY_SECURITY_ADMIN")]
fn test_remove_from_blacklist_wrong_role_panics() {
    let dispatcher = deploy_mock_blacklist_contract();
    let roles_dispatcher = IRolesDispatcher { contract_address: dispatcher.contract_address };
    roles_dispatcher.register_security_agent(SECURITY_AGENT);
    cheat_caller_address_once(dispatcher.contract_address, SECURITY_AGENT);
    dispatcher.add_to_blacklist(USER);
    cheat_caller_address_once(dispatcher.contract_address, USER);
    dispatcher.remove_from_blacklist(USER);
}
