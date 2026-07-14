#!/usr/bin/env bash
#MISE description="Format Rust sources with rustfmt. Fixes files in place via cargo fmt by default; pass --check to verify only via the rules_rust rustfmt aspect (what CI runs)."
#USAGE flag "--check" help="Verify formatting only (rustfmt aspect) instead of fixing files in place"
set -euo pipefail

# Check and fix use different tools by necessity: the rustfmt aspect is a sandboxed Bazel action that
# can only verify — it can't write back to the source tree — so fixing falls back to cargo fmt.
# (env -u RUSTUP_TOOLCHAIN keeps cargo on the rust-toolchain.toml channel, matching the repo's other
# cargo invocations.)
if [ "${usage_check:-false}" = "true" ]; then
  exec bazel build //... \
    --aspects=@rules_rust//rust:defs.bzl%rustfmt_aspect \
    --output_groups=rustfmt_checks
fi

exec env -u RUSTUP_TOOLCHAIN cargo fmt
