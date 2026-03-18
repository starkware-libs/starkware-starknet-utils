use openzeppelin::access::accesscontrol::AccessControlComponent::Errors as OZAccessErrors;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use starkware_utils::components::common_roles::mock_contract::{
    IGuardTestDispatcher, IGuardTestDispatcherTrait, IGuardTestSafeDispatcher,
    IGuardTestSafeDispatcherTrait,
};
use starkware_utils::components::roles::errors::AccessErrors;
use starkware_utils::components::roles::interface::{
    ICommonRolesDispatcher, ICommonRolesDispatcherTrait, ICommonRolesSafeDispatcher,
    ICommonRolesSafeDispatcherTrait, Role,
};
use starkware_utils::errors::Describable;
use starkware_utils_testing::constants;
use starkware_utils_testing::test_utils::{
    assert_panic_with_error, assert_panic_with_felt_error, cheat_caller_address_once,
};

fn deploy() -> (ContractAddress, ICommonRolesDispatcher) {
    let contract = *declare("CommonRolesMock").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![constants::INITIAL_ROOT_ADMIN.into()]).unwrap();
    (address, ICommonRolesDispatcher { contract_address: address })
}

fn deploy_safe() -> (ContractAddress, ICommonRolesSafeDispatcher) {
    let (address, _) = deploy();
    (address, ICommonRolesSafeDispatcher { contract_address: address })
}

// ─── initialize
// ──────────────────────────────────────────────────────────────

#[test]
fn test_initialize_grants_governance_admin() {
    let (_, dispatcher) = deploy();
    assert!(dispatcher.has_role(Role::GovernanceAdmin, constants::INITIAL_ROOT_ADMIN));
}

#[test]
fn test_initialize_grants_security_admin() {
    let (_, dispatcher) = deploy();
    assert!(dispatcher.has_role(Role::SecurityAdmin, constants::INITIAL_ROOT_ADMIN));
}

// ─── grant_role / has_role
// ────────────────────────────────────────────────────

#[test]
fn test_grant_role_authorized() {
    let (address, dispatcher) = deploy();
    let account = constants::APP_ROLE_ADMIN;
    let gov_admin = constants::INITIAL_ROOT_ADMIN;

    assert!(!dispatcher.has_role(Role::AppRoleAdmin, account));
    cheat_caller_address_once(contract_address: address, caller_address: gov_admin);
    dispatcher.grant_role(Role::AppRoleAdmin, account);
    assert!(dispatcher.has_role(Role::AppRoleAdmin, account));
}

#[test]
#[feature("safe_dispatcher")]
fn test_grant_role_unauthorized() {
    let (address, safe) = deploy_safe();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = safe.grant_role(Role::AppRoleAdmin, constants::APP_ROLE_ADMIN);
    assert_panic_with_felt_error(:result, expected_error: OZAccessErrors::MISSING_ROLE);
}

#[test]
#[feature("safe_dispatcher")]
fn test_grant_role_zero_address() {
    let (address, safe) = deploy_safe();
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::INITIAL_ROOT_ADMIN,
    );
    let result = safe.grant_role(Role::GovernanceAdmin, 0.try_into().unwrap());
    assert_panic_with_error(:result, expected_error: AccessErrors::ZERO_ADDRESS.describe());
}

// ─── revoke_role
// ─────────────────────────────────────────────────────────────

#[test]
fn test_revoke_role() {
    let (address, dispatcher) = deploy();
    let account = constants::APP_ROLE_ADMIN;
    let gov_admin = constants::INITIAL_ROOT_ADMIN;

    cheat_caller_address_once(contract_address: address, caller_address: gov_admin);
    dispatcher.grant_role(Role::AppRoleAdmin, account);
    assert!(dispatcher.has_role(Role::AppRoleAdmin, account));

    cheat_caller_address_once(contract_address: address, caller_address: gov_admin);
    dispatcher.revoke_role(Role::AppRoleAdmin, account);
    assert!(!dispatcher.has_role(Role::AppRoleAdmin, account));
}

