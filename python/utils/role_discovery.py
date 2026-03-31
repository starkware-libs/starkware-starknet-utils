#!/usr/bin/env python3
"""
Starknet role discovery — extract role owners from contracts using the CommonRoles component.

Analogous to ``extract_roleslib_roles`` in the EVM contract discovery
(services/starkex/contract_discovery/discovery.py).

Quick setup (standalone):
    cd <repo_root>
    python3 -m venv python/.venv
    source python/.venv/bin/activate
    pip install -r python/utils/requirements.txt

Repo-wide setup (existing project workflow):
    cd <repo_root>
    python3 -m venv python/.venv
    source python/.venv/bin/activate
    pip install -e python

Usage (standalone):
    python role_discovery.py 0x<contract_address> [--chain mainnet|sepolia] [--include-past]
    python role_discovery.py 0x<contract_address> --rpc <RPC_URL> --include-unknown

Usage (importable):
    from role_discovery import extract_common_roles
    roles = asyncio.run(extract_common_roles(client, "0x<address>"))
"""

import argparse
import asyncio
import json
import logging
import sys
import warnings
from collections import defaultdict
from enum import Enum
from typing import Dict, List

from marshmallow.exceptions import ValidationError
from starknet_py.hash.selector import get_selector_from_name
from starknet_py.net.client_models import Call
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.http_client import IncompatibleRPCVersionWarning

logger = logging.getLogger(__name__)


class RoleName(str, Enum):
    AppGovernor = "AppGovernor"
    AppRoleAdmin = "AppRoleAdmin"
    GovernanceAdmin = "GovernanceAdmin"
    Operator = "Operator"
    TokenAdmin = "TokenAdmin"
    UpgradeAgent = "UpgradeAgent"
    UpgradeGovernor = "UpgradeGovernor"
    SecurityAdmin = "SecurityAdmin"
    SecurityAgent = "SecurityAgent"
    SecurityGovernor = "SecurityGovernor"


# Role IDs — must match the constants in
# packages/utils/src/components/roles/interface.cairo.
# Each is keccak256("ROLE_<NAME>") & MASK_250.
ROLE_IDS: Dict[RoleName, int] = {
    RoleName.AppGovernor: 0xD2EAD78C620E94B02D0A996E99298C59DDCCFA1D8A0149080AC3A20DE06068,
    RoleName.AppRoleAdmin: 0x3E615638E0B79444A70F8C695BF8F2A47033BF1CF95691EC3130F64939CEE99,
    RoleName.GovernanceAdmin: 0x3711C9D994FAF6055172091CB841FD4831AA743E6F3315163B06A122C841846,
    RoleName.Operator: 0x023EDB77F7C8CC9E38E8AFE78954F703AEEDA7FFFE014EEB6E56EA84E62F6DA7,
    RoleName.TokenAdmin: 0x0128D63ADBF6B09002C26CAF55C47E2F26635807E3EF1B027218AA74C8D61A3E,
    RoleName.UpgradeAgent: 0x1D8034A6DB21585E9D97CA912EB8113361E6858F64C45C9B321A4D01E949484,
    RoleName.UpgradeGovernor: 0x251E864CA2A080F55BCE5DA2452E8CFCAFDBC951A3E7FFF5023D558452EC228,
    RoleName.SecurityAdmin: 0x26BD110619D11CFDFC28E281DF893BC24828E89177318E9DBD860CDAEDEB6B3,
    RoleName.SecurityAgent: 0x37693BA312785932D430DCCF0F56FFEDD0AA7C0F8B6DA2CC4530C2717689B96,
    RoleName.SecurityGovernor: 0xA5A83E9807E87F281D865AB54B7B0ED2F7F4BBFEF73888810CA16E95E734EB,
}

ROLE_ID_TO_NAME: Dict[int, RoleName] = {v: k for k, v in ROLE_IDS.items()}

