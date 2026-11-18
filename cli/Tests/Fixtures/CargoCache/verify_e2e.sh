#!/usr/bin/env bash
# Opt-in cache verification (`TUIST_CARGO_VERIFY`, `TUIST_CARGO_VERIFY_RECOMPILE`) through the public `tuist cargo`
# command, offline and local-only.
#
# `strict` is a path library keyed by a remembered source list, `gen` uses a proc macro and has a deterministic build
# script, so the read recorder keys both, and `clock`'s build script stamps its output with the current time, as an
# irreproducible build step would. Verifying inputs must agree everywhere; recompiling must flag `clock`'s run as a
# content divergence, and nothing else. Neither may change what the cache holds.
set -euo pipefail
[ "$(uname -sm)" = "Darwin arm64" ] || { echo "Recorded verification needs arm64 macOS" >&2; exit 1; }
. "$(dirname "$0")/common.sh" verify
export TUIST_PROJECT=fixture/verify

checkout() {
    local path="$ROOT/$1/ws"
    mkdir -p "$path/strict/src" "$path/macros/src" "$path/gen/src" "$path/clock/src" "$path/app/src"
    printf '[workspace]\nmembers = ["strict", "macros", "gen", "clock", "app"]\nresolver = "2"\n' > "$path/Cargo.toml"
    printf '[package]\nname = "strict"\nversion = "0.1.0"\nedition = "2021"\n' > "$path/strict/Cargo.toml"
    printf 'mod part;\npub fn strict() -> u64 { part::PART + 1 }\n' > "$path/strict/src/lib.rs"
    printf 'pub const PART: u64 = 10;\n' > "$path/strict/src/part.rs"
    printf '[package]\nname = "macros"\nversion = "0.1.0"\nedition = "2021"\n[lib]\nproc-macro = true\n' \
        > "$path/macros/Cargo.toml"
    printf '20\n' > "$path/value.txt"
    cat > "$path/macros/src/lib.rs" << 'RUST'
extern crate proc_macro;
#[proc_macro]
pub fn value(_: proc_macro::TokenStream) -> proc_macro::TokenStream {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../value.txt");
    std::fs::read_to_string(path).unwrap().trim().parse().unwrap()
}
RUST
    printf '[package]\nname = "gen"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nmacros = { path = "../macros" }\n' \
        > "$path/gen/Cargo.toml"
    printf '300\n' > "$path/gen/generated.txt"
    cat > "$path/gen/build.rs" << 'RUST'
fn main() {
    println!("cargo::rerun-if-changed=generated.txt");
    let input = std::fs::read_to_string("generated.txt").unwrap();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(format!("{out}/generated.rs"), format!("pub const GENERATED: u64 = {};\n", input.trim())).unwrap();
}
RUST
    printf 'include!(concat!(env!("OUT_DIR"), "/generated.rs"));\npub fn gen() -> u64 { macros::value!() + GENERATED }\n' \
        > "$path/gen/src/lib.rs"
    printf '[package]\nname = "clock"\nversion = "0.1.0"\nedition = "2021"\n' > "$path/clock/Cargo.toml"
    cat > "$path/clock/build.rs" << 'RUST'
fn main() {
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(format!("{out}/stamp.rs"), format!("pub const STAMP: u128 = {stamp};\n")).unwrap();
}
RUST
    printf 'include!(concat!(env!("OUT_DIR"), "/stamp.rs"));\n' > "$path/clock/src/lib.rs"
    printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nstrict = { path = "../strict" }\ngen = { path = "../gen" }\nclock = { path = "../clock" }\n' \
        > "$path/app/Cargo.toml"
    printf 'fn main() { println!("{} {} {}", strict::strict(), gen::gen(), clock::STAMP); }\n' > "$path/app/src/main.rs"
    # Recording shares the dependency-unit cache's scope, which is keyed by the lockfile.
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null)
    printf '%s' "$path"
}

# Builds scenario $2 in $1 and sets STRICT, GEN and STAMP from the program's output.
build_verified() {
    build "$1" "$2"
    read -r STRICT GEN STAMP <<< "$("$1/target/debug/app")"
}

# The outcome verification logged for `$2 $3` (a check: sources, reads or outputs) in scenario $1.
verified() {
    sed -nE "s/^Tuist Cargo cache: verified $2 $3: ([a-z-]+).*/\\1/p" "$ROOT/$1.log" | tail -1
}

