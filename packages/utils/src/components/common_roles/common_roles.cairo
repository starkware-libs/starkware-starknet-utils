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

    // Maps each role to its admin role — used both at initialization (to configure OZ
    // AccessControl)
    // and during legacy role reclaim (to ensure admin pairs are set on upgraded contracts).
    // `GOVERNANCE_ADMIN` and `SECURITY_ADMIN` are self-administered (admin == role).
    pub const ROLE_ADMIN_PAIRS: [(RoleId, RoleId); 10] = [
        (APP_GOVERNOR, APP_ROLE_ADMIN), (APP_ROLE_ADMIN, GOVERNANCE_ADMIN),
        (GOVERNANCE_ADMIN, GOVERNANCE_ADMIN), (OPERATOR, APP_ROLE_ADMIN),
        (TOKEN_ADMIN, APP_ROLE_ADMIN), (UPGRADE_AGENT, APP_ROLE_ADMIN),
        (UPGRADE_GOVERNOR, GOVERNANCE_ADMIN), (SECURITY_ADMIN, SECURITY_ADMIN),
        (SECURITY_AGENT, SECURITY_ADMIN), (SECURITY_GOVERNOR, SECURITY_ADMIN),
    ];

    #[storage]
    pub struct Storage {
        // LEGACY: Role-membership map from before OZ AccessControl integration.
        // Written only by the legacy reclaim path (_reclaim_role erases each entry as it migrates
        // it to OZ storage). Private — test mocks access it via the #[rename] storage-collision
        // trick rather than requiring pub visibility on production code.
        role_members: starknet::storage::Map<(RoleId, ContractAddress), bool>,
        // Guards the one-time reclaim window. Fresh contracts set this to `true` in `initialize`;
        // legacy-upgraded contracts leave it `false` until the upgrade is complete and
        // `disable_legacy_role_reclaim` is called by an upgrade governor.
        legacy_role_reclaim_disabled: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    // ─── Public ABI (ICommonRoles)
    // ────────────────────────────────────────────
    // These 7 entry points are the minimal role-management surface. They are the
    // only role-related entry points on Tier-A contracts (CommonRolesComponent
    // only), and they complement the named-role entry points on Tier-B/C contracts
    // (RolesComponent adds IRoles / category interfaces on top).
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
            // GOVERNANCE_ADMIN and SECURITY_ADMIN are non-renounceable — self-removal of those
            // roles would leave the contract permanently ungovernable / un-paused.
            assert!(is_renounceable(role), "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            let role_id: RoleId = role.into();
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp.renounce_role(role: role_id, account: get_caller_address());
        }

        // Allows the caller to migrate their own roles from legacy storage to OZ AccessControl.
        // Also calls ensure_role_admins in case this is the first account to reclaim on a
        // contract that was upgraded without going through initialize().
        fn reclaim_legacy_roles(ref self: ComponentState<TContractState>) {
            InternalTrait::assert_role_reclaim_enabled(@self);
            InternalTrait::_reclaim_legacy_roles_for_account(ref self, get_caller_address());
            InternalTrait::ensure_role_admins(ref self);
        }

        // Batch version gated behind SECURITY_GOVERNOR — intended for the upgrade governor to
        // migrate multiple accounts in one tx. ensure_role_admins is not called here because the
        // upgrade constructor always calls it before any account can reach this path.
        fn reclaim_legacy_roles_for_accounts(
            ref self: ComponentState<TContractState>, accounts: Span<ContractAddress>,
        ) {
            InternalTrait::only_security_governor(@self);
            InternalTrait::assert_role_reclaim_enabled(@self);
            for account in accounts {
                InternalTrait::_reclaim_legacy_roles_for_account(ref self, *account);
            };
        }

        // Permanently closes the reclaim window. Idempotent. Called by an upgrade governor
        // once all legacy roles have been migrated.
        fn disable_legacy_role_reclaim(ref self: ComponentState<TContractState>) {
            InternalTrait::only_upgrade_governor(@self);
            self.legacy_role_reclaim_disabled.write(true);
        }
    }

    // ─── Internal helpers
    // ─────────────────────────────────────────────────────
    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        // WARNING
        // Unprotected — call only from a constructor (or test setup).
        // Sets up OZ AccessControl (initializer + role admin pairs), grants GOVERNANCE_ADMIN and
        // SECURITY_ADMIN to `governance_admin`, then immediately disables legacy role reclaim
        // (fresh contracts have no legacy storage to migrate).
        fn initialize(ref self: ComponentState<TContractState>, governance_admin: ContractAddress) {
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            // Detect double-initialization: if GOVERNANCE_ADMIN already has an admin it means
            // initialize() was already called on this deployment.
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

        // Idempotent: only sets admin pairs whose current admin is zero. This lets it be called
        // on both fresh deployments and upgrades without overwriting intentional customization.
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
        /// Rejects the zero address — granting a role to zero is always a mistake and can make
        /// the role permanently inaccessible if it is self-administered (e.g., GOVERNANCE_ADMIN).
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

        // ─── Role guards
        // ─────────────────────────────────────────────────────
        // These are the canonical authorization checks. Both `CommonRolesComponent` and
        // `RolesComponent` expose them as internal methods so sibling components can call
        // them without going through the public ABI.
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

        // NOTE: parameter order is (account, role) but the storage key is (role, account) —
        // intentional, but keep in mind when reading call sites.
        fn _has_legacy_role(
            self: @ComponentState<TContractState>, account: ContractAddress, role: RoleId,
        ) -> bool {
            self.role_members.read((role, account))
        }

        // Migrates a single (role, account) entry: clears the legacy map entry and grants
        // the role in OZ AccessControl. No-op if the account doesn't hold the role in legacy
        // storage — safe to call unconditionally for all roles.
        fn _reclaim_role(
            ref self: ComponentState<TContractState>, role: RoleId, account: ContractAddress,
        ) {
            if self._has_legacy_role(account, role) {
                self.role_members.write((role, account), false);
                let mut access_comp = get_dep_component_mut!(ref self, Access);
                access_comp._grant_role(:role, :account);
            }
        }

        // Iterates all 10 known roles for one account. O(10) regardless of which roles the
        // account actually holds — acceptable for a one-time migration path.
        fn _reclaim_legacy_roles_for_account(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            for (role, _) in ROLE_ADMIN_PAIRS.span() {
                self._reclaim_role(role: *role, :account);
            }
        }
    }
}
