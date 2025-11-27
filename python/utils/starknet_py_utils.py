from starknet_py.net.full_node_client import FullNodeClient
from starknet_py.net.account.account import Account
from starknet_py.net.models.chains import StarknetChainId
from starknet_py.net.signer.key_pair import KeyPair
from starknet_py.contract import Contract, PreparedFunctionInvokeV3, DeclareResult
from starknet_py.hash.selector import get_selector_from_name
from starknet_py.net.client_models import TransactionStatus
from starknet_py.transaction_errors import (
    TransactionRejectedError,
    TransactionRevertedError,
)
from starknet_py.net.models.transaction import InvokeV3
from starknet_py.net.client_models import (
    ResourceBoundsMapping,
    ResourceBounds,
    Call,
    TransactionExecutionStatus,
)
from starknet_py.hash.utils import verify_message_signature
from starknet_py.proxy.contract_abi_resolver import ContractAbiResolver, ProxyConfig
import aiohttp
import re
import asyncio
import json
from pathlib import Path
from dataclasses import dataclass, asdict, replace
from eth_utils import to_hex, to_int
from ..config import (
    TX_CALLDATA,
    TX_NONCE,
    TX_SENDER_ADDRESS,
    TX_VERSION,
    TX_ACCOUNT_DEPLOYMENT_DATA,
    TX_RESOURCE_BOUNDS,
    TX_SIGNATURE,
)
from .starkli_utils import get_starkli_private_key
from .utils import print_debug, normalize_value


FETCH_EVENTS_CHUNK_SIZE = 100000
UNIVERSAL_GAS_MODEFIER = 10
UPGRADE_FUNCTIONS = [
    "add_new_implementation",
    "replace_to",
]
# RPC
SEPOLIA_RPCS = {
    "pathfinder": "https://starknet-sepolia.public.blastapi.io/rpc/v0_8",
    "juno": "https://staging-rpc.nethermind.dev/sepolia-juno",
}

MAINNET_RPCS = {
    "pathfinder": "https://starknet-mainnet.public.blastapi.io/rpc/v0_8",
    "juno": "https://staging-rpc.nethermind.dev/mainnet-juno",
}
RPC = {StarknetChainId.SEPOLIA: SEPOLIA_RPCS, StarknetChainId.MAINNET: MAINNET_RPCS}


# Dataclasses for upgrade contracts
@dataclass
class EICData:
    eic_hash: str
    eic_init_data: list


@dataclass
class ImplementationData:
    impl_hash: str
    eic_data: EICData
    final: bool


def set_event_chunk_size(chunk_size: int):
    global FETCH_EVENTS_CHUNK_SIZE
    FETCH_EVENTS_CHUNK_SIZE = chunk_size


async def wait_for_tx_acceptance(
    tx_hash: str | int,
    node: FullNodeClient,
    check_interval: float = 2,
    retries: int = 500,
):
    """
    Awaits for transaction to get accepted by polling its status..

    :param tx_hash: The hash of the transaction to wait for.
    :param node: The node to wait for the transaction on.
    :param check_interval: Defines interval between checks.
    :param retries: Defines how many times the transaction is checked until an error is thrown.
    """
    if check_interval <= 0:
        raise ValueError("Argument check_interval has to be greater than 0.")
    if retries <= 0:
        raise ValueError("Argument retries has to be greater than 0.")

    tx_status = await node.get_transaction_status(tx_hash=tx_hash)

    while True:
        retries -= 1
        if tx_status.finality_status == TransactionStatus.REJECTED:
            raise TransactionRejectedError()

        if (
            tx_status.finality_status == TransactionStatus.ACCEPTED_ON_L2
            or tx_status.finality_status == TransactionStatus.ACCEPTED_ON_L1
        ):
            if tx_status.execution_status == TransactionExecutionStatus.REVERTED:
                raise TransactionRevertedError()
            return

        if retries == 0:
            raise ValueError("Transaction not accepted.")

        await asyncio.sleep(check_interval)


def get_chain_id(chain: str) -> StarknetChainId:
    """
    Get the chain id.

    :param chain: String of the chain.
    :return: The starknet chain id.
    """
    if chain == "mainnet":
        return StarknetChainId.MAINNET
    elif chain == "sepolia":
        return StarknetChainId.SEPOLIA
    else:
        raise ValueError(
            f"Invalid chain: {chain}. Chain must be 'mainnet' or 'sepolia'."
        )


