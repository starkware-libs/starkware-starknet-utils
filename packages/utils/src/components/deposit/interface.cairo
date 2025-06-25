use starknet::ContractAddress;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::{TimeDelta, Timestamp};


#[starknet::interface]
pub trait IDeposit<TContractState> {
    fn deposit(
        ref self: TContractState,
        beneficiary: u32,
        asset_id: felt252,
        quantized_amount: u128,
        salt: felt252,
    );
    fn cancel_deposit(
        ref self: TContractState,
        beneficiary: u32,
        asset_id: felt252,
        quantized_amount: u128,
        salt: felt252,
    );
    fn get_deposit_status(self: @TContractState, deposit_hash: HashType) -> DepositStatus;
    fn get_asset_info(self: @TContractState, asset_id: felt252) -> (ContractAddress, u64);
    fn get_cancel_delay(self: @TContractState) -> TimeDelta;
}

#[derive(Debug, Drop, PartialEq, Serde, starknet::Store)]
pub enum DepositStatus {
    #[default]
    NOT_REGISTERED,
    PROCESSED,
    CANCELED,
    PENDING: Timestamp,
}