// ─── renounce
// ────────────────────────────────────────────────────────────────

#[test]
fn test_renounce_renounceable_role() {
    let (address, dispatcher) = deploy();
    let account = constants::APP_ROLE_ADMIN;
    let gov_admin = constants::INITIAL_ROOT_ADMIN;

    cheat_caller_address_once(contract_address: address, caller_address: gov_admin);
    dispatcher.grant_role(Role::AppRoleAdmin, account);

    cheat_caller_address_once(contract_address: address, caller_address: account);
    dispatcher.renounce(Role::AppRoleAdmin);
    assert!(!dispatcher.has_role(Role::AppRoleAdmin, account));
}

#[test]
#[feature("safe_dispatcher")]
fn test_renounce_governance_admin_panics() {
    let (address, safe) = deploy_safe();
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::INITIAL_ROOT_ADMIN,
    );
    let result = safe.renounce(Role::GovernanceAdmin);
    assert_panic_with_error(
        :result, expected_error: AccessErrors::ROLE_CANNOT_BE_RENOUNCED.describe(),
    );
}

#[test]
#[feature("safe_dispatcher")]
fn test_renounce_security_admin_panics() {
    let (address, safe) = deploy_safe();
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::INITIAL_ROOT_ADMIN,
    );
    let result = safe.renounce(Role::SecurityAdmin);
    assert_panic_with_error(
        :result, expected_error: AccessErrors::ROLE_CANNOT_BE_RENOUNCED.describe(),
    );
}

// ─── only_X guards
// ────────────────────────────────────────────────────────────

fn setup_guard_test() -> (ContractAddress, ICommonRolesDispatcher, IGuardTestSafeDispatcher) {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestSafeDispatcher { contract_address: address };
    (address, dispatcher, guard)
}

fn grant(
    address: ContractAddress, dispatcher: ICommonRolesDispatcher, role: Role, to: ContractAddress,
) {
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::INITIAL_ROOT_ADMIN,
    );
    dispatcher.grant_role(:role, account: to);
}

// ── only_role ──

#[test]
fn test_only_role_authorized() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    grant(address, dispatcher, Role::AppRoleAdmin, constants::APP_ROLE_ADMIN);
    cheat_caller_address_once(contract_address: address, caller_address: constants::APP_ROLE_ADMIN);
    guard.assert_only_role(Role::AppRoleAdmin);
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_role_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_role(Role::AppRoleAdmin);
    assert_panic_with_error(:result, expected_error: AccessErrors::CALLER_MISSING_ROLE.describe());
}

// ── only_app_governor ──

#[test]
fn test_only_app_governor_authorized() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::INITIAL_ROOT_ADMIN,
    );
    dispatcher.grant_role(Role::AppRoleAdmin, constants::APP_ROLE_ADMIN);
    cheat_caller_address_once(contract_address: address, caller_address: constants::APP_ROLE_ADMIN);
    dispatcher.grant_role(Role::AppGovernor, constants::APP_GOVERNOR);
    cheat_caller_address_once(contract_address: address, caller_address: constants::APP_GOVERNOR);
    guard.assert_only_app_governor();
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_app_governor_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_app_governor();
    assert_panic_with_error(:result, expected_error: AccessErrors::ONLY_APP_GOVERNOR.describe());
}

// ── only_operator ──

#[test]
fn test_only_operator_authorized() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::INITIAL_ROOT_ADMIN,
    );
    dispatcher.grant_role(Role::AppRoleAdmin, constants::APP_ROLE_ADMIN);
    cheat_caller_address_once(contract_address: address, caller_address: constants::APP_ROLE_ADMIN);
    dispatcher.grant_role(Role::Operator, constants::OPERATOR);
    cheat_caller_address_once(contract_address: address, caller_address: constants::OPERATOR);
    guard.assert_only_operator();
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_operator_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_operator();
    assert_panic_with_error(:result, expected_error: AccessErrors::ONLY_OPERATOR.describe());
}

// ── only_token_admin ──

