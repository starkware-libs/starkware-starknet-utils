#[starknet::component]
pub(crate) mod CommonRolesComponent {
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::accesscontrol::AccessControlComponent::{
        AccessControlImpl, InternalTrait as AccessInternalTrait,
    };
    use openzeppelin::introspection::src5::SRC5Component;
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
    pub struct Storage {}

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
            let role_id: RoleId = role.into();
            assert!(account.is_non_zero(), "{}", AccessErrors::ZERO_ADDRESS);
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp.grant_role(role: role_id, :account);
        }

        fn revoke_role(
            ref self: ComponentState<TContractState>, role: Role, account: ContractAddress,
        ) {
            let role_id: RoleId = role.into();
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp.revoke_role(role: role_id, :account);
        }

        fn has_role(
            self: @ComponentState<TContractState>, role: Role, account: ContractAddress,
        ) -> bool {
            let role_id: RoleId = role.into();
            let access_comp = get_dep_component!(self, Access);
            access_comp.has_role(role: role_id, :account)
        }

        fn renounce(ref self: ComponentState<TContractState>, role: Role) {
            assert!(is_renounceable(role), "{}", AccessErrors::ROLE_CANNOT_BE_RENOUNCED);
            let role_id: RoleId = role.into();
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp.renounce_role(role: role_id, account: get_caller_address());
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
            let un_initialized = access_comp.get_role_admin(role: GOVERNANCE_ADMIN).is_zero();
            assert!(un_initialized, "{}", AccessErrors::ALREADY_INITIALIZED);
            access_comp.initializer();
            assert!(governance_admin.is_non_zero(), "{}", AccessErrors::ZERO_ADDRESS_GOV_ADMIN);
            access_comp._grant_role(role: GOVERNANCE_ADMIN, account: governance_admin);
            access_comp._grant_role(role: SECURITY_ADMIN, account: governance_admin);
            Self::_set_role_admins(ref access_comp);
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

        fn _grant_role(
            ref self: ComponentState<TContractState>, role: RoleId, account: ContractAddress,
        ) {
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp._grant_role(:role, :account);
        }

        fn _revoke_role(
            ref self: ComponentState<TContractState>, role: RoleId, account: ContractAddress,
        ) {
            let mut access_comp = get_dep_component_mut!(ref self, Access);
            access_comp._revoke_role(:role, :account);
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
    }
}
