#[starknet::contract]
pub mod blocklist_mock_contract {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::ERC20Component;
    use starknet::ContractAddress;
    use starkware_utils::components::blocklist::blocklist::blocklist as BlocklistComponent;
    use starkware_utils::components::blocklist::blocklist::blocklist::InternalTrait as BlocklistInternalTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternalTrait;
    use starkware_utils::interfaces::mintable_token::IMintableToken;


    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: BlocklistComponent, storage: blocklist, event: BlocklistEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // --- Components ---
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        blocklist: BlocklistComponent::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        BlocklistEvent: BlocklistComponent::Event,
        RolesEvent: RolesComponent::Event,
        AccessControlEvent: AccessControlComponent::Event,
        SRC5Event: SRC5Component::Event,
    }

    impl HooksImpl<> of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            self.get_contract().blocklist.assert_not_blocked(from);
            self.get_contract().blocklist.assert_not_blocked(recipient);
        }

        fn after_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {}
    }

    #[abi(embed_v0)]
    impl BlocklistImpl = BlocklistComponent::BlocklistImpl<ContractState>;
    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[constructor]
    fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
    ) {
        self.roles.initialize(:governance_admin);
        self.erc20.initializer(:name, :symbol);
    }

    #[abi(embed_v0)]
    pub impl MintableTokenImpl of IMintableToken<ContractState> {
        fn permissioned_mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.blocklist.assert_not_blocked(account);
            self.roles.only_token_admin();
            self.erc20.mint(account, amount);
        }

        fn permissioned_burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.blocklist.assert_not_blocked(account);
            self.roles.only_token_admin();
            self.erc20.burn(account, amount);
        }

        fn is_permitted_minter(self: @ContractState, account: ContractAddress) -> bool {
            self.roles.is_token_admin(account)
        }
    }
}