def setup_node(
    chain: StarknetChainId, rpc: str, api_key: str | None, local_rpc: str | None = None
) -> tuple[FullNodeClient, aiohttp.ClientSession | None]:
    """
    Setup the RPC.

    :param rpc: The RPC to use.
    :return: The RPC.
    """
    session = None
    if rpc == "local":
        assert local_rpc is not None, "local_rpc is required when using local RPC."
        node = FullNodeClient(local_rpc)
    else:
        if rpc == "juno":
            assert api_key is not None, "API key is required when using Juno's RPC."
            session = aiohttp.ClientSession(headers={"x-apikey": api_key})
        node = FullNodeClient(RPC[chain][rpc], session=session)
    return node, session


def setup_keystore_account(
    node: FullNodeClient,
    chain: StarknetChainId,
    account_address: str,
    keystore_file: str,
    keystore_password: str,
) -> Account:
    """
    Setup the starknet.py account.

    :param node: The node to use.
    :param chain: The chain to use.
    :param account_address: The address of the account.
    :param keystore_file: The path to the keystore file.
    :param keystore_password: The password for the keystore file.
    :return: The starknet.py account.
    """
    # Create Account object
    account = Account(
        client=node,
        address=account_address,
        key_pair=KeyPair.from_private_key(
            key=get_starkli_private_key(keystore_file, keystore_password)
        ),
        chain=chain,
    )
    return account


# def setup_ledger_account(
#     chain: StarknetChainId,
#     node: FullNodeClient,
#     account_address: str,
#     derivation_path: str,
# ) -> Account:
#     # Set the signer.
#     signer = LedgerSigner(
#         derivation_path_str=derivation_path,
#         chain_id=chain,
#     )
#     # Create an `Account` instance with the ledger signer.
#     account = Account(
#         client=node,
#         address=account_address,
#         signer=signer,
#         chain=chain,
#     )
#     return account


def get_contract_abi(
    contract_name: str, contract_folder: str, package: str, target: str = "release"
) -> list:
    """
    Return the ABI of the contract.

    :param contract_name: The name of the contract to get the ABI for.
    :param contract_folder: The folder containing the contract.
    :param package: The package name.
    :return: The ABI of the contract.
    """
    base_path = Path(contract_folder)
    contract_class_path = (
        base_path / "target" / target / f"{package}_{contract_name}.contract_class.json"
    )
    if not contract_class_path.exists():
        raise FileNotFoundError(
            f"{package}_{contract_name}.contract_class.json file not found in {contract_folder}/target/{target}. Please run `scarb build` first."
        )
    with open(contract_class_path, "r") as f:
        return json.load(f)["abi"]


async def get_contract_abi_from_node(
    contract_address: str, node: FullNodeClient
) -> list:
    """
    Get the ABI of a contract from a node.

    :param contract_address: The address of the contract to get the ABI for.
    :param node: The node to use.
    :return: The ABI of the contract.
    """
    contract_abi = ContractAbiResolver(
        address=contract_address, client=node, proxy_config=ProxyConfig()
    )
    (abi, _) = await contract_abi.get_abi_for_address()
    return abi


async def get_contract_from_address(
    contract_address: str, provider: FullNodeClient | Account
) -> Contract:
    """
    Get a contract instance from a contract address.

    :param contract_address: The address of the contract to get the instance for.
    :param account: The starknet.py account.
    :return: The contract instance.
    """
    return await Contract.from_address(address=contract_address, provider=provider)


