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

    # Isolate cache + state + config so we can wipe the local cache to force a
    # remote pull, and never touch the host's real Tuist data. Credentials live
    # under XDG_CONFIG_HOME (not XDG_CACHE_HOME), so the cache wipe below does not
    # log us out.
    #
    # Keep these in a dir we own and clean ourselves rather than under
    # BATS_FILE_TMPDIR: tuist keeps writing here (manifest cache, session HAR)
    # for a moment after a command returns, and bats's automatic teardown of its
    # own tmp dir races those writes and aborts the run with "Directory not
    # empty" even when the test passed. Owning the dir keeps the exit status
    # independent of that race.
    #
    # The CLI reads TUIST_XDG_* before XDG_*, and managed runner steps export
    # TUIST_XDG_CACHE_HOME pointing at a cache volume that outlives the job, so
    # both spellings are set here.
    export TUIST_TEST_HOME
    TUIST_TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/module-cache-bc.XXXXXX")"
    export XDG_CACHE_HOME="${TUIST_TEST_HOME}/cache"
    export XDG_STATE_HOME="${TUIST_TEST_HOME}/state"
    export XDG_CONFIG_HOME="${TUIST_TEST_HOME}/config"
    export TUIST_XDG_CACHE_HOME="$XDG_CACHE_HOME"
    export TUIST_XDG_STATE_HOME="$XDG_STATE_HOME"
    export TUIST_XDG_CONFIG_HOME="$XDG_CONFIG_HOME"
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

    # The CLI loads the nearest Tuist.swift from the working directory. Run from
    # the fixture so the old binary never picks up the repository's own manifest,
    # which may use APIs newer than it.
    cd "$FIXTURE_DIR"

    echo "# Using tuist binary: $("$TUIST_EXECUTABLE" version 2>/dev/null || echo unknown)" >&3
    # The way `auth login` is pointed at a server changed across versions: older
    # CLIs take --path and read the URL from Tuist.swift, newer ones take --url.
    # Detect which the pinned binary supports from its --help so the suite
    # survives the pin moving across that boundary - and, crucially, so a real
    # login failure (e.g. a transient 502 from the canary gateway) surfaces as
    # itself instead of being masked by an "Unknown option '--path'" from a
    # blind `|| ... --path` fallback. Credentials/email/password come from env.
    local login_target=(--path "$FIXTURE_DIR")
    if "$TUIST_EXECUTABLE" auth login --help 2>&1 | grep -q -- '--url'; then
        login_target=(--url "$TUIST_URL")
    fi

    # Retry the login: a single transient gateway blip against canary must not
    # fail the whole production gate, mirroring the polled cache pull below.
    echo "# Logging in to ${TUIST_URL}..." >&3
    logged_in=0
    for attempt in 1 2 3 4 5; do
        if "$TUIST_EXECUTABLE" auth login \
            --email "$TUIST_AUTH_EMAIL" \
            --password "$TUIST_AUTH_PASSWORD" \
            "${login_target[@]}" >&3 2>&1; then
            logged_in=1
            break
        fi
        echo "# auth login attempt ${attempt} failed; retrying in 3s" >&3
        sleep 3
    done
    if [ "$logged_in" -ne 1 ]; then
        echo "# auth login to ${TUIST_URL} failed after retries" >&3
    fi
    [ "$logged_in" -eq 1 ]

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
    # Remove our own XDG dir. Tolerant on purpose: tuist may still be flushing
    # into it, and a failed delete here must not fail the run (the dir is outside
    # bats's tmp, so it is never touched by bats's own cleanup).
    if [[ -n "${TUIST_TEST_HOME:-}" ]]; then
        rm -rf "${TUIST_TEST_HOME:?}" 2>/dev/null || true
    fi
}

@test "oldest supported CLI pulls the module cache from canary without a signature error" {
    cd "$FIXTURE_DIR"

    # Warm the cache: build the Framework and upload its xcframework to canary.
    # `tuist cache` exits 0 when the upload is refused and only warns about it,
    # so the output is what proves the artifact reached the remote cache.
    #
    # The run-metadata warning is excluded: it reports the analytics upload, not
    # the cache, and the server can still answer 404 for a project created
    # seconds earlier because the project lookup is cached for up to a minute.
    run "$TUIST_EXECUTABLE" cache --path "$FIXTURE_DIR"
    echo "# tuist cache output:" >&3
    echo "$output" >&3
    [ "$status" -eq 0 ]
    local cache_output
    cache_output="$(grep -v "Failed to upload run metadata" <<<"$output" || true)"
    if ! grep -q "target stored: Framework" <<<"$cache_output" ||
        grep -qiE "No targets were stored|Failed to upload|authentication failed" <<<"$cache_output"; then
        echo "# tuist cache did not upload Framework to the remote cache" >&3
        return 1
    fi

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
    #
    # Linking alone proves nothing when the binary is still on disk: `tuist cache`
    # keeps a local copy, so the cache directory is emptied first and the pull
    # only counts once the binary is back in it.
    local binaries_dir="${TUIST_XDG_CACHE_HOME}/tuist/Binaries"
    linked=0
    for attempt in 1 2 3 4; do
        rm -rf "${TUIST_XDG_CACHE_HOME:?}"/* 2>/dev/null || true
        if [ -n "$(find "$TUIST_XDG_CACHE_HOME" -name '*.xcframework' -print -quit)" ]; then
            echo "# a cached xcframework survived the local cache wipe" >&3
            return 1
        fi
        echo "# tuist generate (attempt ${attempt}):" >&3
        run "$TUIST_EXECUTABLE" generate App --path "$FIXTURE_DIR" --no-open
        echo "$output" >&3
        if grep -qiE "authentication failed|Unable to retrieve" <<<"$output"; then
            echo "# the remote cache refused the pull" >&3
        elif grep -q "xcframework" "${FIXTURE_DIR}"/*.xcodeproj/project.pbxproj 2>/dev/null &&
            [ -n "$(find "$binaries_dir" -name 'Framework.xcframework' -print -quit 2>/dev/null)" ]; then
            linked=1
            break
        fi
        echo "# cache not pulled yet; retrying in 3s" >&3
        sleep 3
    done
    if [ "$linked" -ne 1 ]; then
        echo "# Cached xcframework was never pulled from canary after retries" >&3
    fi
    [ "$linked" -eq 1 ]
}
