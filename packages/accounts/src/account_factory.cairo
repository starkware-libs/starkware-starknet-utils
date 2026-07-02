use starknet::secp256_trait::Signature;
use starknet::{ClassHash, ContractAddress, EthAddress};

#[starknet::interface]
pub trait IAccountFactory<TContractState> {
    fn account_class_hash(self: @TContractState) -> ClassHash;
    fn set_account_class_hash(ref self: TContractState, new_class_hash: ClassHash);
    fn deploy_account(
        ref self: TContractState, eth_address: EthAddress, signature: Signature,
    ) -> ContractAddress;
    /// Returns the deterministic account address for the given Ethereum address,
    /// whether or not it has been deployed.
    fn get_expected_account_address(
        self: @TContractState, eth_address: EthAddress,
    ) -> ContractAddress;
    /// Returns the account address for the given Ethereum address if it is deployed,
    /// or zero otherwise.
    fn get_account(self: @TContractState, eth_address: EthAddress) -> ContractAddress;
}

/// Interface to the `Primer` contract; the factory uses only `set_class_hash`.
#[starknet::interface]
pub trait IPrimer<TContractState> {
    fn set_class_hash(ref self: TContractState, new_class_hash: ClassHash);
}

#[starknet::contract]
pub mod AccountFactory {
    use RolesComponent::InternalTrait as RolesInternalTrait;
    use core::num::traits::Zero;
    use core::traits::Into;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::eth_address::EthAddress;
    use starknet::secp256_trait::Signature;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, syscalls};
    use starkware_accounts::account_factory::{
        IAccountFactory, IPrimerDispatcher, IPrimerDispatcherTrait,
    };
    use starkware_accounts::utils::{
        IEthAccountInitializerDispatcher, IEthAccountInitializerDispatcherTrait, PRIMER_CLASS_HASH,
        eth_address_to_account, is_deployed,
    };
    use starkware_utils::components::common_roles::CommonRolesComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: CommonRolesComponent, storage: common_roles, event: CommonRolesEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: accesscontrolEvent);
    component!(path: SRC5Component, storage: src5, event: src5Event);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;
    #[abi(embed_v0)]
    impl CommonRolesImpl = CommonRolesComponent::CommonRolesImpl<ContractState>;
    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        #[substorage(v0)]
        common_roles: CommonRolesComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        account_class_hash: ClassHash,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        CommonRolesEvent: CommonRolesComponent::Event,
        #[flat]
        accesscontrolEvent: AccessControlComponent::Event,
        #[flat]
        src5Event: SRC5Component::Event,
        AccountClassHashChanged: AccountClassHashChanged,
        AccountDeployed: AccountDeployed,
    }

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct AccountClassHashChanged {
        pub previous_class_hash: ClassHash,
        pub new_class_hash: ClassHash,
    }

    #[derive(Drop, starknet::Event, Debug, PartialEq)]
    pub struct AccountDeployed {
        pub account_class_hash: ClassHash,
        pub eth_address: EthAddress,
        pub account_address: ContractAddress,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        account_class_hash: ClassHash,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self.account_class_hash.write(account_class_hash);
    }

    #[abi(embed_v0)]
    impl AccountFactoryImpl of IAccountFactory<ContractState> {
        fn account_class_hash(self: @ContractState) -> ClassHash {
            self.account_class_hash.read()
        }

        fn get_expected_account_address(
            self: @ContractState, eth_address: EthAddress,
        ) -> ContractAddress {
            eth_address_to_account(:eth_address)
        }

        fn get_account(self: @ContractState, eth_address: EthAddress) -> ContractAddress {
            let account_address = eth_address_to_account(:eth_address);
            if is_deployed(addr: account_address) {
                account_address
            } else {
                Zero::zero()
            }
        }

        fn set_account_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            self.roles.only_app_governor();
            let previous_class_hash = self.account_class_hash();
            if previous_class_hash == new_class_hash {
                return;
            }
            self.account_class_hash.write(new_class_hash);
            self
                .emit(
                    Event::AccountClassHashChanged(
                        AccountClassHashChanged { previous_class_hash, new_class_hash },
                    ),
                );
        }

        /// Returns the deterministic account contract address for the given Ethereum
        /// address, deploying and upgrading a Primer contract on first use.
        fn deploy_account(
            ref self: ContractState, eth_address: EthAddress, signature: Signature,
        ) -> ContractAddress {
            let account_address = eth_address_to_account(:eth_address);
            // If the account contract is deployed, return the address.
            if is_deployed(addr: account_address) {
                return account_address;
            }

            // Deployment of the account contract is done in three steps:
            // 1. Deploy a primer contract to get a deterministic address.
            // 2. Replace to the actual class-hash.
            // 3. Initialize the account contract.
            let (deployed_address, _retdata) = syscalls::deploy_syscall(
                class_hash: PRIMER_CLASS_HASH,
                contract_address_salt: eth_address.into(),
                calldata: [].span(),
                deploy_from_zero: false,
            )
                .unwrap_syscall();
            // Assert that the address returned is the same as the address we expected.
            assert(deployed_address == account_address, 'ACCOUNT_ADDRESS_MISMATCH');

            // Upgrade the primer contract to the current account class hash.
            let primer = IPrimerDispatcher { contract_address: account_address };
            let account_class_hash = self.account_class_hash.read();
            primer.set_class_hash(new_class_hash: account_class_hash);

            let eth_account_initializer = IEthAccountInitializerDispatcher {
                contract_address: account_address,
            };
            eth_account_initializer.initialize(:eth_address, :signature);
            self
                .emit(
                    Event::AccountDeployed(
                        AccountDeployed { account_class_hash, eth_address, account_address },
                    ),
                );

            account_address
        }
    }
}