ROLE_GRANTED_SELECTOR = get_selector_from_name("RoleGranted")
HAS_ROLE_SELECTOR = get_selector_from_name("has_role")
ROLE_CHECK_ENTRYPOINTS: Dict[RoleName, str] = {
    RoleName.AppGovernor: "is_app_governor",
    RoleName.AppRoleAdmin: "is_app_role_admin",
    RoleName.GovernanceAdmin: "is_governance_admin",
    RoleName.Operator: "is_operator",
    RoleName.TokenAdmin: "is_token_admin",
    RoleName.UpgradeAgent: "is_upgrade_agent",
    RoleName.UpgradeGovernor: "is_upgrade_governor",
    RoleName.SecurityAdmin: "is_security_admin",
    RoleName.SecurityAgent: "is_security_agent",
    RoleName.SecurityGovernor: "is_security_governor",
}

RPCS = {
   "mainnet": "https://api.zan.top/public/starknet-mainnet/rpc/v0_8",
   "sepolia": "https://api.zan.top/public/starknet-sepolia/rpc/v0_8",
}

EVENT_CHUNK_SIZE = 100_000


def _to_int(address) -> int:
    return int(str(address), 0)


def _extract_role_and_account(ev: object) -> tuple[int, int] | None:
    """
    Extract (role_id, account) from RoleGranted event variants.
    Supports:
      - flat component keys: [RoleGrantedSelector, role, account, sender]
      - nested component keys: [..., RoleGrantedSelector, role, account, sender]
      - older/non-key layouts using keys[1]=role and data[0]=account
      - full data layouts using data=[role, account, sender]
    """
    keys_raw = ev["keys"] if isinstance(ev, dict) else ev.keys
    data_raw = ev["data"] if isinstance(ev, dict) else ev.data
    keys = [_to_int(v) for v in keys_raw]
    data = [_to_int(v) for v in data_raw]

    if ROLE_GRANTED_SELECTOR in keys:
        selector_pos = keys.index(ROLE_GRANTED_SELECTOR)
        if len(keys) >= selector_pos + 3:
            return keys[selector_pos + 1], keys[selector_pos + 2]

    if len(keys) >= 2 and len(data) >= 1:
        return keys[1], data[0]

    if len(data) >= 2:
        return data[0], data[1]

    return None


async def _get_events_chunk_raw(
    client: FullNodeClient,
    *,
    contract_address: str,
    key_selector_hex: str,
    from_block_number: int,
    to_block_number: int,
    continuation_token: str | None = None,
) -> tuple[list, str | None]:
    """
    Low-level getEvents request that bypasses strict starknet_py schema loading.
    Some RPC providers omit transaction_index/event_index fields.
    """
    params = {
        "address": contract_address,
        "keys": [[key_selector_hex]],
        "from_block": {"block_number": from_block_number},
        "to_block": {"block_number": to_block_number},
        "chunk_size": 1000,
    }
    if continuation_token is not None:
        params["continuation_token"] = continuation_token

    raw = await client._client.call(  # pyright: ignore[reportPrivateUsage]
        method_name="getEvents",
        params={"filter": params},
    )
    return raw.get("events", []), raw.get("continuation_token")


async def _has_role(
    client: FullNodeClient,
    contract_address: int,
    role_id: int,
    account: int,
    block: str | int = "latest",
) -> bool:
    """Call ``has_role(role, account)`` on a CommonRoles contract."""
    result = await client.call_contract(
        call=Call(
            to_addr=contract_address,
            selector=HAS_ROLE_SELECTOR,
            calldata=[role_id, account],
        ),
        block_number=block,
    )
    return len(result) > 0 and result[0] == 1


def _is_missing_entrypoint_error(error: Exception) -> bool:
    msg = str(error).lower()
    return "entry point" in msg and "not found" in msg


async def _call_bool_entrypoint(
    client: FullNodeClient,
    contract_address: int,
    entrypoint: str,
    calldata: list[int],
    block: str | int = "latest",
) -> bool:
    result = await client.call_contract(
        call=Call(
            to_addr=contract_address,
            selector=get_selector_from_name(entrypoint),
            calldata=calldata,
        ),
        block_number=block,
    )
    return len(result) > 0 and result[0] == 1


