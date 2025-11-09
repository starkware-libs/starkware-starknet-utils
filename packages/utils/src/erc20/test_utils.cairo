use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::ContractAddress;

pub fn deploy_mock_erc20_contract(
    initial_supply: u256,
    owner_address: ContractAddress,
    name: ByteArray,
    symbol: ByteArray,
    decimals: u8,
) -> ContractAddress {
    let mut calldata = ArrayTrait::new();
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    decimals.serialize(ref calldata);
    initial_supply.serialize(ref calldata);
    owner_address.serialize(ref calldata);
    let erc20_contract = snforge_std::declare("DualCaseERC20Mock").unwrap().contract_class();
    let (token_address, _) = erc20_contract.deploy(@calldata).unwrap();
    token_address
}
