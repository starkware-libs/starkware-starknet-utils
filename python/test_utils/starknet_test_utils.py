import contextlib
import logging
import os
import signal
import subprocess
import tempfile
from starknet_py.net.account.account import Account
from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.signer.key_pair import KeyPair
from starknet_py.net.signer.stark_curve_signer import StarkCurveSigner
import requests
from starknet_py.contract import Contract
import re
from pathlib import Path
import socket
import errno
import time


logger = logging.getLogger(__name__)

SIERRA_PROGRAM_KEY = "sierra_program"
SIERRA_KEY = "sierra"
CASM_KEY = "casm"
ABI_KEY = "abi"


def get_contract_path(contract_name: str, base_path: Path) -> Path:
    return base_path / f"{contract_name}.json"


def load_contract(contract_name: str, base_path: Path) -> str:
    contract_path = get_contract_path(contract_name=contract_name, base_path=base_path)
    return contract_path.read_text("utf-8")


# Due to the fixed seed, the starknet devnet will always start with the same state.
ETH_Address = 0x49D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7
Class_Hash = 0x46DED64AE2DEAD6448E247234BAB192A9C483644395B66F2155F2614E5804B0
STRK_Address = 0x4718F5A0FC34CC1AF16A1CDEE98FFB20C31F5CD61D6AB07201858F4287C938D
Class_Hash = 0x46DED64AE2DEAD6448E247234BAB192A9C483644395B66F2155F2614E5804B0

# Predeployed UDC
UDC_Address = 0x41A78E741E5AF2FEC34B695679BC6891742439F7AFB8484ECD7766661AD02BF
UDC_Class_Hash = 0x7B3E05F48F0C69E4A65CE5E076A66271A527AFF2C34CE1083EC6E1526997A69

# Account addresses and key pairs for testing

keys = [
    "0x00000000000000000000000000000000b4fac4a807d5f17016e1b8ab17a865c4",
    "0x0000000000000000000000000000000024231a9d8f74eae8cbd8c80826c8193a",
    "0x000000000000000000000000000000001293ea7b811536b80758de00247d8183",
    "0x00000000000000000000000000000000fb49b1af8bb4c3e87701d41368f001f3",
    "0x0000000000000000000000000000000027741a991a8b3a637d0c42276f0981e7",
    "0x00000000000000000000000000000000437756c310eefe42413cf7a5ffbbe349",
    "0x000000000000000000000000000000006e54993e3de6455e0c808713dec59617",
    "0x00000000000000000000000000000000f401ceaef4f781d0a00f79a5353b6b8c",
    "0x0000000000000000000000000000000097bcc69c1f8dceeb9e4171f7d6f2c8a3",
    "0x000000000000000000000000000000009fa01c7fc02a46988a06ddaf75736838",
    "0x00000000000000000000000000000000ea05845eccb044a807a4e8c14b5f16d7",
    "0x00000000000000000000000000000000944d96ff107fc49bc63b33a12586047c",
    "0x00000000000000000000000000000000a468091c646cacb04d0921d13e9f2cff",
    "0x00000000000000000000000000000000dfcb05cc360b82bb4bd8362c5fb74265",
    "0x000000000000000000000000000000003ebeb153a6555be576e80f24ed808a7c",
]
addresses = [
    "0x05b99fc6098fb3bf5a0f95cab6b7a2b6fd376bc04b2fea0ca7eb8f72216ec3b2",
    "0x063ca12081899481a94345c926661121eeab13655be408edb5c7fec854702520",
    "0x067f3fa88e047a4cc5f656423b7253bf01a2144487017fdde7f55d7a702d83d9",
    "0x02a5a18bdfd211dcc91b0145773961a72afaa39f85b3c97ab5b9d3398f658622",
    "0x0574fff23ea8c1779a7978efc0a059b6336fa4e04090118ee9aa88507c341a62",
    "0x030abb3e39b3488ec7e4381d46301cb23c4b409fa80c4fc846949ae77978d279",
    "0x077b18cd56d4ce334687bffe78123ccff4c5ea15dda013c58f17c769af39e135",
    "0x0215b7fd7d85b59c344feab99d06acbfb08d509ee4fbe87e50c304dbe074d8f0",
    "0x06eb4627dff4d0519441dd9bc05f8af2b51e21695b935a56490cbebbb985a562",
    "0x0061aa21aae0cc11130f60295c2b1157e309b0ba833d00c6b82722c11f35a748",
    "0x007f5dc1da6d2e2bb641850371f7dbcd8c9c9f5f8cd40cd44e02219cc1689da3",
    "0x07fa72a7903683ebf3efcc5f15d34027952a5225bda7f9b7672f494ad789a363",
    "0x0737cfc12916c61e36bc01bc34fb988bb752a704b21b795b878b5c3c7031a8c2",
    "0x00541b44e24c57583bdc3502a84be8db16c586fd113b44707f9e67de5675d85b",
    "0x06d7642f72bf5ccf66f4c05c21c5214004b6bd9195de2a22a4704352ec14adc2",
]


