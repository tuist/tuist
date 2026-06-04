#!/usr/bin/env bats
# E2E test: the oldest CLI version we still support must keep working against the
# deployed canary server.
#
# Background: a production change once stopped attaching the cryptographic
# signature to cache-artifact downloads. Newer CLIs had moved past requiring it,
# but older CLIs still ran SignatureVerifierMiddleware and rejected every cache
# response ("Invalid or missing signature ... blocked for security reasons"),
# dropping cache hit rate to 0% for customers pinned to an older release. The
# HEAD acceptance suite could never catch this because it always runs the CLI
# built from HEAD. This suite runs the oldest supported binary instead.
#
# Prerequisites (provided by CI — see
# .github/workflows/server-production-deployment.yml):
#   - TUIST_EXECUTABLE: absolute path to the pinned oldest-supported tuist binary
#   - TUIST_AUTH_EMAIL / TUIST_AUTH_PASSWORD: canary credentials (server-k8s-canary env)
#   - TUIST_URL: server to test against (defaults to https://canary.tuist.dev)

setup_file() {
    load 'test_helper'

    export TUIST_EXECUTABLE="${TUIST_EXECUTABLE:-}"
    if [[ -z "$TUIST_EXECUTABLE" ]]; then
        skip "TUIST_EXECUTABLE must point to the pinned oldest-supported tuist binary"
    fi

    export TUIST_URL="${TUIST_URL:-https://canary.tuist.dev}"

    require_cmd uuidgen
    require_env TUIST_AUTH_EMAIL
    require_env TUIST_AUTH_PASSWORD

    # Isolate cache + state under the test's tmp dir so we can wipe the local
    # cache to force a remote pull, and never touch the host's real Tuist data.
    export XDG_CACHE_HOME="${BATS_FILE_TMPDIR}/cache"
    export XDG_STATE_HOME="${BATS_FILE_TMPDIR}/state"
    mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME"

    export FIXTURE_DIR="${BATS_FILE_TMPDIR}/module_cache_app"
    cp -R "${E2E_DIR}/fixtures/module_cache_app" "$FIXTURE_DIR"

    # Throwaway project under the existing `tuist` org, mirroring the HEAD canary
    # suite's create/delete lifecycle so each run is hermetic.
    local handle_suffix
    handle_suffix="$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-12)"
    export PROJECT_HANDLE="tuist/bc-${handle_suffix}"

    cat > "${FIXTURE_DIR}/Tuist.swift" <<EOF
import ProjectDescription

let tuist = Tuist(
    fullHandle: "${PROJECT_HANDLE}",
    url: "${TUIST_URL}"
)
EOF

    echo "# Using tuist binary: $("$TUIST_EXECUTABLE" version 2>/dev/null || echo unknown)" >&3
    echo "# Logging in to ${TUIST_URL}..." >&3
    "$TUIST_EXECUTABLE" auth login \
        --email "$TUIST_AUTH_EMAIL" \
        --password "$TUIST_AUTH_PASSWORD" \
        --url "$TUIST_URL"

    echo "# Creating throwaway project ${PROJECT_HANDLE}..." >&3
    "$TUIST_EXECUTABLE" project create "$PROJECT_HANDLE" --path "$FIXTURE_DIR"
}

teardown_file() {
    if [[ -n "${PROJECT_HANDLE:-}" ]]; then
        "$TUIST_EXECUTABLE" project delete "$PROJECT_HANDLE" --path "$FIXTURE_DIR" 2>/dev/null || true
    fi
    "$TUIST_EXECUTABLE" auth logout 2>/dev/null || true
}

@test "oldest supported CLI pulls the module cache from canary without a signature error" {
    cd "$FIXTURE_DIR"

    # Warm the cache: build the Framework and upload its xcframework to canary.
    run "$TUIST_EXECUTABLE" cache --path "$FIXTURE_DIR"
    echo "# tuist cache output:" >&3
    echo "$output" >&3
    refute_signature_error "$output"
    [ "$status" -eq 0 ]

    # Drop the local cache so the focused generate below has to fetch the
    # artifact back from canary, exercising the signed download path
    # (downloadCacheArtifact -> SignatureVerifierMiddleware).
    rm -rf "${XDG_CACHE_HOME:?}"/* 2>/dev/null || true

    # Focusing App links the cached Framework as an xcframework, which downloads
    # it from canary — this is where the missing signature broke older CLIs.
    run "$TUIST_EXECUTABLE" generate App --path "$FIXTURE_DIR" --no-open
    echo "# tuist generate output:" >&3
    echo "$output" >&3
    refute_signature_error "$output"
    [ "$status" -eq 0 ]

    # Guard against a silent no-op: the cached binary must actually have been
    # pulled and linked as an xcframework in the generated project, otherwise the
    # download (and signature verification) never happened.
    run bash -c "grep -Rl 'xcframework' '${FIXTURE_DIR}'/*.xcodeproj/project.pbxproj 2>/dev/null"
    if [ "$status" -ne 0 ]; then
        echo "# No xcframework linked in the generated project — the cache was not pulled" >&3
    fi
    [ "$status" -eq 0 ]
}
