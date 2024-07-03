use starknet::{ContractAddress, contract_address_const};


impl ContractAddressDefault of Default<ContractAddress> {
    fn default() -> ContractAddress {
        contract_address_const::<0>()
    }
}

impl OptionDefault<T> of Default<Option<T>> {
    fn default() -> Option<T> {
        Option::None
    }
}
