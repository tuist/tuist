#!/usr/bin/env bash
#
# Reproducer for https://github.com/tuist/tuist/issues/12338
#
# A dependency declared by URL in Tuist/Package.swift with SPM traits, installed
# through the registry (`--replace-scm-with-registry`), loses its
# SWIFT_ACTIVE_COMPILATION_CONDITIONS in the generated dependency project.
#
# Usage:
#   ./reproduce.sh [/path/to/tuist]
#
# The binary can also be provided through TUIST_BIN. Set KEEP_WORKDIR=1 to keep
# the temporary project for inspection.
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUIST_BIN="${1:-${TUIST_BIN:-tuist}}"

if ! command -v "$TUIST_BIN" >/dev/null 2>&1 && [[ ! -x "$TUIST_BIN" ]]; then
    echo "error: '$TUIST_BIN' is not an executable tuist binary" >&2
    exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/registry-spm-traits.XXXXXX")"
cleanup() {
    if [[ "${KEEP_WORKDIR:-0}" == "1" ]]; then
        echo "Kept working directory: $WORK_DIR"
    else
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

cp -R "$FIXTURE_DIR/Project/." "$WORK_DIR/"
cd "$WORK_DIR"

echo "==> Using tuist: $TUIST_BIN"
echo "==> Registry setup"
"$TUIST_BIN" registry setup -p . >/dev/null

echo "==> Installing dependencies through the registry"
"$TUIST_BIN" install

echo "==> Generating the project"
"$TUIST_BIN" generate --no-open

DEPENDENCY_PROJECT="$(find "$WORK_DIR" -path '*tuist-derived/Projects/*swift-dependencies*' -name project.pbxproj -print 2>/dev/null | head -1)"
if [[ -z "$DEPENDENCY_PROJECT" ]]; then
    echo "error: no generated project.pbxproj found" >&2
    exit 2
fi

echo "==> Generated dependency project: $DEPENDENCY_PROJECT"
echo "==> SWIFT_ACTIVE_COMPILATION_CONDITIONS of the swift-dependencies target:"
if ! grep -h -A 6 "SWIFT_ACTIVE_COMPILATION_CONDITIONS" "$DEPENDENCY_PROJECT"; then
    echo "    (no SWIFT_ACTIVE_COMPILATION_CONDITIONS found)"
fi

if grep -q "CombineSchedulers" "$DEPENDENCY_PROJECT"; then
    echo "PASS: the swift-dependencies traits made it into the generated project"
else
    echo "FAIL: the generated dependency project is missing the swift-dependencies traits (issue #12338)"
    exit 1
fi
