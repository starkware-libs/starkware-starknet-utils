use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::{ContractAddress, SyscallResultTrait};
use starkware_utils_testing::constants;

pub(crate) fn deploy_mock_contract() -> ContractAddress {
    let mock_contract = *declare("MockContract").unwrap().contract_class();
    let (contract_address, _) = mock_contract
        .deploy(@array![constants::INITIAL_ROOT_ADMIN.into()])
        .unwrap();
    contract_address
}

pub(crate) fn deploy_mock_contract_with_zero() -> ContractAddress {
    let mock_contract = *declare("MockContract").unwrap().contract_class();
    let (contract_address, _) = mock_contract.deploy(@array![0]).unwrap_syscall();
    contract_address
}
