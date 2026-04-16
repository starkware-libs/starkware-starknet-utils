mod ReplaceabilityTests {
    use core::num::traits::zero::Zero;
    use replaceability::ReplaceabilityComponent;
    use replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use replaceability::interface::{
        IReplaceable, IReplaceableDispatcherTrait, IReplaceableSafeDispatcher,
        IReplaceableSafeDispatcherTrait, ImplementationAdded, ImplementationFinalized,
        ImplementationRemoved, ImplementationReplaced,
    };
    use replaceability::mock::ReplaceabilityMock;
    use replaceability::test_utils::Constants::{
        DEFAULT_UPGRADE_DELAY, DUMMY_FINAL_IMPLEMENTATION_DATA, DUMMY_NONFINAL_IMPLEMENTATION_DATA,
        EIC_UPGRADE_DELAY_ADDITION, GOVERNANCE_ADMIN, NOT_UPGRADE_GOVERNOR_ACCOUNT,
    };
    use replaceability::test_utils::{
        assert_finalized_status, assert_implementation_finalized_event_emitted,
        assert_implementation_replaced_event_emitted, deploy_dummy_contract,
        deploy_replaceability_mock, dummy_final_implementation_data_with_class_hash,
        dummy_nonfinal_eic_implementation_data_with_class_hash,
        dummy_nonfinal_implementation_data_with_class_hash, get_replaceability_mock_v2_class_hash,
        get_upgrade_governor_account,
    };
    use snforge_std::{
        CheatSpan, EventSpyAssertionsTrait, EventSpyTrait, EventsFilterTrait, cheat_block_timestamp,
        cheat_caller_address, get_class_hash, spy_events,
    };
    use starkware_utils::components::replaceability;
    use starkware_utils::components::roles::interface::{
        ICommonRolesDispatcher, ICommonRolesDispatcherTrait, Role,
    };
    use starkware_utils_testing::test_utils::cheat_caller_address_once;

    #[test]
    fn test_get_upgrade_delay() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        assert!(replaceable_dispatcher.get_upgrade_delay() == DEFAULT_UPGRADE_DELAY);
    }

    #[test]
    fn test_initialize() {
        let mut state: ReplaceabilityComponent::ComponentState<ReplaceabilityMock::ContractState> =
            ReplaceabilityComponent::component_state_for_testing();
        assert!(state.get_upgrade_delay() == Zero::zero(), "Upgrade delay should be zero");
        state.initialize(upgrade_delay: DEFAULT_UPGRADE_DELAY);
        assert!(
            state.get_upgrade_delay() == DEFAULT_UPGRADE_DELAY,
            "Upgrade delay should be {DEFAULT_UPGRADE_DELAY}",
        );
    }

    #[test]
    #[should_panic(expected: "ALREADY_INITIALIZED")]
    fn test_initialize_already_initialized() {
        let mut state: ReplaceabilityComponent::ComponentState<ReplaceabilityMock::ContractState> =
            ReplaceabilityComponent::component_state_for_testing();
        assert!(state.get_upgrade_delay() == Zero::zero(), "Upgrade delay should be zero");
        state.initialize(upgrade_delay: DEFAULT_UPGRADE_DELAY);
        assert!(
            state.get_upgrade_delay() == DEFAULT_UPGRADE_DELAY,
            "Upgrade delay should be {DEFAULT_UPGRADE_DELAY}",
        );
        state.initialize(upgrade_delay: DEFAULT_UPGRADE_DELAY);
    }

    #[test]
    fn test_add_new_implementation() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        // Use a real upgradeable class hash so validation at add time can dispatch into it.
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: get_replaceability_mock_v2_class_hash(),
        );

        // Check implementation time pre addition.
        assert!(replaceable_dispatcher.get_impl_activation_time(:implementation_data).is_zero());

        cheat_caller_address_once(
            :contract_address, caller_address: get_upgrade_governor_account(:contract_address),
        );
        let mut spy = spy_events();
        replaceable_dispatcher.add_new_implementation(:implementation_data);
        // Test setup pins block_timestamp to 1, so activation_time = 1 + DEFAULT_UPGRADE_DELAY.
        assert!(
            replaceable_dispatcher
                .get_impl_activation_time(:implementation_data) == DEFAULT_UPGRADE_DELAY
                + 1,
        );

        // Validate event emission.
        spy
            .assert_emitted(
                @array![
                    (
                        contract_address,
                        ReplaceabilityMock::Event::ReplaceabilityEvent(
                            ReplaceabilityComponent::Event::ImplementationAdded(
                                ImplementationAdded { implementation_data: implementation_data },
                            ),
                        ),
                    ),
                ],
            );
    }

    #[test]
    #[should_panic(expected: "ONLY_UPGRADE_GOVERNOR")]
    fn test_add_new_implementation_not_upgrade_governor() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        // class_hash = 0 is intentional: the auth check fires before validation, so the
        // placeholder class is never dispatched into. If the order ever flips, this would
        // surface as "class not declared" instead of ONLY_UPGRADE_GOVERNOR.
        let implementation_data = DUMMY_NONFINAL_IMPLEMENTATION_DATA();

        // Invoke not as an Upgrade Governor.
        cheat_caller_address_once(:contract_address, caller_address: NOT_UPGRADE_GOVERNOR_ACCOUNT);
        replaceable_dispatcher.add_new_implementation(:implementation_data);
    }

    #[test]
    fn test_remove_implementation() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        // Use a real upgradeable class hash so validation at add time can dispatch into it.
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: get_replaceability_mock_v2_class_hash(),
        );

        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(4),
        );
        let mut spy = spy_events();

        // Remove implementation that was not previously added.
        replaceable_dispatcher.remove_implementation(:implementation_data);
        assert!(replaceable_dispatcher.get_impl_activation_time(:implementation_data).is_zero());
        let emitted_events = spy.get_events().emitted_by(:contract_address);
        // The following should NOT emit an event.
        assert!(emitted_events.events.len().is_zero());

        replaceable_dispatcher.add_new_implementation(:implementation_data);
        replaceable_dispatcher.remove_implementation(:implementation_data);
        assert!(replaceable_dispatcher.get_impl_activation_time(:implementation_data).is_zero());

        // Validate event emission.
        spy
            .assert_emitted(
                @array![
                    (
                        contract_address,
                        ReplaceabilityMock::Event::ReplaceabilityEvent(
                            ReplaceabilityComponent::Event::ImplementationRemoved(
                                ImplementationRemoved { implementation_data: implementation_data },
                            ),
                        ),
                    ),
                ],
            );
    }

    #[test]
    #[should_panic(expected: "ONLY_UPGRADE_GOVERNOR")]
    fn test_remove_implementation_not_upgrade_governor() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        let implementation_data = DUMMY_NONFINAL_IMPLEMENTATION_DATA();

        // Invoke not as an Upgrade Governor.
        cheat_caller_address_once(:contract_address, caller_address: NOT_UPGRADE_GOVERNOR_ACCOUNT);
        replaceable_dispatcher.remove_implementation(:implementation_data);
    }

    #[test]
    #[should_panic(expected: "IMPLEMENTATION_EXPIRED")]
    fn test_replace_to_expire_impl() {
        // Tests that impl class-hash cannot be replaced to after expiration.
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;

        // Prepare implementation data with the same class hash (repalce to self).
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: get_class_hash(contract_address),
        );

        // Invoke as an Upgrade Governor.
        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(6),
        );

        // Add implementation.
        replaceable_dispatcher.add_new_implementation(:implementation_data);
        assert!(
            replaceable_dispatcher.get_impl_activation_time(:implementation_data).is_non_zero(),
        );

        // Advance time to enable implementation.
        cheat_block_timestamp(contract_address, DEFAULT_UPGRADE_DELAY + 1, CheatSpan::Indefinite);
        replaceable_dispatcher.replace_to(:implementation_data);

        // Check enabled timestamp zeroed for replaced to impl, and non-zero for other.
        assert!(replaceable_dispatcher.get_impl_activation_time(:implementation_data).is_zero());

        // Add implementation for 2nd time.
        replaceable_dispatcher.add_new_implementation(:implementation_data);

        cheat_block_timestamp(
            contract_address,
            DEFAULT_UPGRADE_DELAY + 1 + DEFAULT_UPGRADE_DELAY + 14 * 3600 * 24 + 2,
            CheatSpan::Indefinite,
        );

        // Should revert on expired_impl.
        replaceable_dispatcher.replace_to(:implementation_data);
    }

    #[test]
    fn test_replace_to_nonfinal_impl() {
        // Tests replacing an implementation to a non-final implementation, as follows:
        // 1. deploys a replaceable contract and another contract with different class hash
        // 2. generates a non-final dummy implementation replacement
        // 3. adds it to the replaceable contract
        // 4. advances time until the new implementation is ready
        // 5. replaces to the new implemenation
        // 6. checks the implemenation is not final
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;

        // Deploy a V2 mock to get a different class hash that still includes replaceability.
        let new_class_hash = get_replaceability_mock_v2_class_hash();
        assert_ne!(get_class_hash(:contract_address), new_class_hash);

        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: new_class_hash,
        );

        // Invoke as an Upgrade Governor.
        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(2),
        );
        let mut spy = spy_events();

        // Add implementation and advance time to enable it.
        replaceable_dispatcher.add_new_implementation(:implementation_data);
        cheat_block_timestamp(
            :contract_address,
            block_timestamp: DEFAULT_UPGRADE_DELAY + 1,
            span: CheatSpan::Indefinite,
        );

        replaceable_dispatcher.replace_to(:implementation_data);

        // Validate new class hash.
        assert_eq!(get_class_hash(:contract_address), new_class_hash);

        // Validate that the new implementation is not final.
        assert_finalized_status(expected: false, :contract_address);

        // Validate `ImplementationReplaced` event emission.
        spy
            .assert_emitted(
                @array![
                    (
                        contract_address,
                        ReplaceabilityMock::Event::ReplaceabilityEvent(
                            ReplaceabilityComponent::Event::ImplementationReplaced(
                                ImplementationReplaced { implementation_data: implementation_data },
                            ),
                        ),
                    ),
                ],
            );

        // Validate `ImplementationFinalized` event is NOT emitted.
        spy
            .assert_not_emitted(
                @array![
                    (
                        contract_address,
                        ReplaceabilityMock::Event::ReplaceabilityEvent(
                            ReplaceabilityComponent::Event::ImplementationFinalized(
                                ImplementationFinalized {
                                    impl_hash: get_class_hash(:contract_address),
                                },
                            ),
                        ),
                    ),
                ],
            );
    }

    #[test]
    fn test_replace_to_with_eic() {
        // Tests replacing an implementation to a non-final implementation using EIC, as follows:
        // 1. deploys a replaceable contract
        // 2. generates a dummy implementation replacement with eic
        // 3. adds it to the replaceable contract
        // 4. advances time until the new implementation is ready
        // 5. replaces to the new implemenation
        // 6. checks the eic effect
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        let implementation_data = dummy_nonfinal_eic_implementation_data_with_class_hash(
            get_class_hash(contract_address),
        );

        // Invoke as an Upgrade Governor.
        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(2),
        );

        // Add implementation and advance time to enable it.
        replaceable_dispatcher.add_new_implementation(:implementation_data);
        cheat_block_timestamp(contract_address, DEFAULT_UPGRADE_DELAY + 1, CheatSpan::Indefinite);

        replaceable_dispatcher.replace_to(:implementation_data);
        assert!(
            replaceable_dispatcher.get_upgrade_delay() == DEFAULT_UPGRADE_DELAY
                + EIC_UPGRADE_DELAY_ADDITION,
        );
    }

    #[test]
    #[should_panic(expected: "ONLY_UPGRADER")]
    fn test_replace_to_not_upgrade_governor() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        // Use a real declared class hash so the validation library_call can resolve it.
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: get_replaceability_mock_v2_class_hash(),
        );

        // Invoke not as an Upgrade Governor.
        cheat_caller_address_once(:contract_address, caller_address: NOT_UPGRADE_GOVERNOR_ACCOUNT);
        replaceable_dispatcher.replace_to(:implementation_data);
    }

    #[test]
    #[should_panic(expected: "UNKNOWN_IMPLEMENTATION")]
    fn test_replace_to_unknown_implementation() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;

        // Invoke as an Upgrade Governor.
        cheat_caller_address_once(
            :contract_address, caller_address: get_upgrade_governor_account(:contract_address),
        );
        // Use a real declared class hash so the validation library_call can resolve it.
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: get_replaceability_mock_v2_class_hash(),
        );

        // Calling replace_to without previously adding the implementation.
        replaceable_dispatcher.replace_to(:implementation_data);
    }

    #[test]
    #[should_panic(expected: "UNKNOWN_IMPLEMENTATION")]
    fn test_replace_to_remove_impl_on_replace() {
        // Tests that when replacing class-hash, the impl time is reset to zero.
        // 1. deploys a replaceable contract
        // 2. generates implementation replacement to the same classhash.
        // 3. adds it to the replaceable contract
        // 4. advances time until the new implementation is ready
        // 5. replaces to the new implemenation
        // 6. checks the impl time is now zero.
        // 7. Fails to replace to this impl.
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;

        // Prepare implementation data with the same class hash (repalce to self).
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: get_class_hash(contract_address),
        );
        let other_implementation_data = DUMMY_FINAL_IMPLEMENTATION_DATA();

        // Invoke as an Upgrade Governor.
        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(8),
        );

        // Add implementations.
        replaceable_dispatcher.add_new_implementation(:implementation_data);
        replaceable_dispatcher
            .add_new_implementation(implementation_data: other_implementation_data);
        assert!(
            replaceable_dispatcher.get_impl_activation_time(:implementation_data).is_non_zero(),
        );
        assert!(
            replaceable_dispatcher
                .get_impl_activation_time(implementation_data: other_implementation_data)
                .is_non_zero(),
        );

        // Advance time to enable implementation.
        cheat_block_timestamp(contract_address, DEFAULT_UPGRADE_DELAY + 1, CheatSpan::Indefinite);

        replaceable_dispatcher.replace_to(:implementation_data);

        // Check enabled timestamp zeroed for replaced to impl, and non-zero for other.
        assert!(replaceable_dispatcher.get_impl_activation_time(:implementation_data).is_zero());
        assert!(
            replaceable_dispatcher
                .get_impl_activation_time(implementation_data: other_implementation_data)
                .is_non_zero(),
        );

        // Should revert with UNKNOWN_IMPLEMENTATION as replace_to removes the implementation.
        replaceable_dispatcher.replace_to(:implementation_data);
    }

    #[test]
    fn test_replace_to_final() {
        // Tests replacing an implementation to a final implementation, as follows:
        // 1. deploys a replaceable contract and another contract with different class hash
        // 2. generates a final dummy implementation replacement
        // 3. adds it to the replaceable contract
        // 4. advances time until the new implementation is ready
        // 5. replaces to the new implemenation
        // 6. checks the implementation is final
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;

        let new_class_hash = get_class_hash(contract_address: deploy_dummy_contract());
        assert_ne!(get_class_hash(:contract_address), new_class_hash);

        let implementation_data = dummy_final_implementation_data_with_class_hash(
            class_hash: new_class_hash,
        );

        // Invoke as an Upgrade Governor.
        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(2),
        );
        let mut spy = spy_events();
        replaceable_dispatcher.add_new_implementation(:implementation_data);

        // Advance time to enable implementation.
        cheat_block_timestamp(
            :contract_address,
            block_timestamp: DEFAULT_UPGRADE_DELAY + 1,
            span: CheatSpan::Indefinite,
        );
        replaceable_dispatcher.replace_to(:implementation_data);

        // Validate new class hash.
        assert_eq!(get_class_hash(:contract_address), new_class_hash);

        // Validate event emissions -- replacement and finalization of the implementation.
        let events = spy.get_events().emitted_by(:contract_address).events;
        // Should emit 3 events: ImplementationAdded, ImplementationReplaced,
        // ImplementationFinalized.
        assert!(events.len() == 3);
        assert_implementation_replaced_event_emitted(
            spied_event: events.at(1), :implementation_data,
        );
        assert_implementation_finalized_event_emitted(
            spied_event: events.at(2), :implementation_data,
        );

        // Validate finalized status.
        assert_finalized_status(expected: true, :contract_address);
    }

    #[test]
    #[feature("safe_dispatcher")]
    #[should_panic(expected: "FINALIZED")]
    fn test_replace_to_already_final() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        let replaceable_safe_dispatcher = IReplaceableSafeDispatcher { contract_address };
        let implementation_data = dummy_final_implementation_data_with_class_hash(
            get_class_hash(contract_address),
        );

        // Invoke as an Upgrade Governor.
        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(3),
        );
        replaceable_dispatcher.add_new_implementation(:implementation_data);

        // Advance time to enable implementation.
        cheat_block_timestamp(contract_address, DEFAULT_UPGRADE_DELAY + 1, CheatSpan::Indefinite);

        // Should NOT revert with FINALIZED as there is no finalized implementation yet.
        match replaceable_safe_dispatcher.replace_to(:implementation_data) {
            Result::Ok(_) => (),
            Result::Err(_) => panic!("First replace should NOT result an error"),
        }

        // Should revert with FINALIZED as the implementation is already finalized.
        replaceable_dispatcher.replace_to(:implementation_data);
    }

    // ─── Replaceability role enforcement
    // ──────────────────────────────────────

    #[test]
    fn test_upgrade_governor_can_use_replaceability() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        let account = NOT_UPGRADE_GOVERNOR_ACCOUNT;

        // Grant upgrade governor via ICommonRoles.
        cheat_caller_address_once(:contract_address, caller_address: GOVERNANCE_ADMIN);
        ICommonRolesDispatcher { contract_address }
            .grant_role(role: Role::UpgradeGovernor, :account);

        // Verify the granted account can call add_new_implementation.
        cheat_caller_address_once(:contract_address, caller_address: account);
        replaceable_dispatcher
            .add_new_implementation(
                implementation_data: dummy_nonfinal_implementation_data_with_class_hash(
                    class_hash: get_replaceability_mock_v2_class_hash(),
                ),
            );
    }

    #[test]
    #[feature("safe_dispatcher")]
    fn test_add_new_implementation_blocks_non_upgradeable() {
        // Adding a non-final implementation that points to a contract without the replaceability
        // component should fail at add time — validation cannot complete the dry-run upgrade
        // cycle on a target that lacks `add_new_implementation_unsafe` or `replace_to`.
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        let safe_dispatcher = IReplaceableSafeDispatcher { contract_address };

        let new_class_hash = get_class_hash(contract_address: deploy_dummy_contract());
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: new_class_hash,
        );

        cheat_caller_address_once(
            :contract_address, caller_address: get_upgrade_governor_account(:contract_address),
        );
        match safe_dispatcher.add_new_implementation(:implementation_data) {
            Result::Ok(_) => panic!("Should have failed: target has no replaceability component"),
            Result::Err(_) => (),
        }
    }

    #[test]
    fn test_add_new_implementation_final_skips_validation() {
        // Adding a final implementation skips validation — even if the target lacks a working
        // upgrade path. Final implementations intentionally surrender upgradeability.
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;

        let new_class_hash = get_class_hash(contract_address: deploy_dummy_contract());
        let implementation_data = dummy_final_implementation_data_with_class_hash(
            class_hash: new_class_hash,
        );

        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(2),
        );
        // Add succeeds despite non-upgradeable target — final=true skips validation.
        replaceable_dispatcher.add_new_implementation(:implementation_data);
        cheat_block_timestamp(contract_address, DEFAULT_UPGRADE_DELAY + 1, CheatSpan::Indefinite);

        replaceable_dispatcher.replace_to(:implementation_data);
        assert_eq!(get_class_hash(:contract_address), new_class_hash);
        assert_finalized_status(expected: true, :contract_address);
    }

    #[test]
    fn test_upgradeability_validation_no_side_effects() {
        // After a successful add_new_implementation, verify that the validation dry-run did
        // not corrupt storage (upgrade_delay should be unchanged — validation writes 0 in the
        // dry-run state, which is reverted by the library_call panic).
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;

        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: get_replaceability_mock_v2_class_hash(),
        );

        cheat_caller_address_once(
            :contract_address, caller_address: get_upgrade_governor_account(:contract_address),
        );
        replaceable_dispatcher.add_new_implementation(:implementation_data);

        assert_eq!(replaceable_dispatcher.get_upgrade_delay(), DEFAULT_UPGRADE_DELAY);
    }

    #[test]
    fn test_add_new_implementation_unsafe_succeeds_for_invalid_target() {
        // add_new_implementation_unsafe bypasses validation — an impl pointing to a contract
        // without the replaceability component is accepted. Verify the activation/expiration
        // entries are written.
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;

        let dummy_class_hash = get_class_hash(contract_address: deploy_dummy_contract());
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: dummy_class_hash,
        );

        cheat_caller_address_once(
            :contract_address, caller_address: get_upgrade_governor_account(:contract_address),
        );
        replaceable_dispatcher.add_new_implementation_unsafe(:implementation_data);

        // Test setup pins block_timestamp to 1, so activation_time = 1 + DEFAULT_UPGRADE_DELAY.
        assert!(
            replaceable_dispatcher
                .get_impl_activation_time(:implementation_data) == DEFAULT_UPGRADE_DELAY
                + 1,
        );
    }

    #[test]
    #[should_panic(expected: "ONLY_UPGRADE_GOVERNOR")]
    fn test_add_new_implementation_unsafe_not_upgrade_governor() {
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        // class_hash = 0 is intentional: auth fires before any storage write, so the
        // placeholder class is never used.
        let implementation_data = DUMMY_NONFINAL_IMPLEMENTATION_DATA();

        cheat_caller_address_once(:contract_address, caller_address: NOT_UPGRADE_GOVERNOR_ACCOUNT);
        replaceable_dispatcher.add_new_implementation_unsafe(:implementation_data);
    }

    #[test]
    #[feature("safe_dispatcher")]
    fn test_add_new_implementation_blocked_when_finalized() {
        // After finalization, add_new_implementation rejects — validation dispatches replace_to
        // on the target class, which (since it shares this contract's storage) reads the
        // `finalized` flag and panics FINALIZED. add_new_implementation_unsafe still succeeds
        // because it bypasses validation entirely.
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        let safe_dispatcher = IReplaceableSafeDispatcher { contract_address };

        // Finalize: schedule a final impl pointing to self, then apply it.
        let final_data = dummy_final_implementation_data_with_class_hash(
            class_hash: get_class_hash(:contract_address),
        );
        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::Indefinite,
        );
        replaceable_dispatcher.add_new_implementation(implementation_data: final_data);
        cheat_block_timestamp(contract_address, DEFAULT_UPGRADE_DELAY + 2, CheatSpan::Indefinite);
        replaceable_dispatcher.replace_to(implementation_data: final_data);
        assert_finalized_status(expected: true, :contract_address);

        // add_new_implementation must now fail — the dispatched replace_to inside validation
        // hits the finalized flag.
        let nonfinal_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: get_replaceability_mock_v2_class_hash(),
        );
        match safe_dispatcher.add_new_implementation(implementation_data: nonfinal_data) {
            Result::Ok(_) => panic!("Should fail: contract is finalized"),
            Result::Err(_) => (),
        }

        // add_new_implementation_unsafe still works — it bypasses validation.
        replaceable_dispatcher.add_new_implementation_unsafe(implementation_data: nonfinal_data);
        assert!(
            replaceable_dispatcher
                .get_impl_activation_time(implementation_data: nonfinal_data)
                .is_non_zero(),
        );
    }

    #[test]
    #[feature("safe_dispatcher")]
    fn test_intentional_brick_via_unsafe_add() {
        // add_new_implementation_unsafe lets an upgrade_governor schedule an impl that would
        // otherwise be blocked by validation. Once scheduled, replace_to applies it — bricking
        // the contract because the new code has no upgrade machinery. This test confirms both
        // halves: the unsafe path succeeds where the safe path would have blocked, AND the
        // resulting contract cannot be upgraded further.
        let replaceable_dispatcher = deploy_replaceability_mock();
        let contract_address = replaceable_dispatcher.contract_address;
        let safe_dispatcher = IReplaceableSafeDispatcher { contract_address };

        let dummy_class_hash = get_class_hash(contract_address: deploy_dummy_contract());
        let implementation_data = dummy_nonfinal_implementation_data_with_class_hash(
            class_hash: dummy_class_hash,
        );

        cheat_caller_address(
            :contract_address,
            caller_address: get_upgrade_governor_account(:contract_address),
            span: CheatSpan::TargetCalls(2),
        );
        replaceable_dispatcher.add_new_implementation_unsafe(:implementation_data);
        cheat_block_timestamp(contract_address, DEFAULT_UPGRADE_DELAY + 1, CheatSpan::Indefinite);

        // Apply the bad impl via the normal replace_to — succeeds because validation already
        // ran (or rather, was bypassed) at add time.
        replaceable_dispatcher.replace_to(:implementation_data);
        assert_eq!(get_class_hash(:contract_address), dummy_class_hash);

        // Contract is now bricked: any upgrade-related call hits a non-existent entry point.
        match safe_dispatcher.add_new_implementation(:implementation_data) {
            Result::Ok(_) => panic!("Bricked contract should not accept add_new_implementation"),
            Result::Err(_) => (),
        }
    }
}
