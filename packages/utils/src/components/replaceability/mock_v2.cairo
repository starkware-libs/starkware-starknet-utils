// Functionally identical to `ReplaceabilityMock` but compiles to a different class hash
// (via the unused `_v2_marker` field). Used as a valid upgrade target in tests where the
// target must include the replaceability component yet differ from the deployed contract.
//
// IMPORTANT: keep this in lockstep with `mock.cairo`. The validation tests assume the two
// classes share the same upgrade machinery; any change to the components, storage layout, or
// constructor of `ReplaceabilityMock` must be mirrored here.
#[starknet::contract]
pub(crate) mod ReplaceabilityMockV2 {
    use CommonRolesComponent::InternalTrait as CommonRolesInternalTrait;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starkware_utils::components::common_roles::CommonRolesComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;

    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: CommonRolesComponent, storage: common_roles, event: CommonRolesEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        common_roles: CommonRolesComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // Extra field to produce a different class hash from ReplaceabilityMock.
        _v2_marker: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub(crate) enum Event {
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        CommonRolesEvent: CommonRolesComponent::Event,
        AccessControlEvent: AccessControlComponent::Event,
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, upgrade_delay: u64, governance_admin: ContractAddress) {
        self.common_roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
    }

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl CommonRolesImpl = CommonRolesComponent::CommonRolesImpl<ContractState>;
}
