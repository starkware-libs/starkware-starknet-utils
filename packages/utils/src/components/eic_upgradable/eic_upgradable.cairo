/// # EIC Upgradable Component
///
/// `replace_class` based upgradability with optional EIC (External Initializer Contract) migration.
/// It exposes only internal logic and no access control.
/// It's the developer's responsibilty to restrict calls appropriately.
#[starknet::component]
pub mod EICUpgradableComponent {
    use core::num::traits::Zero;
    use starknet::syscalls::replace_class_syscall;
    use starknet::{ClassHash, SyscallResultTrait};
    use starkware_utils::components::eic_upgradable::interface::{
        IEICDispatcherTrait, IEICLibraryDispatcher,
    };

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        Upgraded: Upgraded,
    }

    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub struct Upgraded {
        pub class_hash: ClassHash,
    }

    pub mod Errors {
        pub const INVALID_CLASS: felt252 = 'INVALID_CLASS_HASH';
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn upgrade(
            ref self: ComponentState<TContractState>,
            new_class_hash: ClassHash,
            eic_data: Option<(ClassHash, Span<felt252>)>,
        ) {
            assert(new_class_hash.is_non_zero(), Errors::INVALID_CLASS);
            if let Some((class_hash, eic_init_data)) = eic_data {
                IEICLibraryDispatcher { class_hash }.eic_initialize(eic_init_data);
            }
            replace_class_syscall(new_class_hash).unwrap_syscall();
            self.emit(Upgraded { class_hash: new_class_hash });
        }
    }
}