async def _declare_contract(
    contract_name: str,
    contract_folder: str,
    package: str,
    account: Account,
    target: str = "release",
) -> DeclareResult | str:
    """
    Declare a contract using starknet.py and return the declare result, or class hash if already declared.

    :param contract_name: The name of the contract to declare.
    :param contract_folder: The folder containing the contract.
    :param package: The package name.
    :param account: The starknet.py account.
    :return: declare result, or class hash if already declared.
    """
    base_path = Path(contract_folder)
    contract_class_path = (
        base_path / "target" / target / f"{package}_{contract_name}.contract_class.json"
    )
    compiled_contract_class_path = (
        base_path
        / "target"
        / target
        / f"{package}_{contract_name}.compiled_contract_class.json"
    )

    # Verify that the contract files exist.
    if not contract_class_path.exists():
        raise FileNotFoundError(
            f"{package}_{contract_name}.contract_class.json file not found in {contract_folder}/target/{target}. Please run `scarb build` first."
        )
    if not compiled_contract_class_path.exists():
        raise FileNotFoundError(
            f"{package}_{contract_name}.compiled_contract_class.json file not found in {contract_folder}/target/{target}.\n"
            f"Make sure casm = true and casm-add-pythonic-hints = true in [[target.starknet-contract]] section of your Scarb.toml file and then run `scarb build`"
        )

    with open(contract_class_path, "r") as f:
        compiled_contract = f.read()
    with open(compiled_contract_class_path, "r") as f:
        compiled_contract_casm = f.read()

    try:
        declare_result = await Contract.declare_v3(
            account,
            compiled_contract=compiled_contract,
            compiled_contract_casm=compiled_contract_casm,
            auto_estimate=True,
        )
        await declare_result.wait_for_acceptance()
        await wait_for_tx_acceptance(declare_result.hash, account.client)
        return declare_result

    except Exception as e:
        if "is already declared" in str(e):
            match = re.search(r"0x[a-fA-F0-9]{64}", str(e))
            if match:
                class_hash = match.group(0)
                return class_hash
            else:
                raise Exception(f"Failed to extract the class hash. Error: {e}")
        else:
            raise Exception(f"Error declaring contract: {e}")


async def declare_contract(
    contract_name: str,
    contract_folder: str,
    package: str,
    account: Account,
    target: str = "release",
) -> str:
    """
    Declare a contract using starknet.py and return the class hash.

    :param contract_name: The name of the contract to declare.
    :param contract_folder: The folder containing the contract.
    :param package: The package name.
    :param account: The starknet.py account.
    :return: The class hash of the declared contract.
    """
    print_debug(f"Declaring contract: {contract_name}")

    declare_result = await _declare_contract(
        contract_name, contract_folder, package, account, target
    )
    if isinstance(declare_result, DeclareResult):
        class_hash = to_hex(declare_result.class_hash)
        print_debug(f"Declared class hash: {class_hash}")
    else:  # Class hash
        class_hash = declare_result
        print_debug(f"Class is already declared. Class hash: {class_hash}")
    return class_hash


async def deploy_contract(
    class_hash: str,
    account: Account,
    constructor_args: list | dict | None = None,
    contract_name: str | None = None,
    contract_folder: str | None = None,
    package: str | None = None,
    abi: list | None = None,
) -> Contract:
    """
    Deploy a contract using starknet.py and return the contract instance.

    :param class_hash: The class hash of the contract to deploy.
    :param account: The starknet.py account.
    :param constructor_args: The constructor arguments for the contract deployment.
    :param contract_name: The name of the contract to deploy.
    :param contract_folder: The folder containing the contract.
    :param package: The package name.
    :param abi: The ABI of the contract.
    :return: The contract instance.
    """
    if contract_name is None:
        print_debug(f"Deploying contract with class hash: {class_hash}")
    else:
        print_debug(f"Deploying contract: {contract_name}")

    if abi is None:
        if (
            contract_folder is None or package is None or contract_name is None
        ):  # i.e. assert both exist.
            raise ValueError(
                "contract_name, package and contract_folder are required when abi is not provided."
            )
        abi = get_contract_abi(contract_name, contract_folder, package)

    deploy_result = await Contract.deploy_contract_v3(
        account,
        class_hash=class_hash,
        constructor_args=constructor_args,
        abi=abi,
        auto_estimate=True,
    )
    await deploy_result.wait_for_acceptance()
    await wait_for_tx_acceptance(deploy_result.hash, account.client)
    contract = deploy_result.deployed_contract
    print_debug(f"Deployed contract: {to_hex(contract.address)}")

    return contract


