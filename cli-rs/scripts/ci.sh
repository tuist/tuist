#!/usr/bin/env bash
# Everything the cli-rs CI job checks, runnable locally from the repository root.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$REPO_ROOT"
SWIFT_FLAGS=(--replace-scm-with-registry --force-resolved-versions)

swift build "${SWIFT_FLAGS[@]}" --product TuistEmbed
swift build "${SWIFT_FLAGS[@]}" --product tuist
cli-rs/scripts/install-project-description.sh debug

cli-rs/scripts/update-spec.sh .build/debug/tuist --check

(
    cd cli-rs
    cargo fmt -- --check
    cargo clippy --all-targets -- -D warnings
    cargo test
)

cli-rs/scripts/dev-install.sh debug
cli-rs/scripts/parity.sh .build/debug

PROJECT=$(mktemp -d)
trap 'rm -rf "$PROJECT"' EXIT
cp -R examples/xcode/generated_app_with_framework_and_tests/. "$PROJECT/"
python3 cli-rs/scripts/mcp_smoke.py "$REPO_ROOT/.build/debug/tuist-rs" "$PROJECT"
