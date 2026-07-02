use starknet::ContractAddress;

pub fn APP_ROLE_ADMIN() -> ContractAddress {
    'APP_ROLE_ADMIN'.try_into().unwrap()
}

pub fn APP_GOVERNOR() -> ContractAddress {
    'APP_GOVERNOR'.try_into().unwrap()
}

pub fn GOVERNANCE_ADMIN() -> ContractAddress {
    'GOVERNANCE_ADMIN'.try_into().unwrap()
}
