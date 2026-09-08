#!/usr/bin/env bash
set -euo pipefail
: "${AUTORESEARCH_FIXTURES:?Set to named base and edited bitstream paths}"
mise exec -- cargo build --release --example swift_receiver_search >/dev/null
AUTORESEARCH_RECEIVER_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tuist-receiver.XXXXXX")
export AUTORESEARCH_RECEIVER_DIR
echo "Receiver artifacts: $AUTORESEARCH_RECEIVER_DIR"
./target/release/examples/swift_receiver_search
