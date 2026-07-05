use starknet::ClassHash;

/// Standard external entrypoint for `EICUpgradableComponent`. Should be implemented by the
/// contract.
#[starknet::interface]
pub trait IEICUpgradable<TContractState> {
    fn upgrade(
        ref self: TContractState,
        new_class_hash: ClassHash,
        eic_data: Option<(ClassHash, Span<felt252>)>,
    );
}

/// External Initializer Contract: its `eic_initialize` is `library_call`ed during an upgrade (in
/// the upgrading contract's storage context) to migrate storage before the class is replaced.
#[starknet::interface]
pub trait IEIC<TContractState> {
    fn eic_initialize(ref self: TContractState, data: Span<felt252>);
}
