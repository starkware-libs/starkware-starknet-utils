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

/// External Initializer Contract: `eic_initialize` is called (using library_call) during an upgrade
/// to perform custom intialization.
#[starknet::interface]
pub trait IEIC<TContractState> {
    fn eic_initialize(ref self: TContractState, data: Span<felt252>);
}
