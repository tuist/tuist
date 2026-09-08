#!/usr/bin/env bash
set -euo pipefail
mise exec -- cargo test --example chunking_search --example swift_patch_search --example swift_receiver_search --test content_defined_chunking
