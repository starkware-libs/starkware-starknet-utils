use starknet::account::Call;
use starknet::secp256_trait::Signature;
use starknet::{ClassHash, EthAddress};

/// SRC5 interface id for `ICustomSignatureValidation::is_custom_signature_valid`.
/// selector!("is_custom_signature_valid") =
/// 0x002eb9faa4ce06e09879e93803798b87d22877b73964334356bf9e0d8cc22ded
pub const ICUSTOM_SIGNATURE_VALIDATION_ID: felt252 = selector!("is_custom_signature_valid");

/// Checks for account's confirmation that its owner authorized a given set of `calls`,
/// WITHOUT executing them.
/// Validation is over the EIP-712 `CallSet { calls }` message,
/// independent of any specific transaction context (`tx_info`, version, resource bounds, nonce)
/// so a browser EVM wallet can produce the signature.
///
/// Returns `VALIDATED` for a valid 6-felt signature and `0` for an invalid one
/// Reverts on a malformed signature.
/// signature (wrong length or out-of-range components) reverts.
/// Unlike `__validate__`, a valid-shape but wrong signature
/// does not revert — the caller decides how to treat the result.
///
/// This is a stateless predicate: it provides no replay protection. A caller that authorizes
/// actions off this result is responsible for binding/replay protection of its own.
#[starknet::interface]
pub trait ICustomSignatureValidation<TContractState> {
    fn is_custom_signature_valid(
        self: @TContractState, calls: Span<Call>, signature: Span<felt252>,
    ) -> felt252;
}

#[starknet::interface]
pub trait IAccount712Admin<TContractState> {
    fn initialize(ref self: TContractState, eth_address: EthAddress, signature: Signature);
    fn upgrade(
        ref self: TContractState,
        new_class_hash: ClassHash,
        eic_data: Option<(ClassHash, Span<felt252>)>,
    );
}

#[starknet::interface]
pub trait IEIC<TContractState> {
    fn eic_initialize(ref self: TContractState, data: Span<felt252>);
}

/// Emitted when the contract is upgraded.
#[derive(Drop, Debug, PartialEq, starknet::Event)]
pub struct Upgraded {
    pub class_hash: ClassHash,
}
