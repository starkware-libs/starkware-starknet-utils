#[starknet::component]
pub(crate) mod RolesComponent {
    use RolesInterface::{
        AppGovernorAdded, AppGovernorRemoved, AppRoleAdminAdded, AppRoleAdminRemoved,
        GovernanceAdminAdded, GovernanceAdminRemoved, IAppRoles, IGovernanceRoles, IRoles,
        ISecurityRoles, OperatorAdded, OperatorRemoved, Role, SecurityAdminAdded,
        SecurityAdminRemoved, SecurityAgentAdded, SecurityAgentRemoved, SecurityGovernorAdded,
        SecurityGovernorRemoved, TokenAdminAdded, TokenAdminRemoved, UpgradeAgentAdded,
        UpgradeAgentRemoved, UpgradeGovernorAdded, UpgradeGovernorRemoved,
    };
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::accesscontrol::AccessControlComponent::AccessControlImpl;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::common_roles::CommonRolesComponent;
    use starkware_utils::components::common_roles::CommonRolesComponent::InternalTrait as CommonRolesInternalTrait;
    use starkware_utils::components::roles::errors::AccessErrors;
    use starkware_utils::components::roles::interface as RolesInterface;

    #[storage]
    pub struct Storage {}

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
            get_dep_component!(self, CommonRoles).has_role(role: Role::AppGovernor, :account)
        }

        fn is_app_role_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::AppRoleAdmin, :account)
        }

        fn is_governance_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::GovernanceAdmin, :account)
        }

        fn is_operator(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::Operator, :account)
        }

        fn is_security_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::SecurityAdmin, :account)
        }

        fn is_security_agent(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::SecurityAgent, :account)
        }

        fn is_security_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::SecurityGovernor, :account)
        }

        fn is_token_admin(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::TokenAdmin, :account)
        }

        fn is_upgrade_agent(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::UpgradeAgent, :account)
        }

        fn is_upgrade_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::UpgradeGovernor, :account)
        }

        fn register_app_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::AppGovernor,
                    account,
                    Event::AppGovernorAdded(
                        AppGovernorAdded { added_account: account, added_by: get_caller_address() },
                    ),
                );
        }

        fn remove_app_governor(ref self: ComponentState<TContractState>, account: ContractAddress) {
            self
                ._remove_role(
                    Role::AppGovernor,
                    account,
                    Event::AppGovernorRemoved(
                        AppGovernorRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn register_app_role_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::AppRoleAdmin,
                    account,
                    Event::AppRoleAdminAdded(
                        AppRoleAdminAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_app_role_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::AppRoleAdmin,
                    account,
                    Event::AppRoleAdminRemoved(
                        AppRoleAdminRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn register_security_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::SecurityAdmin,
                    account,
                    Event::SecurityAdminAdded(
                        SecurityAdminAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_security_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let caller_address = get_caller_address();
            assert!(account != caller_address, "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            self
                ._remove_role(
                    Role::SecurityAdmin,
                    account,
                    Event::SecurityAdminRemoved(
                        SecurityAdminRemoved {
                            removed_account: account, removed_by: caller_address,
                        },
                    ),
                );
        }

        fn register_security_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::SecurityAgent,
                    account,
                    Event::SecurityAgentAdded(
                        SecurityAgentAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_security_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::SecurityAgent,
                    account,
                    Event::SecurityAgentRemoved(
                        SecurityAgentRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn register_security_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::SecurityGovernor,
                    account,
                    Event::SecurityGovernorAdded(
                        SecurityGovernorAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_security_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::SecurityGovernor,
                    account,
                    Event::SecurityGovernorRemoved(
                        SecurityGovernorRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn register_governance_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::GovernanceAdmin,
                    account,
                    Event::GovernanceAdminAdded(
                        GovernanceAdminAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_governance_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let caller_address = get_caller_address();
            assert!(account != caller_address, "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            self
                ._remove_role(
                    Role::GovernanceAdmin,
                    account,
                    Event::GovernanceAdminRemoved(
                        GovernanceAdminRemoved {
                            removed_account: account, removed_by: caller_address,
                        },
                    ),
                );
        }

        fn register_operator(ref self: ComponentState<TContractState>, account: ContractAddress) {
            self
                ._register_role(
                    Role::Operator,
                    account,
                    Event::OperatorAdded(
                        OperatorAdded { added_account: account, added_by: get_caller_address() },
                    ),
                );
        }

        fn remove_operator(ref self: ComponentState<TContractState>, account: ContractAddress) {
            self
                ._remove_role(
                    Role::Operator,
                    account,
                    Event::OperatorRemoved(
                        OperatorRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn register_token_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::TokenAdmin,
                    account,
                    Event::TokenAdminAdded(
                        TokenAdminAdded { added_account: account, added_by: get_caller_address() },
                    ),
                );
        }

        fn remove_token_admin(ref self: ComponentState<TContractState>, account: ContractAddress) {
            self
                ._remove_role(
                    Role::TokenAdmin,
                    account,
                    Event::TokenAdminRemoved(
                        TokenAdminRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn register_upgrade_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::UpgradeAgent,
                    account,
                    Event::UpgradeAgentAdded(
                        UpgradeAgentAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_upgrade_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::UpgradeAgent,
                    account,
                    Event::UpgradeAgentRemoved(
                        UpgradeAgentRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn register_upgrade_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::UpgradeGovernor,
                    account,
                    Event::UpgradeGovernorAdded(
                        UpgradeGovernorAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_upgrade_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::UpgradeGovernor,
                    account,
                    Event::UpgradeGovernorRemoved(
                        UpgradeGovernorRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }
    }

    // ─── Category-scoped role impls ────────────

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
            get_dep_component!(self, CommonRoles).has_role(role: Role::SecurityAdmin, :account)
        }

        fn register_security_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::SecurityAdmin,
                    account,
                    Event::SecurityAdminAdded(
                        SecurityAdminAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_security_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let caller_address = get_caller_address();
            assert!(account != caller_address, "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            self
                ._remove_role(
                    Role::SecurityAdmin,
                    account,
                    Event::SecurityAdminRemoved(
                        SecurityAdminRemoved {
                            removed_account: account, removed_by: caller_address,
                        },
                    ),
                );
        }

        fn is_security_agent(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::SecurityAgent, :account)
        }

        fn register_security_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::SecurityAgent,
                    account,
                    Event::SecurityAgentAdded(
                        SecurityAgentAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_security_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::SecurityAgent,
                    account,
                    Event::SecurityAgentRemoved(
                        SecurityAgentRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn is_security_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::SecurityGovernor, :account)
        }

        fn register_security_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::SecurityGovernor,
                    account,
                    Event::SecurityGovernorAdded(
                        SecurityGovernorAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_security_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::SecurityGovernor,
                    account,
                    Event::SecurityGovernorRemoved(
                        SecurityGovernorRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
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
            get_dep_component!(self, CommonRoles).has_role(role: Role::GovernanceAdmin, :account)
        }

        fn register_governance_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::GovernanceAdmin,
                    account,
                    Event::GovernanceAdminAdded(
                        GovernanceAdminAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_governance_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            let caller_address = get_caller_address();
            assert!(account != caller_address, "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            self
                ._remove_role(
                    Role::GovernanceAdmin,
                    account,
                    Event::GovernanceAdminRemoved(
                        GovernanceAdminRemoved {
                            removed_account: account, removed_by: caller_address,
                        },
                    ),
                );
        }

        fn is_app_role_admin(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::AppRoleAdmin, :account)
        }

        fn register_app_role_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::AppRoleAdmin,
                    account,
                    Event::AppRoleAdminAdded(
                        AppRoleAdminAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_app_role_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::AppRoleAdmin,
                    account,
                    Event::AppRoleAdminRemoved(
                        AppRoleAdminRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn is_upgrade_governor(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::UpgradeGovernor, :account)
        }

        fn register_upgrade_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::UpgradeGovernor,
                    account,
                    Event::UpgradeGovernorAdded(
                        UpgradeGovernorAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_upgrade_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::UpgradeGovernor,
                    account,
                    Event::UpgradeGovernorRemoved(
                        UpgradeGovernorRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn is_upgrade_agent(
            self: @ComponentState<TContractState>, account: ContractAddress,
        ) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::UpgradeAgent, :account)
        }

        fn register_upgrade_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::UpgradeAgent,
                    account,
                    Event::UpgradeAgentAdded(
                        UpgradeAgentAdded {
                            added_account: account, added_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn remove_upgrade_agent(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._remove_role(
                    Role::UpgradeAgent,
                    account,
                    Event::UpgradeAgentRemoved(
                        UpgradeAgentRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
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
            get_dep_component!(self, CommonRoles).has_role(role: Role::AppGovernor, :account)
        }

        fn register_app_governor(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::AppGovernor,
                    account,
                    Event::AppGovernorAdded(
                        AppGovernorAdded { added_account: account, added_by: get_caller_address() },
                    ),
                );
        }

        fn remove_app_governor(ref self: ComponentState<TContractState>, account: ContractAddress) {
            self
                ._remove_role(
                    Role::AppGovernor,
                    account,
                    Event::AppGovernorRemoved(
                        AppGovernorRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn is_operator(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::Operator, :account)
        }

        fn register_operator(ref self: ComponentState<TContractState>, account: ContractAddress) {
            self
                ._register_role(
                    Role::Operator,
                    account,
                    Event::OperatorAdded(
                        OperatorAdded { added_account: account, added_by: get_caller_address() },
                    ),
                );
        }

        fn remove_operator(ref self: ComponentState<TContractState>, account: ContractAddress) {
            self
                ._remove_role(
                    Role::Operator,
                    account,
                    Event::OperatorRemoved(
                        OperatorRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
        }

        fn is_token_admin(self: @ComponentState<TContractState>, account: ContractAddress) -> bool {
            get_dep_component!(self, CommonRoles).has_role(role: Role::TokenAdmin, :account)
        }

        fn register_token_admin(
            ref self: ComponentState<TContractState>, account: ContractAddress,
        ) {
            self
                ._register_role(
                    Role::TokenAdmin,
                    account,
                    Event::TokenAdminAdded(
                        TokenAdminAdded { added_account: account, added_by: get_caller_address() },
                    ),
                );
        }

        fn remove_token_admin(ref self: ComponentState<TContractState>, account: ContractAddress) {
            self
                ._remove_role(
                    Role::TokenAdmin,
                    account,
                    Event::TokenAdminRemoved(
                        TokenAdminRemoved {
                            removed_account: account, removed_by: get_caller_address(),
                        },
                    ),
                );
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
        fn _register_role(
            ref self: ComponentState<TContractState>,
            role: Role,
            account: ContractAddress,
            event: Event,
        ) {
            let mut common_roles = get_dep_component_mut!(ref self, CommonRoles);
            if common_roles.has_role(:role, :account) {
                return;
            }
            common_roles.grant_role(:role, :account);
            self.emit(event);
        }

        fn _remove_role(
            ref self: ComponentState<TContractState>,
            role: Role,
            account: ContractAddress,
            event: Event,
        ) {
            let mut common_roles = get_dep_component_mut!(ref self, CommonRoles);
            if !common_roles.has_role(:role, :account) {
                return;
            }
            common_roles.revoke_role(:role, :account);
            self.emit(event);
        }

        // WARNING
        // The following internal method is unprotected and should only be used from the containing
        // contract's constructor (or, in context of tests, from the setup method).
        fn initialize(ref self: ComponentState<TContractState>, governance_admin: ContractAddress) {
            let mut common_roles = get_dep_component_mut!(ref self, CommonRoles);
            common_roles.initialize(:governance_admin);
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
