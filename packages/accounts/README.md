# Starkware Accounts

Deployable account contracts.

- **`StarknetEth712Account`** — a Starknet account that authenticates with an Ethereum
  (secp256k1) key, validating EIP-712 typed-data signatures. Implements SRC6
  (`__validate__` / `__execute__`), SRC9 v2 (execute-from-outside), and a self-upgrade entrypoint.
- **`AccountFactory`** — deploys an account for a given Ethereum address at a deterministic
  Starknet address. On first use it deploys a `Primer` at that address and upgrades it to the
  configured account class.
- **`ShadowAccount`** — a minimal contract whose owner (the deployer) can batch-execute arbitrary
  `Call`s through it, exactly as an account would. Only the owner may call `execute`.

## Deterministic addresses

The account address is derived from the Ethereum address (used as the deploy salt) and a fixed
`Primer` class hash (`0x00123e6b…`, see `packages/primer`). `get_expected_account_address` returns
it whether or not the account is deployed; `get_account` returns it only once deployed. Because the
address depends on the `Primer` class hash, that hash is fixed — changing it changes every account
address.
