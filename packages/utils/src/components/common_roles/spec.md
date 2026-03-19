# CommonRolesComponent — Specification

## Overview

The role system is split into two layers:

- **`CommonRolesComponent`** — lean infrastructure. Owns the role constants, the `Role` enum, role admin configuration, role guards (`only_X`), a 7-method ABI (`ICommonRoles`: `grant_role`, `revoke_role`, `has_role`, `renounce`, and the three legacy reclaim entry points), and the legacy reclaim storage (`role_members` map + `legacy_role_reclaim_disabled` flag).
- **`RolesComponent`** — full-featured layer. Delegates all role state to `CommonRolesComponent` internally. Adds named role events (20 variants) and category-scoped embeddable implementations (`IGovernanceRoles`, `ISecurityRoles`, `IAppRoles`), and the fat `IRoles` interface (~30 EPs).

The design lets contracts pick exactly the role surface they need — from zero ABI overhead up to the full named interface — without duplicating any role logic.

---

## Role Hierarchy

| Role | Admin Role | Category Interface |
|---|---|---|
| `GovernanceAdmin` | `GovernanceAdmin` (self) | `IGovernanceRoles` |
| `AppRoleAdmin` | `GovernanceAdmin` | `IGovernanceRoles` |
| `UpgradeGovernor` | `GovernanceAdmin` | `IGovernanceRoles` |
| `UpgradeAgent` | `AppRoleAdmin` | `IGovernanceRoles` |
| `SecurityAdmin` | `SecurityAdmin` (self) | `ISecurityRoles` |
| `SecurityAgent` | `SecurityAdmin` | `ISecurityRoles` |
| `SecurityGovernor` | `SecurityAdmin` | `ISecurityRoles` |
| `AppGovernor` | `AppRoleAdmin` | `IAppRoles` |
| `Operator` | `AppRoleAdmin` | `IAppRoles` |
| `TokenAdmin` | `AppRoleAdmin` | `IAppRoles` |

`GovernanceAdmin` and `SecurityAdmin` are self-administered and cannot be renounced. All other roles are renounceable.

---

## Category Sub-Interfaces

Three `#[starknet::interface]` traits group related roles into a narrower ABI slice:

- **`IGovernanceRoles`** — governance admin, app role admin, upgrade governor, upgrade agent. These are coupled: governance admin appoints upgrade governors; upgrade governors control contract upgrades; app role admin is the gateway to the app-level roles.
- **`ISecurityRoles`** — security admin, security agent, security governor.
- **`IAppRoles`** — app governor, operator, token admin.

These interfaces are defined in `roles/interface.cairo` and **implemented only by `RolesComponent`** (`GovernanceRolesImpl`, `SecurityRolesImpl`, `AppRolesImpl`). They exist so contracts can expose a scoped ABI without pulling in all 30 `IRoles` entry points.

---

## Usage Patterns

### Tier A — Infrastructure only

For components that only need role *checks*, with no named role management ABI of their own (e.g., replaceability, pausable, blocklist).

**Wire:** `CommonRolesComponent` + `AccessControlComponent` + `SRC5Component`. No `RolesComponent`.

**Embed:** `CommonRolesImpl` → 7 entry points: `grant_role`, `revoke_role`, `has_role`, `renounce`, `reclaim_legacy_roles`, `reclaim_legacy_roles_for_accounts`, `disable_legacy_role_reclaim`.

**Role management:** callers use `ICommonRoles::grant_role(Role::UpgradeGovernor, account)`.

**Constructor:**
```cairo
fn constructor(ref self: ContractState, governance_admin: ContractAddress) {
    self.common_roles.initialize(:governance_admin);
}
```

---

### Tier B — Selective named roles

For contracts that need a subset of named role management EPs and their named events, but not the full `IRoles` bloat (e.g., an ERC20 with replaceability that only needs governance + upgrade management).

**Wire:** `RolesComponent` + `CommonRolesComponent` + `AccessControlComponent` + `SRC5Component`.

**Embed:** only the category impl(s) you need — do NOT embed `RolesImpl`.

```cairo
#[abi(embed_v0)]
impl GovernanceRolesImpl = RolesComponent::GovernanceRolesImpl<ContractState>;
#[abi(embed_v0)]
impl CommonRolesImpl = CommonRolesComponent::CommonRolesImpl<ContractState>;
// NO RolesImpl
```

**ABI result:** `IGovernanceRoles` (12 EPs) + `ICommonRoles` (7 EPs). Named events (`UpgradeGovernorAdded`, etc.) are emitted by the category impl methods. Unused event variants are dead-code eliminated from Sierra.

**Constructor:**
```cairo
fn constructor(ref self: ContractState, governance_admin: ContractAddress) {
    self.roles.initialize(:governance_admin);
}
```

---

### Tier C — Full roles

For contracts that expose the complete named role management API (existing pattern).

**Wire:** `RolesComponent` + `CommonRolesComponent` + `AccessControlComponent` + `SRC5Component`.

**Embed:** `RolesImpl` → all ~30 entry points + all 20 named events.

**Constructor:**
```cairo
fn constructor(ref self: ContractState, governance_admin: ContractAddress) {
    self.roles.initialize(:governance_admin);
}
```

---

## Key Invariants

- `CommonRolesComponent` owns all role state — `AccessControlComponent` holds the active role memberships; `CommonRolesComponent` holds the legacy reclaim storage (`role_members` map + `legacy_role_reclaim_disabled` flag).
- `RolesComponent` never duplicates role state — it reads and writes through `CommonRolesComponent`'s internal methods.
- Named events exist only in `RolesComponent::Event`. `CommonRolesComponent::Event` is always empty.
- Category impls exist only in `RolesComponent`. There is no duplication between layers.
- `IGovernanceRolesDispatcher` dispatches correctly against any contract that embeds `RolesImpl`, because `IRoles` exposes the same selectors as `IGovernanceRoles`.
