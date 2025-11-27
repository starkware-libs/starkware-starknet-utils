from ..config import CHUNK_SIZE
from eth_utils import to_hex
import json

DEBUG = False


def set_debug(debug: bool):
    """
    Set the debug flag.

    :param debug: The debug flag.
    """
    global DEBUG
    DEBUG = debug


def print_debug(message: str):
    """
    Print a debug message if the debug flag is set.

    :param message: The message to print.
    """
    if DEBUG:
        print(message)


def split_chunks(arr: list, chunk_size: int = CHUNK_SIZE) -> list:
    """
    Split an array into chunks of a given size.

    :param arr: The array to split.
    :param chunk_size: The size of the chunks.
    :return: A list of chunks.
    """
    return [arr[i : i + chunk_size] for i in range(0, len(arr), chunk_size)]


def normalize_value(val: int) -> int | str:
    """
    Normalize the value to a hex string if it is an address.

    :param val: The value to normalize.
    :return: The normalized value.
    """
    MIN_ADDRESS_VALUE = 10000000000000000000000000000000000
    return to_hex(val) if val > MIN_ADDRESS_VALUE else val


def store_json(path: str, data: list | dict):
    """
    Store the data in a json file.

    :param path: The path to store the data.
    :param data: The data to store.
    """
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def load_json(path: str) -> list | dict:
    """
    Load the data from a json file.

    :param path: The path to load the data.
    :return: The data.
    """
    with open(path, "r") as f:
        return json.load(f)
