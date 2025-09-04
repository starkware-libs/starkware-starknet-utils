use starknet::ContractAddress;

#[derive(Drop, PartialEq, starknet::Event)]
pub struct Clearlisted {
    #[key]
    pub account: ContractAddress,
    pub caller: ContractAddress,
}

#[derive(Drop, PartialEq, starknet::Event)]
pub struct Unclearlisted {
    #[key]
    pub account: ContractAddress,
    pub caller: ContractAddress,
}
