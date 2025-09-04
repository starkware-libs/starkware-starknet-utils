#[starknet::component]
pub mod clearlist {
    use RolesComponent::InternalTrait as RolesInternalTrait;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::clearlist::events::{Clearlisted, Unclearlisted};
    use starkware_utils::components::clearlist::interface::IClearlist;
    use starkware_utils::components::roles::RolesComponent;

    #[storage]
    pub struct Storage {
        pub clearlist: Map<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        Clearlisted: Clearlisted,
        Unclearlisted: Unclearlisted,
    }

    /// Clearlist component.
    ///
    /// This component implements account clearlisting.
    /// Accounts can be removed from the clearlist by the security admin.
    #[embeddable_as(ClearlistImpl)]
    impl Clearlist<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of IClearlist<ComponentState<TContractState>> {
        /// Returns true if the account is clearlisted, and false otherwise.
        fn is_clearlisted(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            self.clearlist.read(account)
        }

        /// Clear an account.
        ///
        /// Can be called only by security admin.
        fn add_to_clearlist(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_security_admin();
            self.clearlist.write(account, true);
            self.emit(Clearlisted { account, caller: get_caller_address() });
        }

        /// Unclear an account.
        ///
        /// Can be called only by security admin.
        fn remove_from_clearlist(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_security_admin();
            self.clearlist.write(account, false);
            self.emit(Unclearlisted { account, caller: get_caller_address() });
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Ensures that the specified account is clearlisted.
        ///
        /// Intended for use by the contract integrating this component.
        fn assert_cleared(self: @ComponentState<TContractState>, account: ContractAddress) {
            assert!(self.clearlist.read(account), "NOT CLEARLISTED: {:?}", account);
        }
    }
}
