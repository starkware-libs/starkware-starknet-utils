import asyncio
import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest
from marshmallow.exceptions import ValidationError
from starknet_py.hash.selector import get_selector_from_name


def _load_role_discovery_module():
    module_path = Path(__file__).resolve().parents[1] / "utils" / "role_discovery.py"
    spec = importlib.util.spec_from_file_location("role_discovery", module_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


role_discovery = _load_role_discovery_module()


APP_GOVERNOR = role_discovery.ROLE_IDS[role_discovery.RoleName.AppGovernor]
ROLE_GRANTED = role_discovery.ROLE_GRANTED_SELECTOR
HAS_ROLE_SELECTOR = get_selector_from_name("has_role")
IS_APP_GOVERNOR_SELECTOR = get_selector_from_name("is_app_governor")


class MissingEntrypointClient:
    def __init__(self):
        self.has_role_calls = 0

    async def get_block_number(self):
        return 10

    async def get_events(self, **kwargs):
        return SimpleNamespace(
            events=[
                SimpleNamespace(keys=[ROLE_GRANTED, APP_GOVERNOR], data=[0x111, 0xAAA]),
            ],
        )

    async def call_contract(self, call, block_number="latest"):
        if call.selector == HAS_ROLE_SELECTOR:
            self.has_role_calls += 1
            raise Exception("Entry point has_role not found in contract")
        if call.selector == IS_APP_GOVERNOR_SELECTOR:
            return [1]
        return [0]


class NonMissingFailureClient:
    async def get_block_number(self):
        return 10

    async def get_events(self, **kwargs):
        return SimpleNamespace(
            events=[
                SimpleNamespace(keys=[ROLE_GRANTED, APP_GOVERNOR], data=[0x111, 0xAAA]),
            ],
        )

    async def call_contract(self, call, block_number="latest"):
        if call.selector == HAS_ROLE_SELECTOR:
            raise Exception("rpc timeout")
        return [0]


class ValidationFallbackClient:
    class RawRpc:
        async def call(self, method_name, params):
            return {
                "events": [
                    {
                        "keys": [
                            hex(ROLE_GRANTED),
                            hex(APP_GOVERNOR),
                            hex(0x222),
                            hex(0xAAA),
                        ],
                        "data": [],
                    },
                ],
                "continuation_token": None,
            }

    def __init__(self):
        self._client = self.RawRpc()

    async def get_block_number(self):
        return 5

    async def get_events(self, **kwargs):
        raise ValidationError(
            {
                "events": {
                    0: {
                        "transaction_index": ["Missing data for required field."],
                        "event_index": ["Missing data for required field."],
                    },
                },
            },
        )

    async def call_contract(self, call, block_number="latest"):
        return [1]


def test_missing_entrypoint_falls_back_to_legacy():
    client = MissingEntrypointClient()
    roles = asyncio.run(role_discovery.extract_common_roles(client, "0x1"))
    assert roles == {"AppGovernor": ["0x111"]}
    assert client.has_role_calls == 1


def test_non_missing_has_role_error_is_raised():
    with pytest.raises(Exception, match="rpc timeout"):
        asyncio.run(
            role_discovery.extract_common_roles(NonMissingFailureClient(), "0x1")
        )


def test_validation_error_uses_raw_get_events_fallback():
    roles = asyncio.run(
        role_discovery.extract_common_roles(
            ValidationFallbackClient(),
            "0x1",
            from_block=0,
            to_block=5,
        ),
    )
    assert roles == {"AppGovernor": ["0x222"]}
