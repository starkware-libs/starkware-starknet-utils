use starknet::ContractAddress;

#[derive(Drop, PartialEq, starknet::Event)]
pub struct Blacklisted {
    #[key]
    pub account: ContractAddress,
}

#[derive(Drop, PartialEq, starknet::Event)]
pub struct Unblacklisted {
    #[key]
    pub account: ContractAddress,
}
