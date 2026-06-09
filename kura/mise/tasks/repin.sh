#!/usr/bin/env bash
#MISE description="Repin Cargo.Bazel.lock (crate_universe) after Rust deps change; `repin check` verifies only"
#USAGE arg "[mode]" help="'check' verifies the pin is current without rewriting it; omit to repin" {
#USAGE   choices "check"
#USAGE }
set -euo pipefail

# Cargo.Bazel.lock pins Bazel's resolved Rust crate graph (crate_universe) and is a digest of
# Cargo.toml + Cargo.lock. It must be regenerated whenever those change — including after merging
# main — or every Bazel job fails at analysis with "lockfile is out of date for 'crates'".
#
# Both modes run on the host with no Docker: the repin/check is a crate_universe module-extension
# step, evaluated before any target analysis or cc-toolchain resolution, so `bazel query
# '@crates//:all'` (which only materializes the @crates repo) needs no cross-GCC toolchain.
cd "${MISE_PROJECT_ROOT}"

if [ "${usage_mode:-}" = "check" ]; then
  # No CARGO_BAZEL_REPIN: a stale pin fails loudly here instead of being silently re-resolved.
  if err="$(bazel query '@crates//:all' 2>&1 >/dev/null)"; then
    echo "Cargo.Bazel.lock is up to date."
  else
    if printf '%s' "$err" | grep -qiE "do not match|out of date for 'crates'"; then
      echo "Cargo.Bazel.lock is out of date — run 'mise run repin' (in kura/) and commit it." >&2
    else
      printf '%s\n' "$err" >&2
    fi
    exit 1
  fi
else
  # Snapshot the lock so we can report whether the repin actually changed it (an unconditional
  # "repinned — commit it" is misleading when the pin was already current).
  lock="Cargo.Bazel.lock"
  before="$(mktemp)"
  trap 'rm -f "$before"' EXIT
  [ -f "$lock" ] && cp "$lock" "$before"

  CARGO_BAZEL_REPIN=1 bazel query '@crates//:all' >/dev/null

  if cmp -s "$before" "$lock"; then
    echo "Cargo.Bazel.lock already up to date — nothing to commit."
  else
    echo "✔ Cargo.Bazel.lock updated — commit it."
  fi
fi