async def declare_and_deploy_contract(
    contract_name: str,
    contract_folder: str,
    package: str,
    account: Account,
    constructor_args: list | dict | None = None,
) -> Contract:
    """
    Declare and deploy a contract using starknet.py and return the contract instance.

    :param contract_name: The name of the contract to declare and deploy.
    :param contract_folder: The folder containing the contract.
    :param package: The package name.
    :param account: The starknet.py account.
    :param constructor_args: The constructor arguments for the contract deployment.
    :return: The contract instance.
    """
    print_debug(f"Declaring and deploying contract: {contract_name}")

    declare_result = await _declare_contract(
        contract_name, contract_folder, package, account
    )
    if isinstance(declare_result, str):  # Class hash
        print_debug(f"Class is already declared. Class hash: {declare_result}")
        return await deploy_contract(
            declare_result,
            account,
            constructor_args,
            contract_name,
            contract_folder,
            package,
        )
    # Declare result
    deploy_result = await declare_result.deploy_v3(
        constructor_args=constructor_args,
        auto_estimate=True,
    )

    await deploy_result.wait_for_acceptance()
    await wait_for_tx_acceptance(deploy_result.hash, account.client)
    contract = deploy_result.deployed_contract
    print_debug(f"Declared and deployed contract: {to_hex(contract.address)}")

    return contract


async def invoke_function(
    contract: Contract, function_name: str, function_args: list | dict | None = None
):
    """
    Invoke a function on the given contract using starknet.py.

    :param contract: The contract instance to invoke the function on.
    :param function_name: The name of the function to invoke.
    :param function_args: The arguments for the function.
    """
    print_debug(f"Invoking function: {function_name}")
    match function_args:
        case dict():
            invocation = await contract.functions[function_name].invoke_v3(
                **function_args,
                auto_estimate=True,
            )
        case list():
            invocation = await contract.functions[function_name].invoke_v3(
                *function_args,
                auto_estimate=True,
            )
        case _:  # None
            invocation = await contract.functions[function_name].invoke_v3(
                auto_estimate=True,
            )
    await invocation.wait_for_acceptance()
    await wait_for_tx_acceptance(invocation.hash, contract.client)

    print_debug(f"Function {function_name} invoked.")


async def call_function(
    contract: Contract, function_name: str, function_args: list | dict | None = None
) -> any:
    """
    Call a function on the given contract using starknet.py.

    :param contract: The contract instance to call the function on.
    :param function_name: The name of the function to call.
    :param function_args: The arguments for the function.
    :return: The result of the function call.
    """
    print_debug(f"Calling function: {function_name}")
    match function_args:
        case dict():
            result = await contract.functions[function_name].call(**function_args)
        case list():
            result = await contract.functions[function_name].call(*function_args)
        case _:  # None
            result = await contract.functions[function_name].call()

    print_debug(f"Function {function_name} called. Result: {result}")
    return result


async def call_function_with_node(
    node: FullNodeClient,
    contract_address: str,
    function_name: str,
    calldata: list,
) -> list:
    """
    Call a function on the given contract using a node.

    :param node: The node to call the function on.
    :param contract_address: The address of the contract to call the function on.
    :param function_name: The name of the function to call.
    :param calldata: The calldata for the function.
    :return: List of integers representing contract’s function output (structured like calldata).
    """
    result = await node.call_contract(
        call=Call(
            to_addr=contract_address,
            selector=get_selector_from_name(function_name),
            calldata=calldata,
        ),
        block_number="latest",
    )
    print_debug(f"Function {function_name} called. Result: {result}")
    return result


async def try_call_function(
    contract: Contract, function_name: str, function_args: list | dict | None = None
) -> tuple[bool, any]:
    """
    Try to call a function on the given contract using starknet.py.

    :param contract: The contract instance to call the function on.
    :param function_name: The name of the function to call.
    :param function_args: The arguments for the function.
    :return: A tuple containing a boolean indicating success and the result of the function call or exception.
    """
    try:
        result = await call_function(contract, function_name, function_args)
        return True, result
    except Exception as e:
        print_debug(f"Error calling function: {function_name}. Error: {e}")
        return False, e


