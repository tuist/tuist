#!/usr/bin/env bash
# Runs the same commands through the Swift `tuist` and the Rust binary that links the
# Swift code, and fails on any difference in exit code, stdout, stderr, or generated
# Xcode files. Paths, session ids, and timings are normalized first.
#
# Usage: cli-rs/scripts/parity.sh <bin-dir>
#   <bin-dir> holds `tuist` (Swift) and `tuist-rs` (Rust) side by side, e.g. .build/debug.

set -uo pipefail

BIN_DIR=$(cd "$1" && pwd)
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
EXAMPLES="$REPO_ROOT/examples/xcode"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0

normalize() {
    sed -E \
        -e "s#$WORK/(swift|rust)#WORK#g" \
        -e 's#sessions/[A-F0-9-]{36}#sessions/SESSION#g' \
        -e 's#[0-9]+\.[0-9]+s#Ns#g' \
        "$1"
}

# case <name> <fixture-or-empty> <args...>
case_() {
    local name=$1 fixture=$2
    shift 2
    for side in swift rust; do
        local dir="$WORK/$side/$name"
        mkdir -p "$dir"
        if [ -n "$fixture" ]; then
            cp -R "$EXAMPLES/$fixture/." "$dir/"
        fi
        local bin="$BIN_DIR/tuist"
        [ "$side" = rust ] && bin="$BIN_DIR/tuist-rs"
        (cd "$dir" && "$bin" "$@" >"$WORK/$side.$name.out" 2>"$WORK/$side.$name.err"; echo $? >"$WORK/$side.$name.code")
    done
    local ok=1
    for stream in code out err; do
        if ! cmp -s <(normalize "$WORK/swift.$name.$stream") <(normalize "$WORK/rust.$name.$stream"); then
            ok=0
            echo "  $stream differs:"
            diff <(normalize "$WORK/swift.$name.$stream") <(normalize "$WORK/rust.$name.$stream") | head -10 | sed 's/^/    /'
        fi
    done
    if [ -n "$fixture" ]; then
        while IFS= read -r file; do
            if ! cmp -s <(normalize "$WORK/swift/$name/$file") <(normalize "$WORK/rust/$name/$file"); then
                ok=0
                echo "  generated file differs: $file"
            fi
        done < <(cd "$WORK/swift/$name" && find . \( -name project.pbxproj -o -name '*.xcscheme' -o -name contents.xcworkspacedata \) | sort)
    fi
    if [ $ok = 1 ]; then
        echo "same  $name (exit $(cat "$WORK/swift.$name.code"))"
    else
        echo "DIFF  $name"
        failures=$((failures + 1))
    fi
}

case_ version "" version
case_ help "" --help
case_ generate-help "" generate --help
case_ unknown-command "" not-a-command
case_ bad-flag "" generate --bogus-flag
case_ whoami "" auth whoami
case_ generate generated_app_with_framework_and_tests generate --no-open
case_ invalid-manifest generated_invalid_manifest generate --no-open
case_ graph-json generated_app_with_framework_and_tests graph --format json --no-open --output-path .
case_ hash-cache generated_app_with_framework_and_tests hash cache

echo
if [ $failures -gt 0 ]; then
    echo "$failures case(s) differ"
    exit 1
fi
echo "all cases match"
