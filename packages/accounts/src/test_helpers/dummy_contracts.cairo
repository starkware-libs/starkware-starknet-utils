use snforge_std::DeclareResultTrait;
use starknet::{ClassHash, SyscallResultTrait};

/// Minimal no-op account target for tests: implements `IEthAccountInitializer` so the factory can
/// call `initialize` after upgrading the Primer into it.
#[starknet::contract]
pub mod DummyEthAddressContract {
    use starknet::eth_address::EthAddress;
    use starknet::secp256_trait::Signature;
    use starkware_accounts::utils::IEthAccountInitializer;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl Initializer of IEthAccountInitializer<ContractState> {
        fn initialize(ref self: ContractState, eth_address: EthAddress, signature: Signature) {}
    }
}

/// Declare the `DummyEthAddressContract` contract and return its class hash.
pub fn declare_dummy_eth_address_contract() -> ClassHash {
    *snforge_std::declare("DummyEthAddressContract").unwrap_syscall().contract_class().class_hash
}

/// Second dummy with a different class hash (via a constructor) for upgrade testing.
#[starknet::contract]
pub mod SecondDummyEthAddressContract {
    use starknet::eth_address::EthAddress;
    use starknet::secp256_trait::Signature;
    use starkware_accounts::utils::IEthAccountInitializer;

    #[storage]
    struct Storage {}

    #[constructor]
    pub fn constructor(ref self: ContractState) {
        // Present only to give this contract a different class hash from the first dummy.
        assert!(true, "ERROR");
    }

    #[abi(embed_v0)]
    impl Initializer of IEthAccountInitializer<ContractState> {
        fn initialize(ref self: ContractState, eth_address: EthAddress, signature: Signature) {}
    }
}

/// Declare the `SecondDummyEthAddressContract` contract and return its class hash.
pub fn declare_second_dummy_eth_address_contract() -> ClassHash {
    *snforge_std::declare("SecondDummyEthAddressContract")
        .unwrap_syscall()
        .contract_class()
        .class_hash
}
