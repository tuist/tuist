#!/usr/bin/env bash
#MISE description="Fail if any source file defines an inline `#[cfg(test)] mod tests { ... }` block. Unit tests must live in a sibling tests.rs declared with `#[cfg(test)] mod tests;` (see AGENTS.md)."
set -euo pipefail

# Keeps modules reviewable: implementation and its tests stay in separate files. The check is a
# plain source scan (no toolchain needed), so it runs in the cheap CI format job and locally the
# same way. It flags the two-line form rustfmt emits (`#[cfg(test)]` then `mod tests {`) as well as
# a single-line `#[cfg(test)] mod tests {`.
violations=$(
  find src -name '*.rs' -print0 | xargs -0 awk '
    function trimmed(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    trimmed($0) ~ /^#\[cfg\(test\)\][[:space:]]*mod tests[[:space:]]*\{/ { print FILENAME ":" FNR; next }
    prev ~ /^#\[cfg\(test\)\]$/ && trimmed($0) ~ /^(pub(\([^)]*\))?[[:space:]]+)?mod tests[[:space:]]*\{/ {
      print FILENAME ":" (FNR - 1)
    }
    { prev = trimmed($0) }
  '
)

if [ -n "$violations" ]; then
  {
    echo "error: inline test modules are not allowed; move each to a sibling tests.rs"
    echo "       declared with '#[cfg(test)] mod tests;' (see kura/AGENTS.md). Offending files:"
    echo "$violations" | sed 's/^/  - /'
  } >&2
  exit 1
fi

echo "No inline test modules found."
