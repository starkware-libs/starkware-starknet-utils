use core::num::traits::Zero;
use starkware_utils_testing::test_utils::{
    Deployable, TokenConfig, TokenState, TokenTrait as TokenStateTrait,
};

mod constants {
    use starknet::ContractAddress;

    pub(crate) const OWNER: ContractAddress = 'OWNER'.try_into().unwrap();
    pub(crate) const SPENDER: ContractAddress = 'SPENDER'.try_into().unwrap();
    pub(crate) const INITIAL_SUPPLY: u256 = 1000;
}

fn deploy_token() -> TokenState {
    let config = TokenConfig {
        name: "Token",
        symbol: "TKN",
        decimals: 18,
        initial_supply: constants::INITIAL_SUPPLY,
        owner: constants::OWNER,
    };
    config.deploy()
}

#[test]
fn test_allowance_zero_without_approval() {
    let token = deploy_token();
    let allowance = token.allowance(owner: constants::OWNER, spender: constants::SPENDER);
    assert!(allowance.is_zero());
}

#[test]
fn test_allowance_after_approve() {
    let token = deploy_token();
    let amount: u128 = 200;
    token.approve(owner: constants::OWNER, spender: constants::SPENDER, :amount);
    let allowance = token.allowance(owner: constants::OWNER, spender: constants::SPENDER);
    assert_eq!(allowance, amount);
}
