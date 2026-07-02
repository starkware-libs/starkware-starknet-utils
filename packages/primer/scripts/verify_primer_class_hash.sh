#!/bin/bash
# Reproduces and verifies the cemented on-chain class hash of the `Primer` contract.
# Must run from packages/primer/ (this isolated package's own workspace), where .tool-versions
# pins scarb 2.14.0. See Scarb.toml header for why this is isolated from the root workspace.
set -euo pipefail

cd "$(dirname "$0")/.."

EXPECTED_CLASS_HASH="0x00123e6bc1c14ae9934e933d3f64916a6116dd6b036a922b2b1f0815e0d1d300"
REQUIRED_SCARB_VERSION="2.14.0"

# 1) Hard-fail (not warn) on scarb version mismatch — the hash is toolchain-locked.
CURRENT_SCARB_VERSION=$(scarb --version | grep -oP 'scarb \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
echo "Scarb version: $CURRENT_SCARB_VERSION (required: $REQUIRED_SCARB_VERSION)"
if [ "$CURRENT_SCARB_VERSION" != "$REQUIRED_SCARB_VERSION" ]; then
    echo "ERROR: Scarb version mismatch — class hash will not be reproducible."
    echo "Run from packages/primer/ so .tool-versions selects scarb $REQUIRED_SCARB_VERSION."
    exit 1
fi

# 2) Guard against .tool-versions drift.
TV_SCARB=$(grep -oP '^scarb \K[0-9]+\.[0-9]+\.[0-9]+' .tool-versions || echo "missing")
if [ "$TV_SCARB" != "$REQUIRED_SCARB_VERSION" ]; then
    echo "ERROR: .tool-versions scarb ($TV_SCARB) != REQUIRED_SCARB_VERSION ($REQUIRED_SCARB_VERSION)."
    exit 1
fi

# 3) Build (release → sierra-replace-ids) and compute the class hash.
echo "Building with release profile..."
SCARB_PROFILE=release scarb build

echo "Computing Primer class hash..."
SNCAST_OUTPUT=$(sncast utils class-hash --package contracts --contract-name Primer 2>&1)
ACTUAL_CLASS_HASH=$(echo "$SNCAST_OUTPUT" | grep "Class Hash:" | awk '{print $3}')

echo "Expected: $EXPECTED_CLASS_HASH"
echo "Actual:   $ACTUAL_CLASS_HASH"
if [ "$ACTUAL_CLASS_HASH" = "$EXPECTED_CLASS_HASH" ]; then
    echo "SUCCESS: Primer class hash matches expected value"
    exit 0
else
    echo "FAILURE: Primer class hash mismatch!"
    exit 1
fi
