#!/usr/bin/env bash
#
# skip-write-benchmark.sh — measures the build-time impact of the pbxproj skip-write change.
#
# Hypothesis under test (Irena's doc): a no-op `tuist generate` rewrites project.pbxproj and
# bumps its mtime, which invalidates Xcode's warm incremental build and forces a broad recompile.
# The skip-write guard leaves an unchanged pbxproj untouched, so the incremental build stays warm.
#
# This script runs the controlled loop:
#   generate -> full (warm) build -> NO-OP generate -> incremental build
# and reports, for a given tuist binary:
#   * whether the no-op generate changed any project.pbxproj mtime
#   * how many compile tasks the following incremental build ran
#   * the incremental build wall-clock time
#
# Run it once with a baseline `tuist` (e.g. the released `mise exec -- tuist`) and once with the
# patched binary built from this branch, then compare. Same project, same machine, same Xcode.
#
# Usage:
#   TUIST_BIN="mise exec -- tuist" SCHEME=MyApp ./skip-write-benchmark.sh /path/to/tuist/project
#   TUIST_BIN=/path/to/patched/tuist SCHEME=MyApp ./skip-write-benchmark.sh /path/to/tuist/project
#
set -euo pipefail

PROJECT_DIR="${1:?Pass the directory containing the Tuist manifest as the first argument}"
TUIST_BIN="${TUIST_BIN:-mise exec -- tuist}"
SCHEME="${SCHEME:?Set SCHEME=<scheme to build>}"
# Isolated DerivedData so runs don't share state with your normal Xcode usage.
DERIVED_DATA="${DERIVED_DATA:-$(mktemp -d)/DerivedData}"

cd "$PROJECT_DIR"

say() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# Snapshot the mtimes (epoch seconds with ns) of every project.pbxproj in the tree.
pbxproj_mtimes() {
  find . -name project.pbxproj -not -path '*/.build/*' -print0 \
    | sort -z \
    | xargs -0 gstat --format='%n %Y.%N' 2>/dev/null
}

# Count real compile tasks in an xcodebuild log (Swift + C/ObjC). A truly warm incremental
# no-op build should print 0 here.
count_compiles() {
  grep -cE '(SwiftCompile|CompileSwift|CompileC |CompileXCStrings|swift-frontend .* -c )' "$1" || true
}

resolve_container() {
  # Prefer a workspace if Tuist produced one, else the single .xcodeproj.
  local ws proj
  ws="$(find . -maxdepth 2 -name '*.xcworkspace' -not -path '*xcodeproj*' | head -1)"
  if [[ -n "$ws" ]]; then echo "-workspace $ws"; return; fi
  proj="$(find . -maxdepth 2 -name '*.xcodeproj' | head -1)"
  echo "-project $proj"
}

say "tuist: $TUIST_BIN   scheme: $SCHEME   derivedData: $DERIVED_DATA"

say "1/5 Initial generate"
$TUIST_BIN generate --no-open

CONTAINER="$(resolve_container)"
say "Container: $CONTAINER"

say "2/5 Warm (full) build — populates the incremental cache"
xcodebuild build $CONTAINER -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  >/tmp/skipwrite-warm.log 2>&1 || { echo "Warm build failed — see /tmp/skipwrite-warm.log"; exit 1; }

BEFORE="$(pbxproj_mtimes)"

say "3/5 No-op generate (no source/manifest changes between warm build and now)"
$TUIST_BIN generate --no-open

AFTER="$(pbxproj_mtimes)"

say "4/5 pbxproj mtime result"
if [[ "$BEFORE" == "$AFTER" ]]; then
  echo "UNCHANGED — no project.pbxproj mtime moved (skip-write effective)"
else
  echo "CHANGED — at least one project.pbxproj was rewritten:"
  diff <(echo "$BEFORE") <(echo "$AFTER") || true
fi

say "5/5 Incremental build after the no-op generate"
START=$(python3 -c 'import time; print(time.time())')
xcodebuild build $CONTAINER -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  >/tmp/skipwrite-incremental.log 2>&1 || { echo "Incremental build failed — see /tmp/skipwrite-incremental.log"; exit 1; }
END=$(python3 -c 'import time; print(time.time())')

COMPILES="$(count_compiles /tmp/skipwrite-incremental.log)"
ELAPSED=$(python3 -c "print(f'{$END - $START:.1f}')")

say "RESULT"
printf 'pbxproj after no-op generate : %s\n' "$([[ "$BEFORE" == "$AFTER" ]] && echo UNCHANGED || echo CHANGED)"
printf 'incremental compile tasks    : %s\n' "$COMPILES"
printf 'incremental build wall time  : %ss\n' "$ELAPSED"
echo "(logs: /tmp/skipwrite-warm.log, /tmp/skipwrite-incremental.log)"