def prepare_invoke_function(
    contract: Contract, function_name: str, function_args: dict | list | None = None
) -> PreparedFunctionInvokeV3:
    """
    Prepare an invoke function call.

    :param contract: The contract instance to invoke the function on.
    :param function_name: The name of the function to invoke.
    :param function_args: The arguments for the function.
    :return: The invocation object.
    """
    match function_args:
        case dict():
            invocation = contract.functions[function_name].prepare_invoke_v3(
                **function_args
            )
        case list():
            invocation = contract.functions[function_name].prepare_invoke_v3(
                *function_args
            )
        case _:  # None
            invocation = contract.functions[function_name].prepare_invoke_v3()
    return invocation


def _convert_prepared_invoke_to_json(
    prepared_invoke: PreparedFunctionInvokeV3, function_name: str
) -> dict:
    """
    Convert a prepared invoke to a dictionary.

    :param prepared_invoke: The prepared invoke to convert.
    :param function_name: The entrypoint.
    :return: The json dictionary.
    """
    return {
        "contractAddress": to_hex(prepared_invoke.to_addr),
        "entrypoint": function_name,
        "calldata": [normalize_value(arg) for arg in prepared_invoke.calldata],
    }


# Note: This is used for argent multisig: https://universal-transaction-executor.vercel.app/.
def prepare_invoke_function_json(
    contract: Contract, function_name: str, function_args: dict | list | None = None
) -> dict:
    """
    Prepare an invoke function call and return the prepared tx as a dictionary.

    :param contract: The contract instance to invoke the function on.
    :param function_name: The name of the function to invoke.
    :param function_args: The arguments for the function.
    :return: Dictionary with the prepared tx.
    """
    tx = prepare_invoke_function(contract, function_name, function_args)
    return _convert_prepared_invoke_to_json(tx, function_name)


def convert_prepared_invoke_list_to_calldata(
    prepared_invoke_list: list[PreparedFunctionInvokeV3],
) -> list:
    """
    Convert a prepared invoke list to calldata.

    :param prepared_invoke_list: The prepared invoke list to convert.
    :return: The calldata.
    """
    calldata = [len(prepared_invoke_list)]
    for prepared_invoke in prepared_invoke_list:
        calldata.extend(
            [
                prepared_invoke.to_addr,
                prepared_invoke.selector,
                len(prepared_invoke.calldata),
            ]
        )
        calldata.extend(prepared_invoke.calldata)
    return calldata


async def execute_multicall(calls: list, account: Account):
    """
    Execute a multicall using starknet.py.

    :param calls: The list of calls to execute.
    :param account: The account to execute the multicall from.
    """
    print_debug(f"Executing multicall.")
    transaction_response = await account.execute_v3(
        calls=calls,
        auto_estimate=True,
    )
    print_debug(f"Transaction hash: {to_hex(transaction_response.transaction_hash)}")
    await account.client.wait_for_tx(transaction_response.transaction_hash)
    await wait_for_tx_acceptance(transaction_response.transaction_hash, account.client)

    print_debug(f"Multicall executed.")


# async def get_transaction_hash(
#     calls: list, account: Account, chain: StarknetChainId
# ) -> str:
#     """
#     Get the transaction hash of a transaction.

#     :param calls: The list of calls of the transaction.
#     :param account: The account to execute the transaction from.
#     :param chain: The chain to use.
#     :return: The transaction hash.
#     """
#     prepared_tx = await account._prepare_invoke_v3(calls=calls, auto_estimate=True)
#     tx_hash = prepared_tx.calculate_hash(chain)
#     return to_hex(tx_hash)


async def fetch_events(
    contract_address: str,
    event_name: str,
    node: FullNodeClient,
    from_block: int = 0,
    to_block: int | str = "latest",
    chunk_size: int = FETCH_EVENTS_CHUNK_SIZE,
) -> list:
    """
    Fetch all events from the given contract address and event name.

    :param contract_address: The address of the contract to fetch events from.
    :param event_name: The name of the event to fetch.
    :param node: The node to fetch events from.
    :param from_block: The block number to start fetching events from.
    :param to_block: The block number to stop fetching events at.
    :param chunk_size: Maximum blocks to fetch events from in one request.
    :return: The events.
    """
    print_debug(f"Fetching events: {event_name}.")
    # Convert to block to a block number.
    if isinstance(to_block, str):
        if to_block != "latest":
            raise ValueError("Invalid to_block value. Must be an integer or 'latest'.")
        to_block = await node.get_block_number()
        print_debug(f"Latest block: {to_block}")
    events = []
    for chunk_start in range(from_block, to_block + 1, chunk_size):
        chunk_end = min(chunk_start + chunk_size - 1, to_block)
        resp = await node.get_events(
            address=contract_address,
            keys=[[hex(get_selector_from_name(event_name))]],
            from_block_number=chunk_start,
            to_block_number=chunk_end,
            follow_continuation_token=True,
        )
        print_debug(
            f"Fetched {len(resp.events)} events from {chunk_start} to {chunk_end}."
        )
        events.extend(resp.events)
    print_debug("Fetched all events.")
    print_debug(f"Fetched {len(events)} events from {from_block} to {to_block}.")
    return events


