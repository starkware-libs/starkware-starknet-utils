use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
};
use starknet::ContractAddress;
use starkware_utils::components::clearlist::interface::{
    IClearlistDispatcher, IClearlistDispatcherTrait,
};
use starkware_utils::components::clearlist::mock_contract::clearlist_mock_contract as MockClearlistContract;
use starkware_utils::interfaces::mintable_token::{
    IMintableTokenDispatcher, IMintableTokenDispatcherTrait,
};
use starkware_utils_testing::constants::{GOVERNANCE_ADMIN, SECURITY_ADMIN, TOKEN_ADMIN};
use starkware_utils_testing::test_utils::{cheat_caller_address_once, set_default_roles};

const USER: ContractAddress = 'USER'.try_into().unwrap();

fn deploy_mock_clearlist_contract() -> ContractAddress {
    let contract = *declare("clearlist_mock_contract").unwrap().contract_class();
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
fn test_add_to_clearlist_by_security_admin() {
    let contract_address = deploy_mock_clearlist_contract();
    let clearlist = IClearlistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    let mut spy = spy_events();
    clearlist.add_to_clearlist(USER);
    assert!(clearlist.is_clearlisted(USER), "User should be clearlisted");
    spy
        .assert_emitted(
            @array![
                (
                    clearlist.contract_address,
                    MockClearlistContract::Event::ClearlistEvent(
                        starkware_utils::components::clearlist::clearlist::clearlist::Event::Clearlisted(
                            starkware_utils::components::clearlist::events::Clearlisted {
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
    let contract_address = deploy_mock_clearlist_contract();
    let clearlist = IClearlistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    clearlist.add_to_clearlist(USER);
    assert!(clearlist.is_clearlisted(USER), "User should be clearlisted");
    let mut spy = spy_events();
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    clearlist.remove_from_clearlist(USER);
    assert!(!clearlist.is_clearlisted(USER), "User should not be clearlisted");
    spy
        .assert_emitted(
            @array![
                (
                    clearlist.contract_address,
                    MockClearlistContract::Event::ClearlistEvent(
                        starkware_utils::components::clearlist::clearlist::clearlist::Event::Unclearlisted(
                            starkware_utils::components::clearlist::events::Unclearlisted {
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
    let contract_address = deploy_mock_clearlist_contract();
    let clearlist = IClearlistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    clearlist.add_to_clearlist(USER);
    assert!(clearlist.is_clearlisted(USER), "User should be clearlisted");
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    clearlist.remove_from_clearlist(USER);
    assert!(!clearlist.is_clearlisted(USER), "User should not be clearlisted");
}

#[test]
#[should_panic(expected: "ONLY_SECURITY_ADMIN")]
fn test_add_to_blocklist_wrong_role_panics() {
    let contract_address = deploy_mock_clearlist_contract();
    let clearlist = IClearlistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, USER);
    clearlist.add_to_clearlist(USER);
}

#[test]
#[should_panic(expected: "ONLY_SECURITY_ADMIN")]
fn test_remove_from_blocklist_wrong_role_panics() {
    let contract_address = deploy_mock_clearlist_contract();
    let clearlist = IClearlistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    clearlist.add_to_clearlist(USER);
    cheat_caller_address_once(contract_address, USER);
    clearlist.remove_from_clearlist(USER);
}


#[test]
fn test_token_mint_to_clearlisted_account_panics() {
    let contract_address = deploy_mock_clearlist_contract();
    let clearlist = IClearlistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    clearlist.add_to_clearlist(USER);
    assert!(clearlist.is_clearlisted(USER), "User should be clearlisted");
    cheat_caller_address_once(contract_address, TOKEN_ADMIN);
    let mintable_token = IMintableTokenDispatcher { contract_address };
    mintable_token.permissioned_mint(USER, 100);
}

#[test]
fn test_token_transfer_from_clearlisted_account() {
    let contract_address = deploy_mock_clearlist_contract();
    let clearlist = IClearlistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    clearlist.add_to_clearlist(USER);
    assert!(clearlist.is_clearlisted(USER), "User should be clearlisted");
    let token = IERC20Dispatcher { contract_address };
    cheat_caller_address_once(contract_address, USER);
    token.transfer(USER, 100);
}

#[test]
#[should_panic(expected: "NOT CLEARLISTED: 1431520594")]
fn test_token_transfer_from_UNclearlisted_account_panics() {
    let contract_address = deploy_mock_clearlist_contract();
    let clearlist = IClearlistDispatcher { contract_address };
    cheat_caller_address_once(contract_address, SECURITY_ADMIN);
    assert!(!clearlist.is_clearlisted(USER), "User should not be clearlisted");
    let token = IERC20Dispatcher { contract_address };
    cheat_caller_address_once(contract_address, USER);
    token.transfer(USER, 100);
}
