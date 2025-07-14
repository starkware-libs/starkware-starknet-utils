#[starknet::component]
pub mod blacklist {
    use RolesComponent::InternalTrait as RolesInternalTrait;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starkware_utils::components::blacklist::events::{Blacklisted, Unblacklisted};
    use starkware_utils::components::blacklist::interface::IBlacklist;
    use starkware_utils::components::roles::RolesComponent;

    #[storage]
    pub struct Storage {
        pub blacklist: Map<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        Blacklisted: Blacklisted,
        Unblacklisted: Unblacklisted,
    }

    /// Blacklist component.
    ///
    /// This component allows to blacklist accounts.
    ///
    /// Blacklisted accounts are not allowed to interact with the contract.
    ///
    /// Blacklisted accounts can be removed from the blacklist by the security admin.
    #[embeddable_as(BlacklistImpl)]
    impl Blacklist<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of IBlacklist<ComponentState<TContractState>> {
        /// Returns true if the account is blacklisted, and false otherwise.
        fn is_blacklisted(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            self.blacklist.read(account)
        }

        /// Adds an account to the blacklist.
        ///
        /// Requirements:
        /// - Caller must have the security agent role.
        ///
        /// Emits a `Blacklisted` event.
        ///
        /// Returns:
        /// - `true` if the account was successfully added to the blacklist.
        fn add_to_blacklist(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            let roles = get_dep_component!(@self, Roles);
            roles.only_security_agent();
            self.blacklist.write(account, true);
            self.emit(Blacklisted { account });
            true
        }

        /// Removes an account from the blacklist.
        ///
        /// Requirements:
        /// - Caller must have the security admin role.
        ///
        /// Emits an `Unblacklisted` event.
        ///
        /// Returns:
        /// - `true` if the account was successfully removed from the blacklist.
        fn remove_from_blacklist(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            let roles = get_dep_component!(@self, Roles);
            roles.only_security_admin();
            self.blacklist.write(account, false);
            self.emit(Unblacklisted { account });
            true
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn assert_not_blacklisted(self: @ComponentState<TContractState>, account: ContractAddress) {
            assert(!self.blacklist.read(account), 'BLACKLISTED');
        }
    }
}
