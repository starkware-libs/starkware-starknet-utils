#[starknet::contract]
pub(crate) mod DualCaseERC20Mock {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::IERC20Metadata;
    use openzeppelin::token::erc20::{DefaultConfig, ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starkware_utils::interfaces::mintable_token::{IMintableToken, IMintableTokenCamelOnly};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;
    impl InternalImpl = ERC20Component::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        decimals: u8,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        decimals: u8,
        initial_supply: u256,
        owner: ContractAddress,
    ) {
        self.decimals.write(decimals);
        self.erc20.initializer(name, symbol);
        self.erc20.mint(recipient: owner, amount: initial_supply);
        self.ownable.initializer(:owner);
    }

    #[abi(embed_v0)]
    impl ERC20CustomMetadataImpl of IERC20Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc20.ERC20_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc20.ERC20_symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.decimals.read()
        }
    }

    #[abi(embed_v0)]
    impl IMintableTokenImpl of IMintableToken<ContractState> {
        fn permissioned_mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            self.erc20.mint(recipient: account, :amount);
        }

        fn permissioned_burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            self.erc20.burn(:account, :amount);
        }

        fn is_permitted_minter(self: @ContractState, account: ContractAddress) -> bool {
            self.ownable.owner() == account
        }
    }

    #[abi(embed_v0)]
    impl IMintableTokenCamelOnlyImpl of IMintableTokenCamelOnly<ContractState> {
        fn permissionedMint(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.permissioned_mint(account, amount);
        }

        fn permissionedBurn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.permissioned_burn(account, amount);
        }

        fn isPermittedMinter(self: @ContractState, account: ContractAddress) -> bool {
            self.is_permitted_minter(account)
        }
    }
}

#[starknet::contract]
pub(crate) mod SnakeERC20Mock {
    use openzeppelin::token::erc20::{DefaultConfig, ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    impl InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        initial_supply: u256,
        recipient: ContractAddress,
    ) {
        self.erc20.initializer(name, symbol);
        self.erc20.mint(recipient, initial_supply);
    }
}

#[starknet::contract]
pub(crate) mod CamelERC20Mock {
    use openzeppelin::token::erc20::{DefaultConfig, ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;

    // `ERC20Impl` is not embedded because it would defeat the purpose of the
    // mock. The `ERC20Impl` case-agnostic methods are manually exposed.
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    impl InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        initial_supply: u256,
        recipient: ContractAddress,
    ) {
        self.erc20.initializer(name, symbol);
        self.erc20.mint(recipient, initial_supply);
    }

    #[abi(per_item)]
    #[generate_trait]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.erc20.allowance(owner, spender)
        }

        #[external(v0)]
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.erc20.transfer(recipient, amount)
        }

        #[external(v0)]
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(spender, amount)
        }
    }
}

/// Although these modules are designed to panic, functions
/// still need a valid return value. We chose:
///
/// 3 for felt252, u8, and u256
/// zero for ContractAddress
/// false for bool
#[starknet::contract]
pub(crate) mod SnakeERC20Panic {
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[abi(per_item)]
    #[generate_trait]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn name(self: @ContractState) -> ByteArray {
            panic!("Some error");
        }

        #[external(v0)]
        fn symbol(self: @ContractState) -> ByteArray {
            panic!("Some error");
        }

        #[external(v0)]
        fn decimals(self: @ContractState) -> u8 {
            panic!("Some error");
        }

        #[external(v0)]
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            panic!("Some error");
        }

        #[external(v0)]
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            panic!("Some error");
        }

        #[external(v0)]
        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) -> bool {
            panic!("Some error");
        }

        #[external(v0)]
        fn total_supply(self: @ContractState) -> u256 {
            panic!("Some error");
        }

        #[external(v0)]
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            panic!("Some error");
        }

        #[external(v0)]
        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) -> bool {
            panic!("Some error");
        }
    }
}

#[starknet::contract]
pub(crate) mod CamelERC20Panic {
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[abi(per_item)]
    #[generate_trait]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn totalSupply(self: @ContractState) -> u256 {
            panic!("Some error");
        }

        #[external(v0)]
        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            panic!("Some error");
        }

        #[external(v0)]
        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            panic!("Some error");
        }
    }
}
