#!/usr/bin/env bash
# On-demand public-CLI iteration benchmark. See iteration_benchmark.md for the protocol and limits.
set -euo pipefail
umask 077

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'HELP'
Usage: iteration_benchmark.sh [--rounds N] [--jobs N] [--settings all|normal|no-incremental]
                            [--scenarios I1,I2,I3,I5,R1,R2,R3] [--remote]

Requires TUIST_CLI_BINARY, rustup with Cargo/rustc, Node.js and Git. Defaults: seven rounds, four jobs, both settings.
--remote requires TUIST_PROJECT, TUIST_URL, TUIST_CACHE_ENDPOINT and TUIST_TOKEN for an isolated
loopback fixture. Without it, R3 is explicitly skipped. Results and logs stay in a private temporary
directory, including on failure. No production endpoints or shared user caches are used.
HELP
}

ROUNDS=7 JOBS=4 SETTINGS=all SCENARIOS=I1,I2,I3,I5,R1,R2,R3 REMOTE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --rounds|--jobs|--settings|--scenarios)
            [ "$#" -ge 2 ] || fail "Missing value for $1"
            case "$1" in
                --rounds) ROUNDS=$2 ;; --jobs) JOBS=$2 ;;
                --settings) SETTINGS=$2 ;; --scenarios) SCENARIOS=$2 ;;
            esac
            shift 2 ;;
        --remote) REMOTE=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done
case "$ROUNDS" in ''|*[!0-9]*|0*) fail '--rounds must be a positive integer without leading zeros' ;; esac
case "$JOBS" in ''|*[!0-9]*|0*) fail '--jobs must be a positive integer without leading zeros' ;; esac
case "$SETTINGS" in all) LANES='normal no-incremental' ;; normal|no-incremental) LANES=$SETTINGS ;;
    *) fail 'Unknown settings lane' ;; esac
case ",$SCENARIOS," in *,,*) fail 'Empty scenario' ;; esac
case "$SCENARIOS" in *[!I1235R,]*) fail 'Scenarios must be comma-separated IDs without spaces' ;; esac
SEEN=,
for scenario in ${SCENARIOS//,/ }; do
    case "$scenario" in I1|I2|I3|I5|R1|R2|R3) ;; *) fail "Unknown scenario: $scenario" ;; esac
    case "$SEEN" in *",$scenario,"*) fail "Duplicate scenario: $scenario" ;; esac
    SEEN="$SEEN$scenario,"
done

: "${TUIST_CLI_BINARY:?Set TUIST_CLI_BINARY to the public tuist executable}"
[ -x "$TUIST_CLI_BINARY" ] || fail 'TUIST_CLI_BINARY must name an executable'
for program in rustup node git; do command -v "$program" >/dev/null || fail "Missing $program"; done
BINARY=$(node -e 'console.log(require("path").resolve(process.argv[1]))' "$TUIST_CLI_BINARY")
FIXTURE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPORTER="$FIXTURE/iteration_benchmark.mjs"
SERVER=${TUIST_URL:-} ENDPOINT=${TUIST_CACHE_ENDPOINT:-} PROJECT=${TUIST_PROJECT:-} TOKEN=${TUIST_TOKEN:-}
if [ "$REMOTE" = 1 ]; then
    [ -n "$PROJECT" ] && [ -n "$TOKEN" ] || fail '--remote requires TUIST_PROJECT and TUIST_TOKEN'
    node "$REPORTER" endpoints "$SERVER" "$ENDPOINT"
fi

# Deliberately do not source common.sh: it disables incremental compilation and deletes target on every build.
for name in $(compgen -e); do
    case "$name" in
        TUIST_*|CARGO_*|RUSTC*|RUSTFLAGS|RUSTDOCFLAGS|RUSTDOC|RUST_LOG|GITHUB_*|CI|CI_*|MAKEFLAGS|MFLAGS|OUT_DIR|XDG_*) unset "$name" ;;
    esac
done
# Preserve normal loader behavior, especially Cargo's Linux LD_LIBRARY_PATH. Reject inherited injection instead
# of clearing it to manufacture cache eligibility. Other inherited search settings are recorded only as names.
for name in $(compgen -e); do
    case "$name" in LD_PRELOAD|DYLD_INSERT_LIBRARIES) fail "Unset inherited $name before benchmarking" ;; esac
