use core::num::traits::Zero;
use openzeppelin::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use starkware_utils::erc20::erc20_mocks::{
    IErc20UtilsCallerDispatcher, IErc20UtilsCallerDispatcherTrait,
};
use starkware_utils_testing::test_utils::{cheat_caller_address_once, deploy_mock_erc20_contract};

mod constants {
    use starknet::ContractAddress;

    pub(crate) const RECIPIENT: ContractAddress = 'RECIPIENT'.try_into().unwrap();
    pub(crate) const SENDER: ContractAddress = 'SENDER'.try_into().unwrap();
    pub(crate) const INITIAL_SUPPLY: u256 = 1000;
    pub(crate) const AMOUNT: u256 = 50;
}

fn deploy_token(owner: ContractAddress, initial_supply: u256) -> ContractAddress {
    deploy_mock_erc20_contract(
        :initial_supply, owner_address: owner, name: "Token", symbol: "TKN", decimals: 18,
    )
}

fn deploy_caller_contract() -> ContractAddress {
    let contract = declare("erc20_utils_caller").unwrap().contract_class();
    let (caller_address, _) = contract.deploy(@array![]).unwrap();
    caller_address
}

#[test]
fn test_checked_transfer_success() {
    let caller_address = deploy_caller_contract();
    let token_address = deploy_token(
        owner: caller_address, initial_supply: constants::INITIAL_SUPPLY,
    );
    let token = IERC20Dispatcher { contract_address: token_address };

    assert!(token.balance_of(caller_address) == constants::INITIAL_SUPPLY);
    assert!(token.balance_of(constants::RECIPIENT) == Zero::zero());

    let caller = IErc20UtilsCallerDispatcher { contract_address: caller_address };
    caller
        .run_checked_transfer(
            :token_address, recipient: constants::RECIPIENT, amount: constants::AMOUNT,
        );

    assert!(token.balance_of(caller_address) == constants::INITIAL_SUPPLY - constants::AMOUNT);
    assert!(token.balance_of(constants::RECIPIENT) == constants::AMOUNT);
}

#[test]
#[should_panic(expected: "Insufficient ERC20 balance")]
fn test_checked_transfer_insufficient_balance() {
    let caller_address = deploy_caller_contract();
    let token_address = deploy_token(
        owner: caller_address, initial_supply: constants::INITIAL_SUPPLY,
    );
    let token = IERC20Dispatcher { contract_address: token_address };

    assert!(token.balance_of(caller_address) == constants::INITIAL_SUPPLY);
    assert!(token.balance_of(constants::RECIPIENT) == Zero::zero());

    let caller = IErc20UtilsCallerDispatcher { contract_address: caller_address };
    caller
        .run_checked_transfer(
            :token_address, recipient: constants::RECIPIENT, amount: constants::INITIAL_SUPPLY + 1,
        );
}

#[test]
fn test_checked_transfer_from_success() {
    let caller_address = deploy_caller_contract();
    let token_address = deploy_token(
        owner: constants::SENDER, initial_supply: constants::INITIAL_SUPPLY,
    );

    let token = IERC20Dispatcher { contract_address: token_address };
    cheat_caller_address_once(contract_address: token_address, caller_address: constants::SENDER);
    token.approve(spender: caller_address, amount: constants::AMOUNT);

    assert!(token.balance_of(constants::SENDER) == constants::INITIAL_SUPPLY);
    assert!(token.balance_of(constants::RECIPIENT) == 0);

    let caller = IErc20UtilsCallerDispatcher { contract_address: caller_address };
    caller
        .run_checked_transfer_from(
            :token_address,
            sender: constants::SENDER,
            recipient: constants::RECIPIENT,
            amount: constants::AMOUNT,
        );

    assert!(token.balance_of(constants::SENDER) == constants::INITIAL_SUPPLY - constants::AMOUNT);
    assert!(token.balance_of(constants::RECIPIENT) == constants::AMOUNT);
}

#[test]
#[should_panic(expected: "Insufficient ERC20 allowance")]
fn test_checked_transfer_from_insufficient_allowance() {
    let caller_address = deploy_caller_contract();
    let token_address = deploy_token(
        owner: constants::SENDER, initial_supply: constants::INITIAL_SUPPLY,
    );
    let token = IERC20Dispatcher { contract_address: token_address };

    assert!(token.balance_of(constants::SENDER) == constants::INITIAL_SUPPLY);
    assert!(token.balance_of(constants::RECIPIENT) == Zero::zero());

    let caller = IErc20UtilsCallerDispatcher { contract_address: caller_address };
    caller
        .run_checked_transfer_from(
            :token_address,
            sender: constants::SENDER,
            recipient: constants::RECIPIENT,
            amount: constants::AMOUNT,
        );
}

#[test]
#[should_panic(expected: "Insufficient ERC20 balance")]
fn test_checked_transfer_from_insufficient_balance() {
    let caller_address = deploy_caller_contract();
    let token_address = deploy_token(
        owner: constants::SENDER, initial_supply: constants::INITIAL_SUPPLY,
    );
    let transfer_amount = constants::INITIAL_SUPPLY + 1;
    let token = IERC20Dispatcher { contract_address: token_address };

    cheat_caller_address_once(contract_address: token_address, caller_address: constants::SENDER);
    token.approve(spender: caller_address, amount: transfer_amount);

    assert!(token.balance_of(constants::SENDER) == constants::INITIAL_SUPPLY);
    assert!(token.balance_of(constants::RECIPIENT) == Zero::zero());

    let caller = IErc20UtilsCallerDispatcher { contract_address: caller_address };
    caller
        .run_checked_transfer_from(
            :token_address,
            sender: constants::SENDER,
            recipient: constants::RECIPIENT,
            amount: transfer_amount,
        );
}
