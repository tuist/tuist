# Shared by the public-command fixtures: `. common.sh <name>` creates an isolated temporary root and cache, clears
# inherited Tuist, GitHub and loader settings, and provides offline builds whose `TUIST_DEBUG=1` per-task cache lines
# the fixtures read. Successful runs remove the root; failures retain it with every build's log.

: "${TUIST_CLI_BINARY:?Set TUIST_CLI_BINARY to the freshly built tuist executable}"
BINARY=$TUIST_CLI_BINARY
FIXTURE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tuist-cargo-$1.XXXXXX")
cleanup() {
    if [ "$?" = 0 ]; then rm -rf "$ROOT"; else printf 'Fixture retained at %s\n' "$ROOT" >&2; fi
}
trap cleanup EXIT
for name in $(compgen -e); do
    case $name in TUIST_* | GITHUB_* | LD_* | DYLD_* | RUSTC_WRAPPER | CARGO_BUILD_RUSTC_WRAPPER) unset "$name" ;; esac
done
export CARGO_INCREMENTAL=0 CARGO_TERM_COLOR=never XDG_CACHE_HOME="$ROOT/xdg" TUIST_URL=http://127.0.0.1:9 TUIST_DEBUG=1

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

expect() {
    [ "$2" = "$3" ] || fail "$1: expected '$2', got '$3'"
}

# Builds the project at $1 from a fresh target as scenario $2, with any further Cargo arguments. Sets STATUS.
run_build() {
    local path=$1 scenario=$2
    shift 2
    rm -rf "$path/target"
    set +e
    (cd "$path" && "$BINARY" cargo build --offline "$@") > /dev/null 2> "$ROOT/$scenario.log"
    STATUS=$?
    set -e
}

build() {
    run_build "$@"
    [ "$STATUS" = 0 ] || fail "$2: build failed, see $ROOT/$2.log"
}

# The last hit/miss line for crate $2 in scenario $1, or nothing when the crate made no cache decision.
task() {
    sed -nE "s/^Tuist Cargo cache: (hit|miss) rust $2\$/\\1/p" "$ROOT/$1.log" | tail -1
}

# The crates Cargo compiled in scenario $1, sorted. Cargo announces hits too; a restored unit is never announced.
compiled() {
    sed -nE 's/^ +Compiling ([^ ]+) .*/\1/p' "$ROOT/$1.log" | sort | tr '\n' ' ' | sed 's/ $//'
}

logged() {
    grep -qF -- "$2" "$ROOT/$1.log"
}

# Overwrites the first bytes of $1 in place, keeping its size.
corrupt() {
    printf corrupt | dd of="$1" bs=1 count=7 conv=notrunc 2> /dev/null
}
