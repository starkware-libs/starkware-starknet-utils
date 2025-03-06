use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::{ContractAddress, SyscallResultTrait};

pub(crate) mod Constants {
    use super::ContractAddress;

    pub(crate) fn WRONG_ADMIN() -> ContractAddress {
        'WRONG_ADMIN'.try_into().unwrap()
    }
    pub(crate) fn INITIAL_ROOT_ADMIN() -> ContractAddress {
        'INITIAL_ROOT_ADMIN'.try_into().unwrap()
    }
    pub(crate) fn GOVERNANCE_ADMIN() -> ContractAddress {
        'GOVERNANCE_ADMIN'.try_into().unwrap()
    }
    pub(crate) fn SECURITY_ADMIN() -> ContractAddress {
        'SECURITY_ADMIN'.try_into().unwrap()
    }
    pub(crate) fn APP_ROLE_ADMIN() -> ContractAddress {
        'APP_ROLE_ADMIN'.try_into().unwrap()
    }
    pub(crate) fn APP_GOVERNOR() -> ContractAddress {
        'APP_GOVERNOR'.try_into().unwrap()
    }
    pub(crate) fn OPERATOR() -> ContractAddress {
        'OPERATOR'.try_into().unwrap()
    }
    pub(crate) fn TOKEN_ADMIN() -> ContractAddress {
        'TOKEN_ADMIN'.try_into().unwrap()
    }
    pub(crate) fn UPGRADE_GOVERNOR() -> ContractAddress {
        'UPGRADE_GOVERNOR'.try_into().unwrap()
    }
    pub(crate) fn SECURITY_AGENT() -> ContractAddress {
        'SECURITY_AGENT'.try_into().unwrap()
    }
}

pub(crate) fn deploy_mock_contract() -> ContractAddress {
    let mock_contract = *declare("MockContract").unwrap().contract_class();
    let (contract_address, _) = mock_contract
        .deploy(@array![Constants::INITIAL_ROOT_ADMIN().into()])
        .unwrap();
    contract_address
}

pub(crate) fn deploy_mock_contract_with_zero() -> ContractAddress {
    let mock_contract = *declare("MockContract").unwrap().contract_class();
    let (contract_address, _) = mock_contract.deploy(@array![0]).unwrap_syscall();
    contract_address
}