done

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tuist-cargo-iteration.XXXXXX")
printf 'Results: %s\n' "$ROOT"
LOCAL_SERVER_PID=
cleanup() {
    local status=$?
    if [ -n "$LOCAL_SERVER_PID" ]; then kill "$LOCAL_SERVER_PID" 2>/dev/null || true; wait "$LOCAL_SERVER_PID" 2>/dev/null || true; fi
    if [ "$status" != 0 ]; then printf 'Benchmark failed; retained diagnostics: %s\n' "$ROOT" >&2; fi
}
trap cleanup EXIT
export CARGO_HOME="$ROOT/cargo-home" CARGO_TERM_COLOR=never
mkdir -p "$CARGO_HOME" "$ROOT/config"
export XDG_CONFIG_HOME="$ROOT/config"
node "$REPORTER" toolchain "$ROOT"
CARGO_BINARY=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).cargo' "$ROOT/toolchain.json")
export RUSTC=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).rustc' "$ROOT/toolchain.json")
export RUSTUP_TOOLCHAIN=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).toolchain' "$ROOT/toolchain.json")
# PATH may contain the supported mise Cargo wrapper. Never use it for the baseline or reference build.
export TUIST_CARGO_EXECUTABLE="$CARGO_BINARY"
node "$REPORTER" metadata "$ROOT" "$BINARY" "$ROUNDS" "$JOBS" "$SETTINGS" "$SCENARIOS" "$REMOTE"
node "$REPORTER" local-server "$ROOT" > "$ROOT/local-server.log" 2>&1 &
LOCAL_SERVER_PID=$!
for attempt in {1..100}; do
    [ ! -f "$ROOT/local-server-url" ] || break
    kill -0 "$LOCAL_SERVER_PID" 2>/dev/null || fail "Local reporting receiver failed; inspect $ROOT/local-server.log"
    sleep 0.1
done
[ -f "$ROOT/local-server-url" ] || fail 'Local reporting receiver did not start'
LOCAL_SERVER=$(cat "$ROOT/local-server-url")

write_workspace() {
    mkdir -p "$WORKSPACE"/{shared,left,right,sibling}/src
    mkdir -p "$WORKSPACE/.cargo"
    # Source tags isolate compiler actions, not the accumulating remote prefetch manifest. CargoUnitCache
    # hashes config contents: a comment isolates samples without changing Cargo's build configuration.
    printf '# iteration benchmark scope: %s\n' "$TAG" > "$WORKSPACE/.cargo/config.toml"
    cat > "$WORKSPACE/Cargo.toml" <<'TOML'
[workspace]
members = ["shared", "left", "right", "sibling"]
resolver = "2"
TOML
    for package in shared left right sibling; do
        cat > "$WORKSPACE/$package/Cargo.toml" <<TOML
[package]
name = "iteration_$package"
version = "0.1.0"
edition = "2021"
TOML
    done
    for package in left right; do
        cat >> "$WORKSPACE/$package/Cargo.toml" <<'TOML'
[dependencies]
iteration_shared = { path = "../shared" }
TOML
    done
    write_revision A
    (cd "$WORKSPACE" && "$CARGO_BINARY" generate-lockfile --offline) > "$SAMPLE/lock.log" 2>&1
    (cd "$WORKSPACE" && git init -q && git add . && git -c user.name=Benchmark \
        -c user.email=benchmark@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null \
        commit -qm 'Controlled benchmark workspace') > "$SAMPLE/git.log" 2>&1
}

write_revision() {
    local shared=7 offset=10
    [ "$1" != shared-edit ] || shared=11
    [ "$1" != app-edit ] || offset=12
    # Each round/scenario has distinct source inputs, identical across configurations. A prior sample cannot
    # populate a later remote miss. Record the tag and patches so the exact synthetic workload is reproducible.
    if [ "$1" = A ] || [ "$1" = shared-edit ]; then
        printf '// %s\npub fn value() -> u64 { %s }\n' "$TAG" "$shared" > "$WORKSPACE/shared/src/lib.rs"
    fi
    if [ "$1" = A ] || [ "$1" = app-edit ]; then
        printf '// %s\nfn main() { println!("{}", iteration_shared::value() + %s); }\n' "$TAG" "$offset" > "$WORKSPACE/left/src/main.rs"
    fi
    if [ "$1" = A ]; then
        printf '// %s\nfn main() { println!("{}", iteration_shared::value() * 3); }\n' "$TAG" > "$WORKSPACE/right/src/main.rs"
        printf '// %s\npub fn unrelated() -> u64 { 101 }\n' "$TAG" > "$WORKSPACE/sibling/src/lib.rs"
    fi
}

build() {
    local phase=$1
    # Give each report its own branch before timing so observation never depends on timestamp guesses.
    if [ "$MODE" != cargo ]; then
        (cd "$WORKSPACE" && git branch -m "$TAG/$MODE/$phase")
    fi
    if [ "$MODE" = remote ]; then node "$REPORTER" remote-setup "$SAMPLE" "$phase"; fi
    if [ "$MODE" = cargo ]; then
        (cd "$WORKSPACE" && node "$REPORTER" measure "$SAMPLE" "$phase" "$ROUND" "$LANE" "$SCENARIO" "$MODE" \
            "$CARGO_BINARY" build --workspace --locked --offline -j "$JOBS")
    else
        (cd "$WORKSPACE" && node "$REPORTER" measure "$SAMPLE" "$phase" "$ROUND" "$LANE" "$SCENARIO" "$MODE" \
            "$BINARY" cargo build --workspace --locked --offline -j "$JOBS")
    fi
    check_outputs "$WORKSPACE/target/debug" "$EXPECTED"
    if [ "$MODE" = remote ]; then
        node "$REPORTER" remote-report "$SAMPLE" "$phase" "$TAG/$MODE/$phase"
    elif [ "$MODE" = local ]; then
        node "$REPORTER" local-report "$SAMPLE" "$phase" "$TAG/$MODE/$phase" "$ROOT"
    fi
}

