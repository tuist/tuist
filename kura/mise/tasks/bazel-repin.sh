#!/usr/bin/env bash
#MISE description="Repin Cargo.Bazel.lock (crate_universe) after Rust deps change; `bazel-repin check` verifies only"
#USAGE arg "[mode]" help="'check' verifies the pin is current without rewriting it; omit to repin" {
#USAGE   choices "check"
#USAGE }
set -euo pipefail

# Cargo.Bazel.lock pins Bazel's resolved Rust crate graph (crate_universe) and is a digest of
# Cargo.toml + Cargo.lock. It must be regenerated whenever those change — including after merging
# main — or every Bazel job fails at analysis with "lockfile is out of date for 'crates'".
#
# Both modes run on the host with no Docker: the repin/check is a crate_universe module-extension
# step, evaluated before any target analysis or cc-toolchain resolution. Both the `@crates//:all`
# query and the //bazel/third_party/lua:lua resolution below are loading-phase (`bazel query`, not
# cquery), so they materialize repos but resolve no cc toolchain.
#
# No `cd` needed: mise runs file tasks from the config root (kura/) regardless of the invocation
# directory, so the relative paths below (Cargo.Bazel.lock) and the bazel workspace resolve here.

if [ "${usage_mode:-}" = "check" ]; then
  # No CARGO_BAZEL_REPIN: a stale pin fails loudly here instead of being silently re-resolved.
  if err="$(bazel query '@crates//:all' 2>&1 >/dev/null)"; then
    echo "Cargo.Bazel.lock is up to date."
  else
    if printf '%s' "$err" | grep -qiE "do not match|out of date for 'crates'"; then
      echo "Cargo.Bazel.lock is out of date — run 'mise run bazel-repin' (in kura/) and commit it." >&2
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

# Guard the vendored-Lua wiring too. bazel/third_party/lua pins lua-src by its versioned canonical
# repo name (@@rules_rust++crate+crates__lua-src-<version>) and MODULE.bazel globs lua-5.4.*; a
# lua-src bump can break both. The `@crates//:all` check above does not catch it (it only
# materializes @crates), so the break would otherwise surface ~60 min into bazel-compile. Resolving
# the target here makes a stale label fail in this ~1-min guard instead.
if lua_err="$(bazel query 'deps(//bazel/third_party/lua:lua)' 2>&1 >/dev/null)"; then
  echo "Vendored-Lua wiring resolves."
else
  echo "//bazel/third_party/lua:lua no longer resolves — most likely a lua-src version bump." >&2
  echo "Update the canonical label in bazel/third_party/lua/BUILD.bazel and the lua-5.4.* glob in MODULE.bazel to the new lua-src version." >&2
  printf '%s\n' "$lua_err" >&2
  exit 1
fi