summary() {
    sed -nE 's/^Tuist Cargo cache: verified ([0-9]+) hits by running them, ([0-9]+) divergent$/\1 \2/p' "$ROOT/$1.log" | tail -1
}

a=$(checkout a)
build_verified "$a" cold
expect cold "11 320" "$STRICT $GEN"
cold=$STAMP

build_verified "$a" warm
expect warm "hit hit hit" "$(task warm strict) $(task warm gen) $(task warm clock)"
expect "warm: the clock run must be restored" "$cold" "$STAMP"

# Inputs: a strict hit is checked by a dep-info run of rustc and still restored; recorded units and build-script runs
# run recorded and compare what they read with the read set that keyed them. A verified unit's outputs are fresh, so
# the clock run's new stamp makes `clock` and `app` ordinary misses, as an uncached build would compile them.
TUIST_CARGO_VERIFY=always build_verified "$a" inputs
expect inputs "11 320" "$STRICT $GEN"
expect "inputs: strict sources" ok "$(verified inputs strict sources)"
expect "inputs: the agreeing strict hit is restored" hit "$(task inputs strict)"
for unit in gen macros "gen build_script_build" "clock build_script_build" "gen build script run" "clock build script run"; do
    expect "inputs: $unit reads" ok "$(verified inputs "$unit" reads)"
done
expect "inputs: units after the fresh clock run" "miss miss" "$(task inputs clock) $(task inputs app)"
expect "inputs: verified hits" "6 0" "$(summary inputs)"

# Verification stores nothing: the next build restores the cold run, not the one verification reran.
build_verified "$a" after-inputs
expect after-inputs "hit hit hit" "$(task after-inputs strict) $(task after-inputs gen) $(task after-inputs clock)"
expect "after-inputs: the cache must still hold the cold run" "$cold" "$STAMP"
logged after-inputs "verified" && fail "after-inputs: verification ran without being asked for"

# Outputs: every hit compiles in place and is compared with its stored entry. Only the clock run may differ, and must;
# what embeds its stamp is keyed by it, so misses.
TUIST_CARGO_VERIFY_RECOMPILE=always build_verified "$a" outputs
expect outputs "11 320" "$STRICT $GEN"
[ "$STAMP" != "$cold" ] || fail "outputs: the clock run must rerun, not restore"
expect "outputs: strict" ok "$(verified outputs strict outputs)"
expect "outputs: gen build script run" ok "$(verified outputs "gen build script run" outputs)"
for unit in gen macros "gen build_script_build" "clock build_script_build"; do
    case "$(verified outputs "$unit" outputs)" in ok | path-debug) ;; *) fail "outputs: $unit must match, see $ROOT/outputs.log" ;; esac
done
expect "outputs: clock build script run" content "$(verified outputs "clock build script run" outputs)"
expect "outputs: units after the fresh clock run" "miss miss" "$(task outputs clock) $(task outputs app)"
expect "outputs: verified hits" "7 1" "$(summary outputs)"

build_verified "$a" after-outputs
expect "after-outputs: the cache must still hold the cold run" "$cold" "$STAMP"

# Incremental codegen names its units after the session, so two incremental compilations of the same sources write
# different objects and rlibs. Recompiling them compares metadata and dep-info, which must still agree, and says so.
# Cargo folds the incremental setting into each workspace crate's `-C metadata`, so these entries live in a cache of
# their own.
export XDG_CACHE_HOME="$ROOT/xdg-incremental" CARGO_INCREMENTAL=1
build_verified "$a" incremental-cold
TUIST_CARGO_VERIFY_RECOMPILE=always build_verified "$a" incremental
expect incremental "11 320" "$STRICT $GEN"
# Not `gen`: it keys the proc macro's freshly linked dylib, whose debug map names this session's objects, so it misses
# as in an uncached incremental build.
for unit in strict macros "gen build_script_build"; do
    expect "incremental: $unit" ok "$(verified incremental "$unit" outputs)"
done
logged incremental "verified strict outputs: ok (incremental codegen is not reproducible" \
    || fail "incremental: the strict comparison must say it compared metadata only, see $ROOT/incremental.log"
expect "incremental: divergences" 1 "$(summary incremental | cut -d' ' -f2)"

printf 'verify: ok\n'
