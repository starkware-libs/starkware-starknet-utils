#[starknet::component]
pub(crate) mod CommonRolesComponent {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::accesscontrol::AccessControlComponent::{
        AccessControlImpl, InternalTrait as AccessInternalTrait,
    };
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{
        StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::roles::errors::AccessErrors;
    use starkware_utils::components::roles::interface::{
        APP_GOVERNOR, APP_ROLE_ADMIN, GOVERNANCE_ADMIN, ICommonRoles, OPERATOR, Role, RoleId,
        SECURITY_ADMIN, SECURITY_AGENT, SECURITY_GOVERNOR, TOKEN_ADMIN, UPGRADE_AGENT,
        UPGRADE_GOVERNOR, is_renounceable,
    };

    pub const ROLE_ADMIN_PAIRS: [(RoleId, RoleId); 10] = [
        (APP_GOVERNOR, APP_ROLE_ADMIN), (APP_ROLE_ADMIN, GOVERNANCE_ADMIN),
        (GOVERNANCE_ADMIN, GOVERNANCE_ADMIN), (OPERATOR, APP_ROLE_ADMIN),
        (TOKEN_ADMIN, APP_ROLE_ADMIN), (UPGRADE_AGENT, APP_ROLE_ADMIN),
        (UPGRADE_GOVERNOR, GOVERNANCE_ADMIN), (SECURITY_ADMIN, SECURITY_ADMIN),
        (SECURITY_AGENT, SECURITY_ADMIN), (SECURITY_GOVERNOR, SECURITY_ADMIN),
    ];

    #[storage]
    pub struct Storage {
        // LEGACY: Old role-membership map from before OZ AccessControl integration.
        // Kept to allow one-time reclaim migration. Read-only after initialize().
        role_members: starknet::storage::Map<(RoleId, ContractAddress), bool>,
        // Once set, legacy reclaim is permanently disabled.
        legacy_role_reclaim_disabled: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(CommonRolesImpl)]
    pub impl CommonRoles<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of ICommonRoles<ComponentState<TContractState>> {
        fn grant_role(
            ref self: ComponentState<TContractState>, role: Role, account: ContractAddress,
        ) {
            InternalTrait::grant_role(ref self, :role, :account);
        }

        fn revoke_role(
            ref self: ComponentState<TContractState>, role: Role, account: ContractAddress,
        ) {
            InternalTrait::revoke_role(ref self, :role, :account);
        }

        fn has_role(
            self: @ComponentState<TContractState>, role: Role, account: ContractAddress,
        ) -> bool {
            InternalTrait::has_role(self, role, account)
        }

        fn renounce(ref self: ComponentState<TContractState>, role: Role) {
            assert!(is_renounceable(role), "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            let role_id: RoleId = role.into();
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp.renounce_role(role: role_id, account: get_caller_address());
        }

        fn reclaim_legacy_roles(ref self: ComponentState<TContractState>) {
            InternalTrait::assert_role_reclaim_enabled(@self);
            InternalTrait::_reclaim_legacy_roles_for_account(ref self, get_caller_address());
            InternalTrait::ensure_role_admins(ref self);
        }

        fn reclaim_legacy_roles_for_accounts(
            ref self: ComponentState<TContractState>, accounts: Span<ContractAddress>,
        ) {
            InternalTrait::only_security_governor(@self);
            InternalTrait::assert_role_reclaim_enabled(@self);
            for account in accounts {
                InternalTrait::_reclaim_legacy_roles_for_account(ref self, *account);
            };
        }

        fn disable_legacy_role_reclaim(ref self: ComponentState<TContractState>) {
            InternalTrait::only_upgrade_governor(@self);
            self.legacy_role_reclaim_disabled.write(true);
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        // WARNING
        // Unprotected — call only from constructor (or test setup).
        fn initialize(ref self: ComponentState<TContractState>, governance_admin: ContractAddress) {
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            let uninitialized = access_comp.get_role_admin(role: GOVERNANCE_ADMIN).is_zero();
            assert!(uninitialized, "{}", AccessErrors::ALREADY_INITIALIZED);
            access_comp.initializer();
            assert!(governance_admin.is_non_zero(), "{}", AccessErrors::ZERO_ADDRESS_GOV_ADMIN);
            access_comp._grant_role(role: GOVERNANCE_ADMIN, account: governance_admin);
            access_comp._grant_role(role: SECURITY_ADMIN, account: governance_admin);
            Self::_set_role_admins(ref access_comp);
            // Fresh contracts have no legacy storage — disable reclaim immediately.
            self.legacy_role_reclaim_disabled.write(true);
        }

        fn _set_role_admins(
            ref access_comp: AccessControlComponent::ComponentState<TContractState>,
        ) {
            for (role, admin_role) in ROLE_ADMIN_PAIRS.span() {
                if access_comp.get_role_admin(role: *role).is_zero() {
                    access_comp.set_role_admin(role: *role, admin_role: *admin_role);
                }
            }
        }

        // WARNING
        // Unprotected — intended for use by contracts performing an upgrade migration
        // that adds new roles to an already-initialized deployment. Idempotent: only sets
        // role-admin pairs that are currently zero, so safe to call on a fresh contract too.
        fn ensure_role_admins(ref self: ComponentState<TContractState>) {
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            Self::_set_role_admins(ref access_comp);
        }

        fn has_role(
            self: @ComponentState<TContractState>, role: Role, account: ContractAddress,
        ) -> bool {
            let role_id: RoleId = role.into();
            let access_comp = get_dep_component!(self, Access);
            access_comp.has_role(role: role_id, :account)
        }

        /// Grants `role` to `account`. Enforces caller is the role's admin (via OZ grant_role).
        fn grant_role(
            ref self: ComponentState<TContractState>, role: Role, account: ContractAddress,
        ) {
            assert!(account.is_non_zero(), "{}", AccessErrors::ZERO_ADDRESS);
            let role: RoleId = role.into();
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp.grant_role(:role, :account);
        }

        /// Revokes `role` from `account`. Blocks self-revoke of non-renounceable roles.
        /// Enforces caller is the role's admin (via OZ revoke_role).
        fn revoke_role(
            ref self: ComponentState<TContractState>, role: Role, account: ContractAddress,
        ) {
            assert!(
                get_caller_address() != account || is_renounceable(role),
                "{}",
                AccessErrors::ROLE_CANNOT_BE_RENOUNCED,
            );
            let role: RoleId = role.into();
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp.revoke_role(:role, :account);
        }

        fn only_role(self: @ComponentState<TContractState>, role: Role) {
            let role_id: RoleId = role.into();
            let access_comp = get_dep_component!(self, Access);
            assert!(
                access_comp.has_role(role: role_id, account: get_caller_address()),
                "{}",
                AccessErrors::CALLER_MISSING_ROLE,
            );
        }

        fn only_app_governor(self: @ComponentState<TContractState>) {
            let access_comp = get_dep_component!(self, Access);
            assert!(
                access_comp.has_role(role: APP_GOVERNOR, account: get_caller_address()),
                "{}",
                AccessErrors::ONLY_APP_GOVERNOR,
            );
        }

        fn only_operator(self: @ComponentState<TContractState>) {
            let access_comp = get_dep_component!(self, Access);
            assert!(
                access_comp.has_role(role: OPERATOR, account: get_caller_address()),
                "{}",
                AccessErrors::ONLY_OPERATOR,
            );
        }

        fn only_token_admin(self: @ComponentState<TContractState>) {
            let access_comp = get_dep_component!(self, Access);
            assert!(
                access_comp.has_role(role: TOKEN_ADMIN, account: get_caller_address()),
                "{}",
                AccessErrors::ONLY_TOKEN_ADMIN,
            );
        }

        fn only_upgrade_governor(self: @ComponentState<TContractState>) {
            let access_comp = get_dep_component!(self, Access);
            assert!(
                access_comp.has_role(role: UPGRADE_GOVERNOR, account: get_caller_address()),
                "{}",
                AccessErrors::ONLY_UPGRADE_GOVERNOR,
            );
        }

        fn only_upgrader(self: @ComponentState<TContractState>) {
            let access_comp = get_dep_component!(self, Access);
            let caller = get_caller_address();
            assert!(
                access_comp.has_role(role: UPGRADE_AGENT, account: caller)
                    || access_comp.has_role(role: UPGRADE_GOVERNOR, account: caller),
                "{}",
                AccessErrors::ONLY_UPGRADER,
            );
        }

        fn only_security_admin(self: @ComponentState<TContractState>) {
            let access_comp = get_dep_component!(self, Access);
            assert!(
                access_comp.has_role(role: SECURITY_ADMIN, account: get_caller_address()),
                "{}",
                AccessErrors::ONLY_SECURITY_ADMIN,
            );
        }

        fn only_security_agent(self: @ComponentState<TContractState>) {
            let access_comp = get_dep_component!(self, Access);
            assert!(
                access_comp.has_role(role: SECURITY_AGENT, account: get_caller_address()),
                "{}",
                AccessErrors::ONLY_SECURITY_AGENT,
            );
        }

        fn only_security_governor(self: @ComponentState<TContractState>) {
            let access_comp = get_dep_component!(self, Access);
            assert!(
                access_comp.has_role(role: SECURITY_GOVERNOR, account: get_caller_address()),
                "{}",
                AccessErrors::ONLY_SECURITY_GOVERNOR,
            );
        }

        fn assert_role_reclaim_enabled(self: @ComponentState<TContractState>) {
            assert!(
                !self.legacy_role_reclaim_disabled.read(),
                "{}",
                AccessErrors::LEGACY_ROLE_RECLAIM_DISABLED,
            );
        }

        fn _has_legacy_role(
            self: @ComponentState<TContractState>, account: ContractAddress, role: RoleId,
        ) -> bool {
            self.role_members.read((role, account))
        }

        fn _reclaim_role(
            ref self: ComponentState<TContractState>, role: RoleId, account: ContractAddress,
        ) {
            if self._has_legacy_role(account, role) {
                self.role_members.write((role, account), false);
                let mut access_comp = get_dep_component_mut!(ref self, Access);
                access_comp._grant_role(:role, :account);
            }
        }

        fn _reclaim_legacy_roles_for_account(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            for (role, _) in ROLE_ADMIN_PAIRS.span() {
                self._reclaim_role(role: *role, :account);
            }
        }
    }
}
