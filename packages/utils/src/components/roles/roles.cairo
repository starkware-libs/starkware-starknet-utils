#[starknet::component]
pub(crate) mod RolesComponent {
    use RolesInterface::{
        APP_GOVERNOR, APP_ROLE_ADMIN, AppGovernorAdded, AppGovernorRemoved, AppRoleAdminAdded,
        AppRoleAdminRemoved, GOVERNANCE_ADMIN, GovernanceAdminAdded, GovernanceAdminRemoved,
        IAppRoles, IGovernanceRoles, IRoles, ISecurityRoles, OPERATOR, OperatorAdded,
        OperatorRemoved, RoleId, SECURITY_ADMIN, SECURITY_AGENT, SECURITY_GOVERNOR,
        SecurityAdminAdded, SecurityAdminRemoved, SecurityAgentAdded, SecurityAgentRemoved,
        SecurityGovernorAdded, SecurityGovernorRemoved, TOKEN_ADMIN, TokenAdminAdded,
        TokenAdminRemoved, UPGRADE_AGENT, UPGRADE_GOVERNOR, UpgradeAgentAdded, UpgradeAgentRemoved,
        UpgradeGovernorAdded, UpgradeGovernorRemoved,
    };
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
    use starkware_utils::components::common_roles::CommonRolesComponent;
    use starkware_utils::components::common_roles::CommonRolesComponent::InternalTrait as CommonRolesInternalTrait;
    use starkware_utils::components::roles::errors::AccessErrors;
    use starkware_utils::components::roles::interface as RolesInterface;

    #[storage]
    pub struct Storage {
        // LEGACY: This is the old storage for role members.
        // We need it to allow reclaim legacy roles.
        role_members: starknet::storage::Map<(RoleId, ContractAddress), bool>,
        // Flag to disable legacy role reclaim. Once set, legacy roles cannot be reclaimed.
        legacy_role_reclaim_disabled: bool,
    }

    #[event]
    #[derive(Copy, Drop, PartialEq, starknet::Event)]
    pub enum Event {
        AppGovernorAdded: AppGovernorAdded,
        AppGovernorRemoved: AppGovernorRemoved,
        AppRoleAdminAdded: AppRoleAdminAdded,
        AppRoleAdminRemoved: AppRoleAdminRemoved,
        GovernanceAdminAdded: GovernanceAdminAdded,
        GovernanceAdminRemoved: GovernanceAdminRemoved,
        OperatorAdded: OperatorAdded,
        OperatorRemoved: OperatorRemoved,
        SecurityAdminAdded: SecurityAdminAdded,
        SecurityAdminRemoved: SecurityAdminRemoved,
        SecurityAgentAdded: SecurityAgentAdded,
        SecurityAgentRemoved: SecurityAgentRemoved,
        SecurityGovernorAdded: SecurityGovernorAdded,
        SecurityGovernorRemoved: SecurityGovernorRemoved,
        TokenAdminAdded: TokenAdminAdded,
        TokenAdminRemoved: TokenAdminRemoved,
        UpgradeGovernorAdded: UpgradeGovernorAdded,
        UpgradeGovernorRemoved: UpgradeGovernorRemoved,
        UpgradeAgentAdded: UpgradeAgentAdded,
        UpgradeAgentRemoved: UpgradeAgentRemoved,
    }

