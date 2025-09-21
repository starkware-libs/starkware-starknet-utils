use openzeppelin::account::utils::is_valid_stark_signature;

pub type Signature = Span<felt252>;
pub type PublicKey = felt252;
pub type HashType = felt252;

pub fn validate_stark_signature(public_key: PublicKey, msg_hash: HashType, signature: Signature) {
    assert(
        is_valid_stark_signature(:msg_hash, :public_key, :signature), 'INVALID_STARK_KEY_SIGNATURE',
    );
}
