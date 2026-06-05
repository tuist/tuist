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

    # Isolate cache + state + config under the test's tmp dir so we can wipe the
    # local cache to force a remote pull, and never touch the host's real Tuist
    # data. Credentials live under XDG_CONFIG_HOME (not XDG_CACHE_HOME), so the
    # cache wipe below does not log us out.
    export XDG_CACHE_HOME="${BATS_FILE_TMPDIR}/cache"
    export XDG_STATE_HOME="${BATS_FILE_TMPDIR}/state"
    export XDG_CONFIG_HOME="${BATS_FILE_TMPDIR}/config"
    mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"

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
    # The way `auth login` is pointed at a server changed across versions: older
    # CLIs take --path and read the URL from Tuist.swift, newer ones take --url.
    # Try --url first and fall back to --path so the suite survives the pin
    # moving across that boundary. Credentials/email/password come from env.
    echo "# Logging in to ${TUIST_URL}..." >&3
    "$TUIST_EXECUTABLE" auth login \
        --email "$TUIST_AUTH_EMAIL" \
        --password "$TUIST_AUTH_PASSWORD" \
        --url "$TUIST_URL" \
        || "$TUIST_EXECUTABLE" auth login \
            --email "$TUIST_AUTH_EMAIL" \
            --password "$TUIST_AUTH_PASSWORD" \
            --path "$FIXTURE_DIR"

    # --build-system is required non-interactively; without it the CLI prompts
    # "Which build system does your project use?" and aborts in CI. xcode is the
    # build system the binary cache flow exercised below depends on.
    echo "# Creating throwaway project ${PROJECT_HANDLE}..." >&3
    "$TUIST_EXECUTABLE" project create "$PROJECT_HANDLE" --path "$FIXTURE_DIR" --build-system xcode
}

teardown_file() {
    if [[ -n "${PROJECT_HANDLE:-}" ]]; then
        "$TUIST_EXECUTABLE" project delete "$PROJECT_HANDLE" --path "$FIXTURE_DIR" 2>/dev/null || true
    fi
    # --path resolves the canary host so logout clears the right session.
    "$TUIST_EXECUTABLE" auth logout --path "$FIXTURE_DIR" 2>/dev/null || true
}

@test "oldest supported CLI pulls the module cache from canary without a signature error" {
    cd "$FIXTURE_DIR"

    # Warm the cache: build the Framework and upload its xcframework to canary.
    run "$TUIST_EXECUTABLE" cache --path "$FIXTURE_DIR"
    echo "# tuist cache output:" >&3
    echo "$output" >&3
    [ "$status" -eq 0 ]

    # A just-warmed artifact takes a moment to become downloadable from the
    # remote cache, so wipe the local cache and poll: re-run the focused generate
    # until the cached Framework is pulled back and linked as an xcframework
    # (mirroring how the HEAD canary suite waits for remote results). Without the
    # poll this races the cache and flakes - the remote pull can return nothing on
    # the first try moments after the upload.
    #
    # The signature check is implicit and behavioral: a cached xcframework can
    # only be linked if the old CLI completed a signed download. If the server
    # stopped signing, the pull would fail and no xcframework would ever appear,
    # so this still fails on the regression it guards, without matching log wording.
    linked=0
    for attempt in 1 2 3 4 5 6; do
        rm -rf "${XDG_CACHE_HOME:?}"/* 2>/dev/null || true
        echo "# tuist generate (attempt ${attempt}):" >&3
        "$TUIST_EXECUTABLE" generate App --path "$FIXTURE_DIR" --no-open >&3 2>&1 || true
        if grep -q "xcframework" "${FIXTURE_DIR}"/*.xcodeproj/project.pbxproj 2>/dev/null; then
            linked=1
            break
        fi
        echo "# cache not pulled yet; retrying in 10s" >&3
        sleep 10
    done
    if [ "$linked" -ne 1 ]; then
        echo "# Cached xcframework was never pulled from canary after retries" >&3
    fi
    [ "$linked" -eq 1 ]
}
