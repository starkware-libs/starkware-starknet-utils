# Primer (crate `contracts`) — isolated, hash-pinned package

`Primer` is a trivial contract whose **only** purpose is to have a well-known, cemented on-chain
class hash:

```
0x00123e6bc1c14ae9934e933d3f64916a6116dd6b036a922b2b1f0815e0d1d300
```

`starkware_account_factory` deploys a `Primer` at a deterministic address (computed from this exact
class hash) and immediately upgrades it via `set_class_hash` into the real account. Because the
deterministic address depends on the class hash, **the hash must not change** — already-deployed
accounts depend on it.

## Why this package is special

- **Not a member of the root sn-utils workspace.** The root runs scarb 2.15.1; this package must
  build with **scarb 2.14.0** to reproduce the cemented hash. Isolation is achieved with the
  member-less `[workspace]` stanza in `Scarb.toml` (so the root `scarb build -w` ignores it) plus a
  local `.tool-versions` pinning scarb 2.14.0 / starknet-foundry 0.54.1.
- **Crate name is `contracts`, not `starkware_*`.** The name and module path
  `contracts::primer::primer::Primer` are baked into the hashed Sierra by `sierra-replace-ids`;
  renaming would change the hash. This is an intentional exception to the repo's `starkware_*`
  naming convention.

## Reproduce / verify the hash

```bash
cd packages/primer
./scripts/verify_primer_class_hash.sh   # uses scarb 2.14.0 via .tool-versions; expects 0x00123e6b…
```

CI runs this on every PR touching `packages/primer/**` (`.github/workflows/verify-primer-class-hash.yml`).

## Do NOT change

The crate name, module paths, `starknet`/`edition` pins, and the `[profile.release.cairo]
sierra-replace-ids` setting are all hash-critical. Any change must be re-verified against the
expected hash above. `Primer`'s behavioral tests live in `starkware_accounts` (against a 2.15.1
`PrimerTestMock`), since this island has no test toolchain.
