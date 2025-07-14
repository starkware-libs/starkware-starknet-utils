use starknet::ContractAddress;

#[derive(Drop, PartialEq, starknet::Event)]
pub struct Blocklisted {
    #[key]
    pub account: ContractAddress,
    #[key]
    pub caller: ContractAddress,
}

#[derive(Drop, PartialEq, starknet::Event)]
pub struct Unblocklisted {
    #[key]
    pub account: ContractAddress,
    #[key]
    pub caller: ContractAddress,
}
