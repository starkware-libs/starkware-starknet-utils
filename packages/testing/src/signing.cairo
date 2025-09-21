use snforge_std::signature::KeyPair;
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::Secp256r1Point;

pub type StarkKeyPair = KeyPair<felt252, felt252>;
pub type Secp256k1KeyPair = KeyPair<u256, Secp256k1Point>;
pub type Secp256r1KeyPair = KeyPair<u256, Secp256r1Point>;
