#!/usr/bin/env bash
set -euo pipefail
: "${AUTORESEARCH_FIXTURES:?Set to named base and edited bitstream paths}"
mise exec -- cargo build --release --example swift_patch_search >/dev/null
./target/release/examples/swift_patch_search
