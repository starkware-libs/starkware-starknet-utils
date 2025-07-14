use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
};
use starknet::ContractAddress;
use starkware_utils::components::blocklist::interface::{
    IBlocklistDispatcher, IBlocklistDispatcherTrait,
};
use starkware_utils::components::blocklist::mock_contract::blocklist_mock_contract as MockBlocklistContract;
use starkware_utils::interfaces::mintable_token::{
    IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
};
use starkware_utils_testing::constants::{GOVERNANCE_ADMIN, SECURITY_ADMIN};
use starkware_utils_testing::test_utils::{cheat_caller_address_once, set_default_roles};

const USER: ContractAddress = 'USER'.try_into().unwrap();

fn deploy_mock_blocklist_contract() -> ContractAddress {
    let contract = *declare("blocklist_mock_contract").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    let name: ByteArray = "STRK";
    let symbol: ByteArray = "STRK";
    GOVERNANCE_ADMIN.serialize(ref calldata);
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    set_default_roles(contract: contract_address, governance_admin: GOVERNANCE_ADMIN);
    contract_address
}

#[test]
fn test_add_to_blocklist_by_security_admin() {
    let contract_address = deploy_mock_blocklist_contract();
    let blocklist = IBlocklistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    let mut spy = spy_events();
    blocklist.add_to_blocklist(USER);
    assert!(blocklist.is_blocklisted(USER), "User should be blocklisted");
    spy
        .assert_emitted(
            @array![
                (
                    blocklist.contract_address,
                    MockBlocklistContract::Event::BlocklistEvent(
                        starkware_utils::components::blocklist::blocklist::blocklist::Event::Blocklisted(
                            starkware_utils::components::blocklist::events::Blocklisted {
                                account: USER, caller: SECURITY_ADMIN,
                            },
                        ),
                    ),
                ),
            ],
        );
}

#[test]
fn test_remove_from_blocklist_by_security_admin() {
    let contract_address = deploy_mock_blocklist_contract();
    let blocklist = IBlocklistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    blocklist.add_to_blocklist(USER);
    assert!(blocklist.is_blocklisted(USER), "User should be blocklisted");
    let mut spy = spy_events();
    blocklist.remove_from_blocklist(USER);
    assert!(!blocklist.is_blocklisted(USER), "User should not be blocklisted");
    spy
        .assert_emitted(
            @array![
                (
                    blocklist.contract_address,
                    MockBlocklistContract::Event::BlocklistEvent(
                        starkware_utils::components::blocklist::blocklist::blocklist::Event::Unblocklisted(
                            starkware_utils::components::blocklist::events::Unblocklisted {
                                account: USER, caller: SECURITY_ADMIN,
                            },
                        ),
                    ),
                ),
            ],
        );
}

#[test]
fn test_is_blocklisted() {
    let contract_address = deploy_mock_blocklist_contract();
    let blocklist = IBlocklistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    blocklist.add_to_blocklist(USER);
    assert!(blocklist.is_blocklisted(USER), "User should be blocklisted");
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    blocklist.remove_from_blocklist(USER);
    assert!(!blocklist.is_blocklisted(USER), "User should not be blocklisted");
}

#[test]
#[should_panic(expected: "ONLY_SECURITY_ADMIN")]
fn test_add_to_blocklist_wrong_role_panics() {
    let contract_address = deploy_mock_blocklist_contract();
    let blocklist = IBlocklistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, USER);
    blocklist.add_to_blocklist(USER);
}

#[test]
#[should_panic(expected: "ONLY_SECURITY_ADMIN")]
fn test_remove_from_blocklist_wrong_role_panics() {
    let contract_address = deploy_mock_blocklist_contract();
    let blocklist = IBlocklistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    blocklist.add_to_blocklist(USER);
    cheat_caller_address_once(contract_address, USER);
    blocklist.remove_from_blocklist(USER);
}


#[test]
#[should_panic(expected: "BLOCKLISTED: 1431520594")]
fn test_token_mint_to_blocked_account_panics() {
    let contract_address = deploy_mock_blocklist_contract();
    let blocklist = IBlocklistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    blocklist.add_to_blocklist(USER);
    assert!(blocklist.is_blocklisted(USER), "User should be blocklisted");
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    let mintable_token = IMintableTokenDispatcher { contract_address };
    mintable_token.permissioned_mint(USER, 100);
}

#[test]
#[should_panic(expected: "BLOCKLISTED: 1431520594")]
fn test_token_transfer_from_blocked_account_panics() {
    let contract_address = deploy_mock_blocklist_contract();
    let blocklist = IBlocklistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    blocklist.add_to_blocklist(USER);
    assert!(blocklist.is_blocklisted(USER), "User should be blocklisted");
    let token = IERC20Dispatcher { contract_address };
    cheat_caller_address_once(contract_address, USER);
    token.transfer(USER, 100);
}
