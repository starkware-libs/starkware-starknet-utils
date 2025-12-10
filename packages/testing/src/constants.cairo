use starknet::ContractAddress;

pub const WRONG_ADMIN: ContractAddress = 'WRONG_ADMIN'.try_into().unwrap();
pub const INITIAL_ROOT_ADMIN: ContractAddress = 'INITIAL_ROOT_ADMIN'.try_into().unwrap();
pub const GOVERNANCE_ADMIN: ContractAddress = 'GOVERNANCE_ADMIN'.try_into().unwrap();
pub const SECURITY_ADMIN: ContractAddress = 'SECURITY_ADMIN'.try_into().unwrap();
pub const SECURITY_GOVERNOR: ContractAddress = 'SECURITY_GOVERNOR'.try_into().unwrap();
pub const APP_ROLE_ADMIN: ContractAddress = 'APP_ROLE_ADMIN'.try_into().unwrap();
pub const APP_GOVERNOR: ContractAddress = 'APP_GOVERNOR'.try_into().unwrap();
pub const OPERATOR: ContractAddress = 'OPERATOR'.try_into().unwrap();
pub const TOKEN_ADMIN: ContractAddress = 'TOKEN_ADMIN'.try_into().unwrap();
pub const UPGRADE_AGENT: ContractAddress = 'UPGRADE_AGENT'.try_into().unwrap();
pub const UPGRADE_GOVERNOR: ContractAddress = 'UPGRADE_GOVERNOR'.try_into().unwrap();
pub const SECURITY_AGENT: ContractAddress = 'SECURITY_AGENT'.try_into().unwrap();
pub const DUMMY_ADDRESS: ContractAddress = 'DUMMY_ADDRESS'.try_into().unwrap();
