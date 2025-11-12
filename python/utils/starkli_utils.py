import subprocess

# from pathlib import Path


def get_starkli_private_key(keystore_file: str, keystore_password: str):
    """
    Get the private key from the starkli keystore.

    :param keystore_file: The path to the keystore file.
    :param keystore_password: The password for the keystore file.
    :return: The private key.
    """
    # Verify keystore file.
    # path = Path(keystore_file)
    # if not path.exists():
    #     raise FileNotFoundError(f"Keystore file {keystore_file} not found.")
    # if not path.is_file():
    #     raise FileNotFoundError(f"Keystore file {keystore_file} is not a file.")

    # Get private key.
    password_format = "--password={}"
    command = [
        "starkli",
        "signer",
        "keystore",
        "inspect-private",
        keystore_file,
        password_format.format(keystore_password),
    ]

    try:
        result = subprocess.run(command, capture_output=True, text=True)

        if result.returncode == 0:
            return result.stdout.split()[2]
        else:
            raise Exception(
                f"Private key extraction failed with error: {result.stderr}"
            )
    except Exception as e:
        raise Exception(f"An error occurred while getting private key: {e}")


def ledger_sign_tx(tx_hash: str, ledger_path: str) -> str:
    """
    Sign a transaction with the ledger account.

    :param tx_hash: The hash of the transaction to sign.
    :param ledger_path: The derivation_path of the ledger.
    :return: The signature of the transaction.
    """
    command = [
        "starkli",
        "ledger",
        "sign-hash",
        "--path",
        ledger_path,
        tx_hash,
    ]
    try:
        input(
            "Open ledger and press enter to continue, then sign the tx in your legder."
        )
        result = subprocess.run(command, capture_output=True, text=True)

        if result.returncode == 0:
            print(f"Signing successful: {result.stdout.strip()}")
            return result.stdout.strip()
        else:
            print(f"Signing failed with error: {result.stderr}")
    except Exception as e:
        print(f"An error occurred while signing transaction: {e}")


def get_ledger_public_key(ledger_path: str) -> str:
    """
    Get the public key from the ledger account.

    :param ledger_path: The derivation_path of the ledger.
    :return: The public key of the ledger account.
    """
    command = [
        "starkli",
        "ledger",
        "get-public-key",
        "--no-display",
        ledger_path,
    ]
    try:
        input("Getting public key. Open ledger and press enter to continue.")
        result = subprocess.run(command, capture_output=True, text=True)

        if result.returncode == 0:
            print(f"Public key: {result.stdout.strip()}")
            return result.stdout.strip()
        else:
            print(f"Getting public key failed with error: {result.stderr}")
    except Exception as e:
        print(f"An error occurred while getting public key: {e}")
