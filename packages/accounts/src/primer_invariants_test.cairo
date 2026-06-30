use snforge_std::{ContractClassTrait, DeclareResultTrait};
use starknet::{ContractAddress, SyscallResultTrait};
use starkware_accounts::utils::{PRIMER_CLASS_HASH, compute_contract_address};

/// Guard: the factory's `#[cfg(target: "test")]` PRIMER_CLASS_HASH must equal the class hash of the
/// 2.15.1 `PrimerTestMock` the tests actually deploy. If a toolchain/source change shifts the
/// mock's hash, this fails loudly (instead of the deploy_account tests failing cryptically with an
/// address mismatch). Update the cfg(test) constant in utils.cairo to the value reported here.
#[test]
fn test_primer_test_mock_hash_matches_cfg_constant() {
    let mock_hash = *snforge_std::declare("PrimerTestMock")
        .unwrap_syscall()
        .contract_class()
        .class_hash;
    assert!(
        mock_hash == PRIMER_CLASS_HASH,
        "PrimerTestMock class hash {:?} != cfg(target: \"test\") PRIMER_CLASS_HASH {:?}",
        mock_hash,
        PRIMER_CLASS_HASH,
    );
}

/// Golden vector (Sepolia, verified on-chain): the factory at 0x0317…2dad returns account
/// 0x00ad…459d for eth address 0xa3dc…0271 using the PRODUCTION Primer class hash 0x00123e6b…
/// This validates the real deterministic-address derivation independently of the test mock hash.
#[test]
fn test_production_address_golden_vector() {
    let expected: ContractAddress =
        0x00ad94c5b4e5eb87976d885977dcf484c63e9e0028764f0f0dfe486bc643459d
        .try_into()
        .unwrap();
    let got = compute_contract_address(
        salt: 0xa3dc89cdedc8ffb9b52799fedf402dd2175e0271,
        class_hash: 0x00123e6bc1c14ae9934e933d3f64916a6116dd6b036a922b2b1f0815e0d1d300,
        constructor_calldata: array![].span(),
        deployer_address: 0x0317263e89ac4a44b44c232424c2c5069e13876703b32ebc1efb5d3237a32dad,
    );
    assert!(got == expected, "golden vector mismatch: got {:?}", got);
}
