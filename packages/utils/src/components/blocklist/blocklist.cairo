#[starknet::component]
pub mod blocklist {
    use RolesComponent::InternalTrait as RolesInternalTrait;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::blocklist::events::{Blocklisted, Unblocklisted};
    use starkware_utils::components::blocklist::interface::IBlocklist;
    use starkware_utils::components::roles::RolesComponent;

    #[storage]
    pub struct Storage {
        pub blocklist: Map<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        Blocklisted: Blocklisted,
        Unblocklisted: Unblocklisted,
    }

    /// Blocklist component.
    ///
    /// This component implements account blocklisting.
    /// Accounts can be removed from the blocklist by the security admin.
    #[embeddable_as(BlocklistImpl)]
    impl Blocklist<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of IBlocklist<ComponentState<TContractState>> {
        /// Returns true if the account is blocklisted, and false otherwise.
        fn is_blocklisted(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            self.blocklist.read(account)
        }

        /// Block an account.
        ///
        /// Can be called only by security admin.
        fn add_to_blocklist(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_security_admin();
            self.blocklist.write(account, true);
            self.emit(Blocklisted { account, caller: get_caller_address() });
        }

        /// Unblock an account.
        ///
        /// Can be called only by security admin.
        fn remove_from_blocklist(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_security_admin();
            self.blocklist.write(account, false);
            self.emit(Unblocklisted { account, caller: get_caller_address() });
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Ensures that the specified account is not present in the blocklist.
        ///
        /// Intended for use by the contract integrating this component.
        fn assert_not_blocked(self: @ComponentState<TContractState>, account: ContractAddress) {
            assert!(!self.blocklist.read(account), "BLOCKLISTED: {:?}", account);
        }
    }
}
