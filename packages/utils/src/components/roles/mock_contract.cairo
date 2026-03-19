#[starknet::contract]
pub mod MockContract {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starkware_utils::components::common_roles::CommonRolesComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternalTrait;

    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: CommonRolesComponent, storage: common_roles, event: CommonRolesEvent);
    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        #[substorage(v0)]
        common_roles: CommonRolesComponent::Storage,
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RolesEvent: RolesComponent::Event,
        CommonRolesEvent: CommonRolesComponent::Event,
        AccessControlEvent: AccessControlComponent::Event,
        SRC5Event: SRC5Component::Event,
    }

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;
    #[abi(embed_v0)]
    impl CommonRolesImpl = CommonRolesComponent::CommonRolesImpl<ContractState>;

    #[constructor]
    fn constructor(ref self: ContractState, governance_admin: ContractAddress) {
        self.roles.initialize(:governance_admin);
    }
}