#[test]
fn test_only_token_admin_authorized() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::INITIAL_ROOT_ADMIN,
    );
    dispatcher.grant_role(Role::AppRoleAdmin, constants::APP_ROLE_ADMIN);
    cheat_caller_address_once(contract_address: address, caller_address: constants::APP_ROLE_ADMIN);
    dispatcher.grant_role(Role::TokenAdmin, constants::TOKEN_ADMIN);
    cheat_caller_address_once(contract_address: address, caller_address: constants::TOKEN_ADMIN);
    guard.assert_only_token_admin();
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_token_admin_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_token_admin();
    assert_panic_with_error(:result, expected_error: AccessErrors::ONLY_TOKEN_ADMIN.describe());
}

// ── only_upgrade_governor ──

#[test]
fn test_only_upgrade_governor_authorized() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    grant(address, dispatcher, Role::UpgradeGovernor, constants::UPGRADE_GOVERNOR);
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::UPGRADE_GOVERNOR,
    );
    guard.assert_only_upgrade_governor();
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_upgrade_governor_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_upgrade_governor();
    assert_panic_with_error(
        :result, expected_error: AccessErrors::ONLY_UPGRADE_GOVERNOR.describe(),
    );
}

// ── only_upgrader (upgrade_governor OR upgrade_agent) ──

#[test]
fn test_only_upgrader_authorized_as_governor() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    grant(address, dispatcher, Role::UpgradeGovernor, constants::UPGRADE_GOVERNOR);
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::UPGRADE_GOVERNOR,
    );
    guard.assert_only_upgrader();
}

#[test]
fn test_only_upgrader_authorized_as_agent() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::INITIAL_ROOT_ADMIN,
    );
    dispatcher.grant_role(Role::AppRoleAdmin, constants::APP_ROLE_ADMIN);
    cheat_caller_address_once(contract_address: address, caller_address: constants::APP_ROLE_ADMIN);
    dispatcher.grant_role(Role::UpgradeAgent, constants::UPGRADE_AGENT);
    cheat_caller_address_once(contract_address: address, caller_address: constants::UPGRADE_AGENT);
    guard.assert_only_upgrader();
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_upgrader_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_upgrader();
    assert_panic_with_error(:result, expected_error: AccessErrors::ONLY_UPGRADER.describe());
}

// ── only_security_admin ──

#[test]
fn test_only_security_admin_authorized() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    grant(address, dispatcher, Role::SecurityAdmin, constants::SECURITY_ADMIN);
    cheat_caller_address_once(contract_address: address, caller_address: constants::SECURITY_ADMIN);
    guard.assert_only_security_admin();
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_security_admin_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_security_admin();
    assert_panic_with_error(:result, expected_error: AccessErrors::ONLY_SECURITY_ADMIN.describe());
}

// ── only_security_agent ──

#[test]
fn test_only_security_agent_authorized() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    grant(address, dispatcher, Role::SecurityAgent, constants::SECURITY_AGENT);
    cheat_caller_address_once(contract_address: address, caller_address: constants::SECURITY_AGENT);
    guard.assert_only_security_agent();
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_security_agent_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_security_agent();
    assert_panic_with_error(:result, expected_error: AccessErrors::ONLY_SECURITY_AGENT.describe());
}

// ── only_security_governor ──

#[test]
fn test_only_security_governor_authorized() {
    let (address, dispatcher) = deploy();
    let guard = IGuardTestDispatcher { contract_address: address };
    grant(address, dispatcher, Role::SecurityGovernor, constants::SECURITY_GOVERNOR);
    cheat_caller_address_once(
        contract_address: address, caller_address: constants::SECURITY_GOVERNOR,
    );
    guard.assert_only_security_governor();
}

#[test]
#[feature("safe_dispatcher")]
fn test_only_security_governor_unauthorized() {
    let (address, _, guard) = setup_guard_test();
    cheat_caller_address_once(contract_address: address, caller_address: constants::WRONG_ADMIN);
    let result = guard.assert_only_security_governor();
    assert_panic_with_error(
        :result, expected_error: AccessErrors::ONLY_SECURITY_GOVERNOR.describe(),
    );
}
