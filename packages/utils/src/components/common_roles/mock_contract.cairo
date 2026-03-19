/// Backdoor for setting legacy role membership in tests.
#[starknet::interface]
pub(crate) trait ILegacySetup<TState> {
    fn set_legacy_role(ref self: TState, role_id: felt252, account: starknet::ContractAddress);
}

/// Simulates a contract that was deployed with the old role storage and then upgraded to
/// CommonRolesComponent without calling `initialize` (so `legacy_role_reclaim_disabled`
/// remains false, and legacy role data can be reclaimed).
#[starknet::contract]
pub(crate) mod LegacyCommonRolesMock {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::accesscontrol::AccessControlComponent::InternalTrait as AccessInternalTrait;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::StorageMapWriteAccess;
    use starkware_utils::components::common_roles::CommonRolesComponent;
    use starkware_utils::components::common_roles::CommonRolesComponent::InternalTrait as CommonRolesInternalTrait;
    use starkware_utils::components::roles::interface::{GOVERNANCE_ADMIN, SECURITY_ADMIN};
    use super::ILegacySetup;

    component!(path: CommonRolesComponent, storage: common_roles, event: CommonRolesEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[storage]
    #[allow(starknet::colliding_storage_paths)]
    struct Storage {
        #[substorage(v0)]
        common_roles: CommonRolesComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // Collides with CommonRolesComponent::role_members via substorage(v0) flat layout.
        // Used only for test setup — allows writing legacy role entries without pub visibility.
        #[rename("role_members")]
        legacy_role_members: starknet::storage::Map<(felt252, ContractAddress), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub(crate) enum Event {
        CommonRolesEvent: CommonRolesComponent::Event,
        AccessControlEvent: AccessControlComponent::Event,
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, governance_admin: ContractAddress) {
        // Migrate path: wire roles without initialize(), leaving
        // legacy_role_reclaim_disabled=false.
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(role: GOVERNANCE_ADMIN, account: governance_admin);
        self.accesscontrol._grant_role(role: SECURITY_ADMIN, account: governance_admin);
        self.common_roles.ensure_role_admins();
    }

    #[abi(embed_v0)]
    impl CommonRolesImpl = CommonRolesComponent::CommonRolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl LegacySetupImpl of ILegacySetup<ContractState> {
        fn set_legacy_role(ref self: ContractState, role_id: felt252, account: ContractAddress) {
            self.legacy_role_members.write((role_id, account), true);
        }
    }
}

#[starknet::interface]
pub(crate) trait IGuardTest<TState> {
    fn assert_only_role(self: @TState, role: starkware_utils::components::roles::interface::Role);
    fn assert_only_app_governor(self: @TState);
    fn assert_only_operator(self: @TState);
    fn assert_only_token_admin(self: @TState);
    fn assert_only_upgrade_governor(self: @TState);
    fn assert_only_upgrader(self: @TState);
    fn assert_only_security_admin(self: @TState);
    fn assert_only_security_agent(self: @TState);
    fn assert_only_security_governor(self: @TState);
}

#[starknet::contract]
pub(crate) mod CommonRolesMock {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starkware_utils::components::common_roles::CommonRolesComponent;
    use starkware_utils::components::common_roles::CommonRolesComponent::InternalTrait as CommonRolesInternalTrait;
    use starkware_utils::components::roles::interface::Role;
    use super::IGuardTest;

    component!(path: CommonRolesComponent, storage: common_roles, event: CommonRolesEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        common_roles: CommonRolesComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub(crate) enum Event {
        CommonRolesEvent: CommonRolesComponent::Event,
        AccessControlEvent: AccessControlComponent::Event,
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, governance_admin: ContractAddress) {
        self.common_roles.initialize(:governance_admin);
    }

    #[abi(embed_v0)]
    impl CommonRolesImpl = CommonRolesComponent::CommonRolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl GuardTestImpl of IGuardTest<ContractState> {
        fn assert_only_role(self: @ContractState, role: Role) {
            self.common_roles.only_role(:role);
        }
        fn assert_only_app_governor(self: @ContractState) {
            self.common_roles.only_app_governor();
        }
        fn assert_only_operator(self: @ContractState) {
            self.common_roles.only_operator();
        }
        fn assert_only_token_admin(self: @ContractState) {
            self.common_roles.only_token_admin();
        }
        fn assert_only_upgrade_governor(self: @ContractState) {
            self.common_roles.only_upgrade_governor();
        }
        fn assert_only_upgrader(self: @ContractState) {
            self.common_roles.only_upgrader();
        }
        fn assert_only_security_admin(self: @ContractState) {
            self.common_roles.only_security_admin();
        }
        fn assert_only_security_agent(self: @ContractState) {
            self.common_roles.only_security_agent();
        }
        fn assert_only_security_governor(self: @ContractState) {
            self.common_roles.only_security_governor();
        }
    }
}