async def _supports_has_role(
    client: FullNodeClient,
    contract_address: int,
    block: str | int = "latest",
) -> bool:
    """
    Probe whether `has_role(role, account)` exists on the contract.
    """
    try:
        await _call_bool_entrypoint(
            client,
            contract_address,
            "has_role",
            [ROLE_IDS[RoleName.AppGovernor], 0],
            block=block,
        )
        return True
    except Exception as e:
        if _is_missing_entrypoint_error(e):
            return False
        # Non-interface errors shouldn't force a fallback mode.
        logger.warning("Failed probing has_role support: %s", e)
        return True


async def _has_legacy_role(
    client: FullNodeClient,
    contract_address: int,
    role_name: RoleName,
    account: int,
    block: str | int = "latest",
) -> bool:
    entrypoint = ROLE_CHECK_ENTRYPOINTS.get(role_name)
    if entrypoint is None:
        return False
    try:
        return await _call_bool_entrypoint(
            client,
            contract_address,
            entrypoint,
            [account],
            block=block,
        )
    except Exception as e:
        logger.warning(
            "legacy role check %s failed for account %s: %s",
            entrypoint,
            hex(account),
            e,
        )
        return False


async def _fetch_role_granted_events(
    client: FullNodeClient,
    contract_address: str | int,
    from_block: int = 0,
    to_block: str | int = "latest",
) -> list:
    """Fetch all OZ AccessControl ``RoleGranted`` events emitted by *contract_address*."""
    address_hex = hex(_to_int(contract_address))
    key_selector_hex = hex(ROLE_GRANTED_SELECTOR)
    if isinstance(to_block, str):
        to_block = await client.get_block_number()

    all_events = []
    for chunk_start in range(from_block, to_block + 1, EVENT_CHUNK_SIZE):
        chunk_end = min(chunk_start + EVENT_CHUNK_SIZE - 1, to_block)
        try:
            resp = await client.get_events(
                address=address_hex,
                keys=[[key_selector_hex]],
                from_block_number=chunk_start,
                to_block_number=chunk_end,
                follow_continuation_token=True,
            )
            all_events.extend(resp.events)
        except ValidationError:
            logger.warning(
                "RPC omitted event indices; using raw getEvents fallback for blocks %s-%s",
                chunk_start,
                chunk_end,
            )
            token = None
            while True:
                events, token = await _get_events_chunk_raw(
                    client,
                    contract_address=address_hex,
                    key_selector_hex=key_selector_hex,
                    from_block_number=chunk_start,
                    to_block_number=chunk_end,
                    continuation_token=token,
                )
                all_events.extend(events)
                if token is None:
                    break
    return all_events


