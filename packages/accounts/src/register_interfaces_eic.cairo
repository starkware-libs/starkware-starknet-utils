// SPDX-License-Identifier: Apache-2.0
/// EIC (External Initializer Contract) for registering SRC5 interfaces.
/// This contract is called via library_call during upgrade to register
/// interface IDs that were not registered in older account implementations.

#[starknet::contract]
pub mod RegisterInterfacesEIC {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use starkware_accounts::interface::IEIC;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[abi(embed_v0)]
    impl EICImpl of IEIC<ContractState> {
        fn eic_initialize(ref self: ContractState, data: Span<felt252>) {
            for interface_id in data {
                self.src5.register_interface(*interface_id);
            }
        }
    }
}