async def fetch_last_event(
    contract_address: str,
    event_name: str,
    node: FullNodeClient,
    from_block: int = 0,
    to_block: int | str = "latest",
    chunk_size: int = FETCH_EVENTS_CHUNK_SIZE,
):
    """
    Fetch the last event of a given event name from a given contract address.

    :param contract_address: The address of the contract to fetch events from.
    :param event_name: The name of the event to fetch.
    :param node: The node to fetch events from.
    :param from_block: The block number to start fetching events from.
    :param to_block: The block number to stop fetching events at.
    :param chunk_size: Maximum blocks to fetch events from in one request.
    :return: The last event.
    """
    print_debug(f"Fetching last event of {event_name}.")
    # Convert to block to a block number.
    if isinstance(to_block, str):
        if to_block != "latest":
            raise ValueError("Invalid to_block value. Must be an integer or 'latest'.")
        to_block = await node.get_block_number()
        print_debug(f"Latest block: {to_block}")
    for chunk_end in range(to_block, from_block + chunk_size, -chunk_size):
        chunk_start = max(chunk_end - chunk_size, from_block)
        resp = await node.get_events(
            address=contract_address,
            keys=[[hex(get_selector_from_name(event_name))]],
            from_block_number=chunk_start,
            to_block_number=chunk_end,
            follow_continuation_token=True,
        )
        print_debug(
            f"Fetched {len(resp.events)} events from {chunk_start} to {chunk_end}."
        )
        if len(resp.events) > 0:
            return resp.events[-1]
    return None


def prepare_upgrade_calls(
    contract: Contract, implementation_data: ImplementationData
) -> list:
    """
    Prepare the calls for the upgrade.

    :param contract: The contract instance to upgrade.
    :param implementation_data: The implementation data for the upgrade.
    :return: A list with the calls.
    """
    upgrade_args = [asdict(implementation_data)]
    calls = []
    for function_name in UPGRADE_FUNCTIONS:
        calls.append(prepare_invoke_function(contract, function_name, upgrade_args))
    return calls


# Note: This is used for argent multisig: https://universal-transaction-executor.vercel.app/.
def prepare_upgrade_calls_json(
    contract: Contract, implementation_data: ImplementationData
) -> list[dict]:
    """
    Prepare the calls for the upgrade and return the prepared tx as a list of dictionaries.

    :param contract: The contract instance to upgrade.
    :param implementation_data: The implementation data for the upgrade.
    :return: A list with the calls as dictionaries.
    """
    upgrade_args = [asdict(implementation_data)]
    calls = []
    for function_name in UPGRADE_FUNCTIONS:
        calls.append(
            _convert_prepared_invoke_to_json(
                prepare_invoke_function(contract, function_name, upgrade_args),
                function_name,
            )
        )
    return calls


async def upgrade_contract(contract: Contract, implementation_data: ImplementationData):
    """
    Upgrade a contract using starknet.py.

    :param contract: The contract instance to upgrade.
    :param implementation_data: The implementation data for the upgrade.
    """
    print_debug(f"Upgrading contract: {to_hex(contract.address)}")
    calls = prepare_upgrade_calls(contract, implementation_data)
    await execute_multicall(calls, contract.account)
    print_debug(f"Contract {to_hex(contract.address)} upgraded.")


