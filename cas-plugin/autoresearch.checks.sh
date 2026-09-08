#!/usr/bin/env bash
set -euo pipefail
mise exec -- cargo test --example chunking_search --test content_defined_chunking >/dev/null