class StarknetTestUtils:
    """
    Allows testing Starknet contracts.
    """

    MAX_RETRIES = 5

    def __init__(self, port: int):
        self.starknet = Starknet(port=port)
        self.accounts = self.starknet.accounts

    def stop(self):
        self.starknet.stop()

    @classmethod
    @contextlib.contextmanager
    def context_manager(cls, port: int | None = None, backoff: float = 0.1):
        """
        Retry creating a Starknet instance if port is already in use.
        If port is None, will pick random free port.
        """
        for attempt in range(cls.MAX_RETRIES):
            try:
                actual_port = port or get_free_port()
                res = cls(port=actual_port)
                yield res
                return
            except OSError as e:
                if e.errno in (errno.EADDRINUSE, errno.EACCES):  # port in use
                    if attempt < cls.MAX_RETRIES - 1:
                        time.sleep(backoff)  # short backoff
                        continue
                    raise
            finally:
                try:
                    res.stop()
                except Exception:
                    pass

    def advance_time(self, n_seconds: int):
        payload = {
            "jsonrpc": "2.0",
            "id": "1",
            "method": "devnet_increaseTime",
            "params": {"time": n_seconds},
        }
        rpc_url = f"{self.starknet.get_client().url}\rpc"
        response = requests.post(rpc_url, json=payload)
        response.raise_for_status()


class Starknet:
    """
    Represents a running instance of starknet.
    """

    def __init__(
        self,
        port: int = 5050,
        seed: int = 500,
        initial_balance: int = 10**30,
        accounts: int = 15,
        starknet_chain_id: StarknetChainId = StarknetChainId.SEPOLIA,
    ):
        """
        Runs starknet.
        Use stop() to ensure the process is killed at the end.
        """
        self.err_stream = tempfile.NamedTemporaryFile()
        self.port = port
        self.seed = seed
        self.initial_balance = initial_balance
        self.accounts = accounts
        self.starknet_chain_id = starknet_chain_id

        command = (
            "starknet-devnet "
            f"--port {self.port} "
            f"--seed {self.seed} "
            f"--initial-balance {self.initial_balance} "
            f"--accounts {self.accounts} "
            "--lite-mode"
        )
        self.starknet_proc = subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.DEVNULL,
            stderr=self.err_stream,
            # Open the process in a new process group.
            start_new_session=True,
        )
        self.is_alive = True
        self.accounts = []
        key_pairs = []
        for key in keys:
            key_pairs.append(KeyPair.from_private_key(key))

        for i in range(len(addresses)):
            signer = StarkCurveSigner(addresses[i], key_pairs[i], self.starknet_chain_id)

            account = Account(
                client=self.get_client(),
                address=addresses[i],
                signer=signer,
                chain=self.starknet_chain_id,
            )
            self.accounts.append(account)

    def __del__(self):
        self.stop()

    def get_client(self) -> FullNodeClient:
        node_url = f"http://localhost:{self.port}"
        return FullNodeClient(node_url=node_url)

    def stop(self):
        if not self.is_alive:
            return

        # Kill the entire process group.
        os.killpg(self.starknet_proc.pid, signal.SIGINT)
        self.is_alive = False
        # Capture errors.
        self.err_stream.flush()
        self.err_stream.seek(0)
        stderr_data = self.err_stream.read().decode()
        if len(stderr_data) > 0:
            logger.error(f"Starknet stderr data:\n{str(stderr_data)}\n")
        self.err_stream.close()


async def grant_roles(contracts_by_role: dict[str, Contract], roles: dict[str, Account]):
    for role_name in ["app_role_admin", "upgrade_governor", "security_admin"]:
        await (
            await contracts_by_role["governance_admin"]
            .functions[f"register_{role_name}"]
            .invoke_v3(roles[role_name].address, auto_estimate=True)
        ).wait_for_acceptance(check_interval=0.1)

    for role_name in ["app_governor", "operator", "token_admin"]:
        await (
            await contracts_by_role["app_role_admin"]
            .functions[f"register_{role_name}"]
            .invoke_v3(roles[role_name].address, auto_estimate=True)
        ).wait_for_acceptance(check_interval=0.1)

    await (
        await contracts_by_role["security_admin"]
        .functions["register_security_agent"]
        .invoke_v3(roles["security_agent"].address, auto_estimate=True)
    ).wait_for_acceptance(check_interval=0.1)


def get_cairo_int_constant(file_path: Path, constant_name: str) -> int:
    """
    Extracts a Cairo integer constant from a file.
    """
    content = file_path.read_text()

    # Normalize multi-line expressions into a single line
    content = re.sub(r"\\\n", "", content)  # remove backslash-newline
    content = re.sub(r"\s*\n\s*", " ", content)  # join lines

    # Pattern to extract the numeric value (with optional type suffix and try_into)
    pattern = rf"""
        pub\s+const\s+{re.escape(constant_name)}
        \s*:\s*[\w\d]+
        \s*=\s*
        (?P<val>0x[0-9a-fA-F_]+|[0-9_]+)
        (_[uU]\d+)?
        (\s*\.\s*try_into\(\)\s*\.\s*unwrap\(\))?
        \s*;
    """

    match = re.search(pattern, content, re.VERBOSE)
    if not match:
        raise ValueError(f"Constant '{constant_name}' not found in {file_path}")

    raw = match.group("val").replace("_", "")
    return int(raw, 16 if raw.startswith("0x") else 10)


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]
