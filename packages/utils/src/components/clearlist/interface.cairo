use starknet::ContractAddress;

#[starknet::interface]
pub trait IClearlist<TState> {
    fn is_clearlisted(self: @TState, account: ContractAddress) -> bool;
    fn add_to_clearlist(ref self: TState, account: ContractAddress);
    fn remove_from_clearlist(ref self: TState, account: ContractAddress);
}
