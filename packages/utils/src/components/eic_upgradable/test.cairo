// SPDX-License-Identifier: Apache-2.0

mod EICUpgradableTests {
    use snforge_std::{
        ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, load, spy_events,
    };
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
    use starkware_utils::components::eic_upgradable::eic_upgradable::EICUpgradableComponent;
    use starkware_utils::components::eic_upgradable::interface::{
        IEICUpgradableDispatcher, IEICUpgradableDispatcherTrait,
    };
    use starkware_utils::components::eic_upgradable::mock::{
        EICUpgradableMock, IMockVersionDispatcher, IMockVersionDispatcherTrait,
    };

    const EIC_MARKER_VALUE: felt252 = 42;

    fn deploy_mock() -> (IEICUpgradableDispatcher, ContractAddress) {
        let contract = declare("EICUpgradableMock").unwrap_syscall().contract_class();
        let (address, _) = contract.deploy(@array![]).unwrap_syscall();
        (IEICUpgradableDispatcher { contract_address: address }, address)
    }

    fn v2_class_hash() -> ClassHash {
        *declare("EICUpgradableMockV2").unwrap_syscall().contract_class().class_hash
    }

    fn eic_class_hash() -> ClassHash {
        *declare("EICMock").unwrap_syscall().contract_class().class_hash
    }

    fn version_of(address: ContractAddress) -> felt252 {
        IMockVersionDispatcher { contract_address: address }.version()
    }

    #[test]
    fn test_upgrade_replaces_class_and_emits() {
        let (dispatcher, address) = deploy_mock();
        assert!(version_of(address) == 1, "mock should start at version 1");
        let new_class_hash = v2_class_hash();

        let mut spy = spy_events();
        dispatcher.upgrade(new_class_hash, Option::None);

        assert!(version_of(address) == 2, "class should have been replaced with v2");
        spy
            .assert_emitted(
                @array![
                    (
                        address,
                        EICUpgradableMock::Event::UpgradableEvent(
                            EICUpgradableComponent::Event::Upgraded(
                                EICUpgradableComponent::Upgraded { class_hash: new_class_hash },
                            ),
                        ),
                    ),
                ],
            );
    }

    #[test]
    fn test_upgrade_runs_eic() {
        let (dispatcher, address) = deploy_mock();
        let new_class_hash = v2_class_hash();
        let eic_class_hash = eic_class_hash();

        dispatcher
            .upgrade(
                new_class_hash, Option::Some((eic_class_hash, array![EIC_MARKER_VALUE].span())),
            );

        // The EIC ran in the mock's storage context, writing the marker slot ...
        let marker = *load(target: address, storage_address: selector!("eic_marker"), size: 1)
            .at(0);
        assert!(marker == EIC_MARKER_VALUE, "EIC should have written the marker slot");
        // ... and the class was still replaced afterwards.
        assert!(version_of(address) == 2, "class should have been replaced with v2");
    }

    #[test]
    #[should_panic(expected: 'INVALID_CLASS_HASH')]
    fn test_upgrade_zero_class_hash_reverts() {
        let (dispatcher, _) = deploy_mock();
        dispatcher.upgrade(0.try_into().unwrap(), Option::None);
    }

    #[test]
    #[should_panic(expected: 'EIC_INIT_DATA_LEN_MISMATCH')]
    fn test_upgrade_eic_revert_propagates() {
        let (dispatcher, _) = deploy_mock();
        let new_class_hash = v2_class_hash();
        let eic_class_hash = eic_class_hash();
        // Empty init data trips the EIC's length assert; the whole upgrade must revert.
        dispatcher.upgrade(new_class_hash, Option::Some((eic_class_hash, array![].span())));
    }
}