check_outputs() {
    local actual right
    actual=$("$1/iteration_left")
    right=$("$1/iteration_right")
    actual=$(printf '%s\n%s' "$actual" "$right")
    [ "$actual" = "$2" ] || fail "Incorrect output in $SAMPLE: expected [$2], got [$actual]"
}

sample() (
    MODE=$1
    SAMPLE="$ROOT/$LANE/$SCENARIO/round-$ROUND/$MODE"
    WORKSPACE="$SAMPLE/workspace"
    TAG="$(basename "$ROOT")/$LANE/$SCENARIO/$ROUND"
    mkdir -p "$SAMPLE"
    export XDG_CACHE_HOME="$SAMPLE/cache" XDG_STATE_HOME="$SAMPLE/state"
    export TUIST_PROJECT=fixture/iteration TUIST_URL="$LOCAL_SERVER" TUIST_TOKEN=fixture-local-only
    if [ "$MODE" = remote ]; then
        export TUIST_PROJECT="$PROJECT" TUIST_URL="$SERVER" TUIST_CACHE_ENDPOINT="$ENDPOINT" TUIST_TOKEN="$TOKEN"
    fi
    if [ "$LANE" = no-incremental ]; then export CARGO_INCREMENTAL=0; else unset CARGO_INCREMENTAL; fi
    write_workspace
    EXPECTED=$(printf '17\n21')
    case "$SCENARIO" in
        I1|I2|I3|I5|R2|R3) build prime ;;
    esac
    case "$SCENARIO" in
        I2) write_revision app-edit; EXPECTED=$(printf '19\n21') ;;
        I3) write_revision shared-edit; EXPECTED=$(printf '21\n33') ;;
        I5)
            write_revision app-edit; EXPECTED=$(printf '19\n21'); build edited
            # Rewrite only changed bytes on return to A. Retain fresh timestamps, not Git's old mtimes.
            printf '// %s\nfn main() { println!("{}", iteration_shared::value() + 10); }\n' "$TAG" > "$WORKSPACE/left/src/main.rs"
            EXPECTED=$(printf '17\n21') ;;
        R2) rm -rf "$WORKSPACE/target" ;;
        R3) rm -rf "$WORKSPACE/target" "$XDG_CACHE_HOME" ;;
    esac
    build measured
    if [ "$MODE" = remote ] && [ "$LANE" = no-incremental ] && [ "$SCENARIO" = R1 ]; then
        # Cold uploads may have unknown byte counts. Prove publication by restoring this unique source corpus
        # through the real cache, outside the measured interval, with no target or client cache remaining.
        rm -rf "$WORKSPACE/target" "$XDG_CACHE_HOME"
        build remote-proof
        node "$REPORTER" remote-publication "$SAMPLE"
    fi
    # Build the measured source revision through ordinary Cargo with a separate target directory. This and
    # independent arithmetic expectations catch stale cache hits without requiring byte-identical executables.
    (cd "$WORKSPACE" && "$CARGO_BINARY" build --workspace --locked --offline -j "$JOBS" \
        --target-dir "$SAMPLE/reference-target") > "$SAMPLE/reference.log" 2>&1
    check_outputs "$SAMPLE/reference-target/debug" "$EXPECTED"
    (cd "$WORKSPACE" && git diff --no-ext-diff) > "$SAMPLE/patch.diff"
    node "$REPORTER" verified "$SAMPLE"
    printf '%s %s round=%s %s: verified\n' "$LANE" "$SCENARIO" "$ROUND" "$MODE"
)

for LANE in $LANES; do
    for SCENARIO in ${SCENARIOS//,/ }; do
        if [ "$SCENARIO" = R3 ] && [ "$REMOTE" = 0 ]; then
            printf '%s R3: SKIPPED (enable --remote with an isolated real cache)\n' "$LANE"
            continue
        fi
        MODES='cargo local'
        if [ "$REMOTE" = 1 ] && [ "$SCENARIO" != R2 ]; then MODES='cargo local remote'; fi
        [ "$SCENARIO" != R3 ] || MODES='cargo remote'
        ROUND=1
        while [ "$ROUND" -le "$ROUNDS" ]; do
            # Rotate configuration order within a round; never run competing builds concurrently.
            set -- $MODES
            rotations=$(( (ROUND - 1) % $# ))
            while [ "$rotations" -gt 0 ]; do first=$1; shift; set -- "$@" "$first"; rotations=$((rotations - 1)); done
            for mode in "$@"; do sample "$mode"; done
            ROUND=$((ROUND + 1))
        done
    done
done
node "$REPORTER" summarize "$ROOT"
printf 'PASS: all measured outputs agree with independent expectations and ordinary Cargo. Results: %s\n' "$ROOT"
