use starknet::ContractAddress;

#[starknet::interface]
pub trait IMintableToken<TContractState> {
    fn permissioned_mint(ref self: TContractState, account: ContractAddress, amount: u256);
    fn permissioned_burn(ref self: TContractState, account: ContractAddress, amount: u256);
    fn is_permitted_minter(self: @TContractState, account: ContractAddress) -> bool;
}