async def get_class_hash_at(contract_address: str, node: FullNodeClient) -> str:
    """
    Get the class hash of a contract at a given address.

    :param contract_address: The address of the contract to get the class hash for.
    :param node: The node to get the class hash from.
    :return: The class hash of the contract.
    """
    return to_hex(await node.get_class_hash_at(contract_address))


async def get_nonce(address: str, node: FullNodeClient) -> int:
    """
    Get the nonce of an account.

    :param address: The address of the account to get the nonce for.
    :param node: The node to get the nonce from.
    :return: The nonce of the account.
    """
    return await node.get_contract_nonce(address)


async def generate_invoke_tx(
    calldata: list,
    sender_address: str,
    node: FullNodeClient,
    nonce: int | None = None,
    version: int = 3,
    account_deployment_data: list | None = None,
) -> InvokeV3:
    """
    Generate an invoke transaction. Set the resource bounds to 0.

    :param calldata: The calldata for the transaction.
    :param sender_address: The address of the sender.
    :param node: A node to get the nonce from.
    :param nonce: The nonce for the transaction.
    :param version: The version of the transaction.
    :param account_deployment_data: The account deployment data for the transaction.
    :return: An invoke transaction.
    """
    if nonce is None:
        nonce = await get_nonce(sender_address, node)
    if account_deployment_data is None:
        account_deployment_data = []
    zero_resource_bounds = ResourceBoundsMapping(
        l1_gas=ResourceBounds(max_amount=0, max_price_per_unit=0),
        l2_gas=ResourceBounds(max_amount=0, max_price_per_unit=0),
        l1_data_gas=ResourceBounds(max_amount=0, max_price_per_unit=0),
    )
    tx = InvokeV3(
        calldata=calldata,
        nonce=nonce,
        resource_bounds=zero_resource_bounds,
        signature=[],
        sender_address=to_int(hexstr=sender_address),
        version=version,
        account_deployment_data=account_deployment_data,
    )
    return tx


async def estimate_fee(tx: InvokeV3, node: FullNodeClient) -> ResourceBoundsMapping:
    """
    Estimate the fee for an invoke transaction and return the needed resource bounds.

    :param tx: The invoke transaction to estimate the fee for.
    :param node: The node to use.
    :return: The needed resource bounds(estimated * UNIVERSAL_GAS_MODEFIER).
    """
    fee = await node.estimate_fee(tx, skip_validate=True)
    return ResourceBoundsMapping(
        l1_gas=ResourceBounds(
            max_amount=fee.l1_gas_consumed * UNIVERSAL_GAS_MODEFIER,
            max_price_per_unit=fee.l1_gas_price * UNIVERSAL_GAS_MODEFIER,
        ),
        l1_data_gas=ResourceBounds(
            max_amount=fee.l1_data_gas_consumed * UNIVERSAL_GAS_MODEFIER,
            max_price_per_unit=fee.l1_data_gas_price * UNIVERSAL_GAS_MODEFIER,
        ),
        l2_gas=ResourceBounds(
            max_amount=fee.l2_gas_consumed * UNIVERSAL_GAS_MODEFIER,
            max_price_per_unit=fee.l2_gas_price * UNIVERSAL_GAS_MODEFIER,
        ),
    )


async def generate_invoke_tx_with_fee(
    calldata: list,
    sender_address: str,
    node: FullNodeClient,
    nonce: int | None = None,
    version: int = 3,
    account_deployment_data: list | None = None,
) -> InvokeV3:
    """
    Generate an invoke transaction with estimated fee.

    :param calldata: The calldata for the transaction.
    :param sender_address: The address of the sender.
    :param node: A node to use.
    :param nonce: The nonce for the transaction.
    :param version: The version of the transaction.
    :param account_deployment_data: The account deployment data for the transaction.
    :return: An invoke transaction with estimated fee.
    """
    tx = await generate_invoke_tx(
        calldata,
        sender_address,
        node,
        nonce=nonce,
        version=version,
        account_deployment_data=account_deployment_data,
    )
    resource_bounds = await estimate_fee(tx, node)
    tx = replace(tx, resource_bounds=resource_bounds)
    return tx


def _extract_signature_from_string(signature: str) -> list[int]:
    """
    Extracts signature (r, s) from a string.

    :param signature: The full signature.
    :return: The signature as a list of [r, s].
    """
    sig_r = int(signature[:66], 0)
    sig_s = int("0x" + signature[66:], 0)
    return [sig_r, sig_s]


