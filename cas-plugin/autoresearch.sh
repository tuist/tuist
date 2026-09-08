#!/usr/bin/env bash
set -euo pipefail
: "${AUTORESEARCH_FIXTURES:?Set to a manifest of named base/edited compiler output paths}"
mise exec -- cargo build --release --example chunking_search >/dev/null
./target/release/examples/chunking_search
