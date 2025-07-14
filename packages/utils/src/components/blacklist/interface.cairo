use starknet::ContractAddress;

#[starknet::interface]
pub trait IBlacklist<TState> {
    fn is_blacklisted(self: @TState, account: ContractAddress) -> bool;
    fn add_to_blacklist(ref self: TState, account: ContractAddress) -> bool;
    fn remove_from_blacklist(ref self: TState, account: ContractAddress) -> bool;
}
