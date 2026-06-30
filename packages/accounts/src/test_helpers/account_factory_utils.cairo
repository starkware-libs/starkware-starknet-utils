use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::eth_address::EthAddress;
use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
use starkware_accounts::utils::{PRIMER_CLASS_HASH, compute_contract_address};
use starkware_utils_testing::test_utils::{
    set_account_as_app_governor, set_account_as_app_role_admin,
};
use crate::test_helpers::constants::{APP_GOVERNOR, APP_ROLE_ADMIN, GOVERNANCE_ADMIN};
use crate::test_helpers::dummy_contracts::declare_dummy_eth_address_contract;

/// Mirrors AccountFactory.eth_address_to_account for tests, using the
/// PRIMER_CLASS_HASH and the account factory address as the deployer address.
pub fn eth_address_to_account(
    account_factory: ContractAddress, eth_address: EthAddress,
) -> ContractAddress {
    compute_contract_address(
        salt: eth_address.into(),
        class_hash: PRIMER_CLASS_HASH.into(),
        constructor_calldata: array![].span(),
        deployer_address: account_factory.into(),
    )
}

/// Declare the `PrimerTestMock` (stand-in for the real Primer) and return its class hash.
pub fn declare_primer_contract() -> ClassHash {
    *snforge_std::declare("PrimerTestMock").unwrap_syscall().contract_class().class_hash
}

/// Sets default roles for the AccountFactory contract.
pub fn set_account_factory_default_roles(account_factory: ContractAddress) {
    set_account_as_app_role_admin(
        contract: account_factory, account: APP_ROLE_ADMIN(), governance_admin: GOVERNANCE_ADMIN(),
    );
    set_account_as_app_governor(
        contract: account_factory, account: APP_GOVERNOR(), app_role_admin: APP_ROLE_ADMIN(),
    );
}

/// Builds the constructor calldata array for AccountFactory.
pub fn account_factory_constructor_calldata() -> Array<felt252> {
    let governance_admin: ContractAddress = GOVERNANCE_ADMIN();
    let upgrade_delay: u64 = 0;
    let account_class_hash: ClassHash = declare_dummy_eth_address_contract();
    let mut calldata: Array<felt252> = array![];
    Serde::serialize(@governance_admin, ref calldata);
    Serde::serialize(@upgrade_delay, ref calldata);
    Serde::serialize(@account_class_hash, ref calldata);
    calldata
}

/// Sets up the AccountFactory test environment:
/// - deploys the `AccountFactory` contract,
/// - sets default roles,
/// - declares the Primer test mock so its class hash is available.
pub fn setup_account_factory_test_env() -> ContractAddress {
    let calldata = account_factory_constructor_calldata();
    let account_factory_contract = snforge_std::declare("AccountFactory")
        .unwrap_syscall()
        .contract_class();
    let (account_factory_contract_address, _) = account_factory_contract
        .deploy(@calldata)
        .unwrap_syscall();
    set_account_factory_default_roles(account_factory_contract_address);
    declare_primer_contract();
    account_factory_contract_address
}