def add_signature_to_tx(
    tx: InvokeV3, signature: str, chain_id: StarknetChainId, public_key: str
) -> InvokeV3:
    """
    Add a signature to an invoke transaction.

    :param tx: The invoke transaction.
    :param signature: The full signature.
    :param chain_id: The chain id.
    :param public_key: The public key of the signer.
    :return: The invoke transaction with the signature added.
    """
    sign = _extract_signature_from_string(signature)
    tx_hash = calculate_tx_hash(tx, chain_id)
    if not verify_message_signature(
        to_int(hexstr=tx_hash), sign, to_int(hexstr=public_key)
    ):
        raise ValueError(
            "Invalid signature. Tx hash: {tx_hash}, signature: {sign}, public key: {public_key}"
        )
    tx = replace(tx, signature=sign)
    return tx


def calculate_tx_hash(tx: InvokeV3, chain_id: StarknetChainId) -> str:
    """
    Compute the hash of an invoke transaction.

    :param tx: The invoke transaction.
    :param chain_id: The chain id.
    :return: The hash of the invoke transaction.
    """
    return to_hex(tx.calculate_hash(chain_id))


def invoke_v3_to_json(tx: InvokeV3) -> dict:
    """
    Convert an invoke transaction to a dictionary.

    :param tx: The invoke transaction.
    :return: The dictionary.
    """
    return {
        TX_CALLDATA: tx.calldata,
        TX_NONCE: tx.nonce,
        TX_SENDER_ADDRESS: to_hex(tx.sender_address),
        TX_VERSION: tx.version,
        TX_ACCOUNT_DEPLOYMENT_DATA: tx.account_deployment_data,
        TX_RESOURCE_BOUNDS: asdict(tx.resource_bounds),
        TX_SIGNATURE: tx.signature,
    }


def json_to_invoke_v3(json: dict) -> InvokeV3:
    """
    Convert a dictionary to an invoke transaction.

    :param json: The dictionary.
    :return: The invoke transaction.
    """
    return InvokeV3(
        calldata=json[TX_CALLDATA],
        nonce=json[TX_NONCE],
        resource_bounds=_dict_to_resource_bounds(json[TX_RESOURCE_BOUNDS]),
        signature=json[TX_SIGNATURE],
        sender_address=to_int(hexstr=json[TX_SENDER_ADDRESS]),
        version=json[TX_VERSION],
        account_deployment_data=json[TX_ACCOUNT_DEPLOYMENT_DATA],
    )


def _dict_to_resource_bounds(resource_bounds: dict) -> ResourceBoundsMapping:
    """
    Convert a dictionary to a resource bounds mapping.

    :param resource_bounds: The dictionary.
    :return: The resource bounds mapping.
    """
    return ResourceBoundsMapping(
        l1_gas=ResourceBounds(
            max_amount=resource_bounds["l1_gas"]["max_amount"],
            max_price_per_unit=resource_bounds["l1_gas"]["max_price_per_unit"],
        ),
        l2_gas=ResourceBounds(
            max_amount=resource_bounds["l2_gas"]["max_amount"],
            max_price_per_unit=resource_bounds["l2_gas"]["max_price_per_unit"],
        ),
        l1_data_gas=ResourceBounds(
            max_amount=resource_bounds["l1_data_gas"]["max_amount"],
            max_price_per_unit=resource_bounds["l1_data_gas"]["max_price_per_unit"],
        ),
    )


async def send_invoke_transaction(tx: InvokeV3, node: FullNodeClient):
    """
    Send a invoke transaction.

    :param tx: The invoke transaction.
    :param node: The node to use.
    """
    print_debug(f"Sending invoke transaction.")
    response = await node.send_transaction(tx)
    print_debug(f"Transaction hash: {to_hex(response.transaction_hash)}")
    wait_for_acceptance = input("Wait for acceptance? (y/n): ")
    if wait_for_acceptance == "y":
        print_debug(f"Waiting for transaction acceptance...")
        await wait_for_tx_acceptance(response.transaction_hash, node)
    print_debug(f"Invoke transaction sent.")