    #[embeddable_as(RolesImpl)]
    pub impl Roles<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        impl CommonRoles: CommonRolesComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of IRoles<ComponentState<TContractState>> {
        fn is_app_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: APP_GOVERNOR, :account)
        }

        fn is_app_role_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: APP_ROLE_ADMIN, :account)
        }

        fn is_governance_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: GOVERNANCE_ADMIN, :account)
        }

        fn is_operator(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            get_dep_component!(self, Access).has_role(role: OPERATOR, :account)
        }

        fn is_security_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: SECURITY_ADMIN, :account)
        }

        fn is_security_agent(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: SECURITY_AGENT, :account)
        }

        fn is_security_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: SECURITY_GOVERNOR, :account)
        }

        fn is_token_admin(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            get_dep_component!(self, Access).has_role(role: TOKEN_ADMIN, :account)
        }

        fn is_upgrade_agent(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: UPGRADE_AGENT, :account)
        }

        fn is_upgrade_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: UPGRADE_GOVERNOR, :account)
        }

        fn register_app_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::AppGovernorAdded(
                AppGovernorAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: APP_GOVERNOR, :account, :event);
        }

        fn remove_app_governor(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let event = Event::AppGovernorRemoved(
                AppGovernorRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: APP_GOVERNOR, :account, :event);
        }

        fn register_app_role_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::AppRoleAdminAdded(
                AppRoleAdminAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: APP_ROLE_ADMIN, :account, :event);
        }

        fn remove_app_role_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::AppRoleAdminRemoved(
                AppRoleAdminRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: APP_ROLE_ADMIN, :account, :event);
        }

        fn register_security_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityAdminAdded(
                SecurityAdminAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: SECURITY_ADMIN, :account, :event);
        }

        fn remove_security_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityAdminRemoved(
                SecurityAdminRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: SECURITY_ADMIN, :account, :event);
        }

        fn register_security_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityAgentAdded(
                SecurityAgentAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: SECURITY_AGENT, :account, :event);
        }

        fn remove_security_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityAgentRemoved(
                SecurityAgentRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: SECURITY_AGENT, :account, :event);
        }

        fn register_security_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityGovernorAdded(
                SecurityGovernorAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: SECURITY_GOVERNOR, :account, :event);
        }

        fn remove_security_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityGovernorRemoved(
                SecurityGovernorRemoved {
                    removed_account: account, removed_by: get_caller_address(),
                },
            );
            self._revoke_role_and_emit(role: SECURITY_GOVERNOR, :account, :event);
        }

        fn register_governance_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::GovernanceAdminAdded(
                GovernanceAdminAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: GOVERNANCE_ADMIN, :account, :event);
        }

        fn remove_governance_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let caller_address = get_caller_address();
            assert!(account != caller_address, "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            let event = Event::GovernanceAdminRemoved(
                GovernanceAdminRemoved { removed_account: account, removed_by: caller_address },
            );
            self._revoke_role_and_emit(role: GOVERNANCE_ADMIN, :account, :event);
        }

        fn register_operator(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let event = Event::OperatorAdded(
                OperatorAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: OPERATOR, :account, :event);
        }

        fn remove_operator(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let event = Event::OperatorRemoved(
                OperatorRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: OPERATOR, :account, :event);
        }

        fn register_token_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::TokenAdminAdded(
                TokenAdminAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: TOKEN_ADMIN, :account, :event);
        }

        fn remove_token_admin(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let event = Event::TokenAdminRemoved(
                TokenAdminRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: TOKEN_ADMIN, :account, :event);
        }

        fn register_upgrade_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::UpgradeAgentAdded(
                UpgradeAgentAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: UPGRADE_AGENT, :account, :event);
        }

        fn remove_upgrade_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::UpgradeAgentRemoved(
                UpgradeAgentRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: UPGRADE_AGENT, :account, :event);
        }

        fn register_upgrade_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::UpgradeGovernorAdded(
                UpgradeGovernorAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: UPGRADE_GOVERNOR, :account, :event);
        }

        fn remove_upgrade_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::UpgradeGovernorRemoved(
                UpgradeGovernorRemoved {
                    removed_account: account, removed_by: get_caller_address(),
                },
            );
            self._revoke_role_and_emit(role: UPGRADE_GOVERNOR, :account, :event);
        }

        fn renounce(ref self: ComponentState<TContractState>, role: RoleId) {
            assert!(
                role != GOVERNANCE_ADMIN && role != SECURITY_ADMIN,
                "{}",
                AccessErrors::ROLE_CANNOT_BE_RENOUNCED,
            );
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp.renounce_role(:role, account: get_caller_address())
        }

        fn reclaim_legacy_roles(ref self: ComponentState<TContractState>) {
            self.assert_role_reclaim_enabled();
            self._reclaim_legacy_roles_for_account(get_caller_address());
            let mut common_roles = get_dep_component_mut!(ref self, CommonRoles);
            common_roles.ensure_role_admins();
        }

        fn reclaim_legacy_roles_for_accounts(
            ref self: ComponentState<TContractState>, accounts: Span<ContractAddress>,
        ) {
            self.only_security_governor();
            self.assert_role_reclaim_enabled();
            for account in accounts {
                self._reclaim_legacy_roles_for_account(*account);
            };
        }

        fn disable_legacy_role_reclaim(ref self: ComponentState<TContractState>) {
            self.only_upgrade_governor();
            self.legacy_role_reclaim_disabled.write(true);
        }
    }

    // ─── Category-scoped role impls
    // ───────────────────────────────────────────

    #[embeddable_as(SecurityRolesImpl)]
    pub impl SecurityRoles<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        impl CommonRoles: CommonRolesComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of ISecurityRoles<ComponentState<TContractState>> {
        fn is_security_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: SECURITY_ADMIN, :account)
        }

        fn register_security_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityAdminAdded(
                SecurityAdminAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: SECURITY_ADMIN, :account, :event);
        }

        fn remove_security_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityAdminRemoved(
                SecurityAdminRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: SECURITY_ADMIN, :account, :event);
        }

        fn is_security_agent(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: SECURITY_AGENT, :account)
        }

        fn register_security_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityAgentAdded(
                SecurityAgentAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: SECURITY_AGENT, :account, :event);
        }

        fn remove_security_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityAgentRemoved(
                SecurityAgentRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: SECURITY_AGENT, :account, :event);
        }

        fn is_security_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: SECURITY_GOVERNOR, :account)
        }

        fn register_security_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityGovernorAdded(
                SecurityGovernorAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: SECURITY_GOVERNOR, :account, :event);
        }

        fn remove_security_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::SecurityGovernorRemoved(
                SecurityGovernorRemoved {
                    removed_account: account, removed_by: get_caller_address(),
                },
            );
            self._revoke_role_and_emit(role: SECURITY_GOVERNOR, :account, :event);
        }
    }

    #[embeddable_as(GovernanceRolesImpl)]
    pub impl GovernanceRoles<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        impl CommonRoles: CommonRolesComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of IGovernanceRoles<ComponentState<TContractState>> {
        fn is_governance_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: GOVERNANCE_ADMIN, :account)
        }

        fn register_governance_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::GovernanceAdminAdded(
                GovernanceAdminAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: GOVERNANCE_ADMIN, :account, :event);
        }

        fn remove_governance_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let caller_address = get_caller_address();
            assert!(account != caller_address, "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            let event = Event::GovernanceAdminRemoved(
                GovernanceAdminRemoved { removed_account: account, removed_by: caller_address },
            );
            self._revoke_role_and_emit(role: GOVERNANCE_ADMIN, :account, :event);
        }

        fn is_app_role_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: APP_ROLE_ADMIN, :account)
        }

        fn register_app_role_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::AppRoleAdminAdded(
                AppRoleAdminAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: APP_ROLE_ADMIN, :account, :event);
        }

        fn remove_app_role_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::AppRoleAdminRemoved(
                AppRoleAdminRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: APP_ROLE_ADMIN, :account, :event);
        }

        fn is_upgrade_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: UPGRADE_GOVERNOR, :account)
        }

        fn register_upgrade_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::UpgradeGovernorAdded(
                UpgradeGovernorAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: UPGRADE_GOVERNOR, :account, :event);
        }

        fn remove_upgrade_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::UpgradeGovernorRemoved(
                UpgradeGovernorRemoved {
                    removed_account: account, removed_by: get_caller_address(),
                },
            );
            self._revoke_role_and_emit(role: UPGRADE_GOVERNOR, :account, :event);
        }

        fn is_upgrade_agent(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: UPGRADE_AGENT, :account)
        }

        fn register_upgrade_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::UpgradeAgentAdded(
                UpgradeAgentAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: UPGRADE_AGENT, :account, :event);
        }

        fn remove_upgrade_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::UpgradeAgentRemoved(
                UpgradeAgentRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: UPGRADE_AGENT, :account, :event);
        }
    }

    #[embeddable_as(AppRolesImpl)]
    pub impl AppRoles<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        impl CommonRoles: CommonRolesComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of IAppRoles<ComponentState<TContractState>> {
        fn is_app_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, Access).has_role(role: APP_GOVERNOR, :account)
        }

        fn register_app_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::AppGovernorAdded(
                AppGovernorAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: APP_GOVERNOR, :account, :event);
        }

        fn remove_app_governor(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let event = Event::AppGovernorRemoved(
                AppGovernorRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: APP_GOVERNOR, :account, :event);
        }

        fn is_operator(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            get_dep_component!(self, Access).has_role(role: OPERATOR, :account)
        }

        fn register_operator(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let event = Event::OperatorAdded(
                OperatorAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: OPERATOR, :account, :event);
        }

        fn remove_operator(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let event = Event::OperatorRemoved(
                OperatorRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: OPERATOR, :account, :event);
        }

        fn is_token_admin(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            get_dep_component!(self, Access).has_role(role: TOKEN_ADMIN, :account)
        }

        fn register_token_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let event = Event::TokenAdminAdded(
                TokenAdminAdded { added_account: account, added_by: get_caller_address() },
            );
            self._grant_role_and_emit(role: TOKEN_ADMIN, :account, :event);
        }

        fn remove_token_admin(ref self: ComponentState<TContractState>, account: ContractAddress) {
            let event = Event::TokenAdminRemoved(
                TokenAdminRemoved { removed_account: account, removed_by: get_caller_address() },
            );
            self._revoke_role_and_emit(role: TOKEN_ADMIN, :account, :event);
        }
    }

    #[generate_trait]
    pub impl ClaimRoleImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of ClaimRoleInternal<TContractState> {
        // Reinstate role membership per legacy role membership:
        // 1. If the account held the legacy role, it will be granted in the current realm.
        // 2. Role membership in the current realm will not be cleared if no legacy member held.
        // 3. Legacy membership is cleared after reading, so reclaim can be done effectively only
        //    once.
        fn _reclaim_role(
            ref self: ComponentState<TContractState>, role: RoleId, account: ContractAddress,
        ) {
            if self._has_legacy_role(account, role) {
                // Clear legacy membership to prevent double claiming.
                self.role_members.write((role, account), false);
                let mut access_comp = get_dep_component_mut!(ref self, Access);
                access_comp._grant_role(:role, :account);
            }
        }

        fn _has_legacy_role(
            self: @ComponentState<TContractState>, account: ContractAddress, role: RoleId,
        ) -> bool {
            self.role_members.read((role, account))
        }

        fn _reclaim_legacy_roles_for_account(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            for (role, _) in CommonRolesComponent::ROLE_ADMIN_PAIRS.span() {
                self._reclaim_role(role: *role, :account);
            }
        }
    }

    #[generate_trait]
    pub impl RolesInternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Access: AccessControlComponent::HasComponent<TContractState>,
        impl CommonRoles: CommonRolesComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn _grant_role_and_emit(
            ref self: ComponentState<TContractState>,
            role: RoleId,
            account: ContractAddress,
            event: Event,
        ) {
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            if !access_comp.has_role(:role, :account) {
                assert!(account.is_non_zero(), "{}", AccessErrors::ZERO_ADDRESS);
                access_comp.grant_role(:role, :account);
                self.emit(event);
            }
        }

        fn _revoke_role_and_emit(
            ref self: ComponentState<TContractState>,
            role: RoleId,
            account: ContractAddress,
            event: Event,
        ) {
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            if access_comp.has_role(:role, :account) {
                access_comp.revoke_role(:role, :account);
                self.emit(event);
            }
        }

        fn assert_role_reclaim_enabled(self: @ComponentState<TContractState>) {
            assert!(
                !self.legacy_role_reclaim_disabled.read(),
                "{}",
                AccessErrors::LEGACY_ROLE_RECLAIM_DISABLED,
            );
        }

        // WARNING
        // The following internal method is unprotected and should only be used from the containing
        // contract's constructor (or, in context of tests, from the setup method).
        fn initialize(ref self: ComponentState<TContractState>, governance_admin: ContractAddress) {
            let mut common_roles = get_dep_component_mut!(ref self, CommonRoles);
            common_roles.initialize(:governance_admin);
            self.legacy_role_reclaim_disabled.write(true);
        }

        fn only_app_governor(self: @ComponentState<TContractState>) {
            get_dep_component!(self, CommonRoles).only_app_governor();
        }

        fn only_operator(self: @ComponentState<TContractState>) {
            get_dep_component!(self, CommonRoles).only_operator();
        }

        fn only_token_admin(self: @ComponentState<TContractState>) {
            get_dep_component!(self, CommonRoles).only_token_admin();
        }

        fn only_upgrade_governor(self: @ComponentState<TContractState>) {
            get_dep_component!(self, CommonRoles).only_upgrade_governor();
        }

        fn only_upgrader(self: @ComponentState<TContractState>) {
            get_dep_component!(self, CommonRoles).only_upgrader();
        }

        fn only_security_admin(self: @ComponentState<TContractState>) {
            get_dep_component!(self, CommonRoles).only_security_admin();
        }

        fn only_security_agent(self: @ComponentState<TContractState>) {
            get_dep_component!(self, CommonRoles).only_security_agent();
        }

        fn only_security_governor(self: @ComponentState<TContractState>) {
            get_dep_component!(self, CommonRoles).only_security_governor();
        }
    }
}
