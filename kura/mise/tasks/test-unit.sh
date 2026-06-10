#!/usr/bin/env bash
#MISE description="Run the Rust unit tests with a raised file-descriptor limit (RocksDB-backed tests open many fds in parallel)"
set -euo pipefail

ulimit -n 65536
cargo test
