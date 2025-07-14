use starknet::ContractAddress;

#[starknet::interface]
pub trait IBlocklist<TState> {
    fn is_blocklisted(self: @TState, account: ContractAddress) -> bool;
    fn add_to_blocklist(ref self: TState, account: ContractAddress);
    fn remove_from_blocklist(ref self: TState, account: ContractAddress);
}