async def extract_common_roles(
    client: FullNodeClient,
    contract_address: str | int,
    from_block: int = 0,
    to_block: str | int = "latest",
    include_past: bool = False,
    include_unknown: bool = False,
) -> Dict[str, List[str]]:
    """
    Extract current (or historical) role owners from a Starknet contract that
    uses the CommonRoles / OZ-AccessControl component.

    Returns ``{role_name: [hex_address, ...]}`` for every role that has at least one owner.

    When *include_past* is ``True``, every address that was **ever** granted a
    role is returned without verifying current membership.
    When *include_unknown* is ``True``, discovered role IDs not in ``ROLE_IDS``
    are also returned as ``UNKNOWN_ROLE_<hex_role_id>``.
    """
    addr_int = _to_int(contract_address)
    events = await _fetch_role_granted_events(
        client,
        contract_address,
        from_block=from_block,
        to_block=to_block,
    )
    logger.info("Fetched %d RoleGranted events from %s", len(events), hex(addr_int))

    # Event layout (OZ AccessControl, #[flat] component embedding):
    #   keys = [sn_keccak("RoleGranted"), role_id]
    #   data = [account, sender]
    role_grants: Dict[int, set] = defaultdict(set)
    for ev in events:
        extracted = _extract_role_and_account(ev)
        if extracted is None:
            continue
        role_id, account = extracted
        role_grants[role_id].add(account)

    role_owners: Dict[str, List[str]] = {}
    block_arg: str | int = to_block if isinstance(to_block, int) else "latest"
    has_role_supported = await _supports_has_role(client, addr_int, block=block_arg)
    if not has_role_supported:
        logger.debug(
            "Contract does not expose has_role(role, account); using legacy is_<role>(account) checks."
        )

    roles_to_check: list[tuple[RoleName | str, int]] = list(ROLE_IDS.items())
    if include_unknown:
        for role_id in sorted(role_grants.keys()):
            if role_id not in ROLE_ID_TO_NAME:
                roles_to_check.append((f"UNKNOWN_ROLE_{hex(role_id)}", role_id))

    for role_name, role_id in roles_to_check:
        candidates = role_grants.get(role_id, set())
        if not candidates:
            continue

        if include_past:
            owners = sorted(candidates)
        else:
            owners = []
            for acct in sorted(candidates):
                if has_role_supported:
                    try:
                        has_it = await _has_role(
                            client,
                            addr_int,
                            role_id,
                            acct,
                            block=block_arg,
                        )
                    except Exception as e:
                        if _is_missing_entrypoint_error(e):
                            # Missing entry point means this contract uses legacy role check entrypoints.
                            has_role_supported = False
                            logger.debug(
                                "has_role missing entrypoint (%s); switching to legacy is_<role>(account) checks for this contract run.",
                                e,
                            )
                            has_it = await _has_legacy_role(
                                client,
                                addr_int,
                                role_name,
                                acct,
                                block=block_arg,
                            )
                        else:
                            raise
                else:
                    has_it = await _has_legacy_role(
                        client,
                        addr_int,
                        role_name,
                        acct,
                        block=block_arg,
                    )
                if has_it:
                    owners.append(acct)

        if owners:
            role_name_str = (
                role_name.value if isinstance(role_name, RoleName) else role_name
            )
            role_owners[role_name_str] = [hex(a) for a in owners]
            logger.info("  %s: %s", role_name_str, role_owners[role_name_str])

    unknown_role_ids = sorted(
        role_id for role_id in role_grants.keys() if role_id not in ROLE_ID_TO_NAME
    )
    if role_grants and not role_owners:
        if unknown_role_ids:
            logger.warning(
                "RoleGranted events found, but none match CommonRoles IDs. Unknown role IDs: %s",
                ", ".join(hex(r) for r in unknown_role_ids),
            )
        else:
            logger.warning(
                "RoleGranted events found, but no current CommonRoles holders were detected."
            )

    return role_owners


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Extract role owners from a Starknet contract using CommonRoles.",
    )
    parser.add_argument("contract_address", help="Contract address (hex)")
    parser.add_argument(
        "--chain",
        choices=["mainnet", "sepolia"],
        default="mainnet",
        help="Starknet network (default: mainnet)",
    )
    parser.add_argument(
        "--rpc",
        default=None,
        help="Custom RPC URL (overrides --chain)",
    )
    parser.add_argument(
        "--from-block",
        type=int,
        default=0,
        help="Start scanning from this block (default: 0)",
    )
    parser.add_argument(
        "--include-past",
        action="store_true",
        help="Include addresses that were ever granted a role, even if revoked",
    )
    parser.add_argument(
        "--include-unknown",
        action="store_true",
        help="Include discovered role IDs not mapped to CommonRoles constants",
    )
    parser.add_argument(
        "--log_level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        default="WARNING",
        help="Logging level (default: WARNING)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Shorthand for --log_level=DEBUG",
    )
    return parser


async def _main():
    args = _build_parser().parse_args()
    effective_log_level = "DEBUG" if args.verbose else args.log_level

    if effective_log_level != "DEBUG":
        warnings.filterwarnings("ignore", category=IncompatibleRPCVersionWarning)
    logging.basicConfig(
        level=getattr(logging, effective_log_level),
        format="%(levelname)s: %(message)s",
        stream=sys.stderr,
    )

    rpc_url = args.rpc or RPCS[args.chain]
    client = FullNodeClient(rpc_url)

    try:
        roles = await extract_common_roles(
            client,
            contract_address=args.contract_address,
            from_block=args.from_block,
            include_past=args.include_past,
            include_unknown=args.include_unknown,
        )
        print(json.dumps(roles, sort_keys=True, indent=2))
    except Exception as e:
        print(json.dumps({"error": str(e)}, sort_keys=True, indent=2))
        raise SystemExit(1)


if __name__ == "__main__":
    asyncio.run(_main())
