#!/usr/bin/env bash
# Remembered source lists through the public `tuist cargo` command, offline and local-only.
#
# Strict admission keys a path library by the sources an earlier compilation read, without running rustc to discover
# them. The library has a warning, which a hit must replay. A list that no longer matches must never hide a change: a
# new submodule misses and is cached on that same build, an edited submodule misses, and a file that makes module
# resolution ambiguous fails compilation instead of hitting. A library whose sources strict admission refuses
# (`#[link]`) learns that only after rustc ran: that same build must record its reads, so the next build hits.
# Expected values are computed here.
set -euo pipefail
. "$(dirname "$0")/common.sh" sources
export TUIST_PROJECT=fixture/sources
ws="$ROOT/ws"

write() {
    mkdir -p "$(dirname "$ws/$1")"
    printf "$2" > "$ws/$1"
}

# Builds scenario $1 and sets OUTPUT (empty when the build failed) and the decisions for `m` and `linked`.
build_sources() {
    run_build "$ws" "$1"
    OUTPUT=
    if [ "$STATUS" = 0 ]; then
        OUTPUT=$("$ws/target/debug/app")
        logged "$1" 'function `unused` is never used' || fail "$1: the warning was not shown"
    fi
    M=$(task "$1" m) LINKED=$(task "$1" linked)
    printf '%s: exit=%s output=%s m=%s linked=%s\n' "$1" "$STATUS" "$OUTPUT" "$M" "$LINKED"
}

write Cargo.toml '[workspace]\nmembers = ["m", "linked", "app"]\nresolver = "2"\n'
write linked/Cargo.toml '[package]\nname = "linked"\nversion = "0.1.0"\nedition = "2021"\n'
# In a submodule, as in `libc`: the root source alone is admissible, so the compilation is deferred.
write linked/src/lib.rs 'mod sys;\npub fn magnitude() -> i32 { unsafe { sys::abs(-4) } }\n'
write linked/src/sys.rs '#[link(name = "c")]\nextern "C" { pub fn abs(value: i32) -> i32; }\n'
write m/Cargo.toml '[package]\nname = "m"\nversion = "0.1.0"\nedition = "2021"\n'
write m/src/lib.rs 'mod a;\nfn unused() {}\npub fn value() -> u64 { a::A }\n'
write m/src/a.rs 'pub const A: u64 = 1;\n'
write app/Cargo.toml '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nm = { path = "../m" }\nlinked = { path = "../linked" }\n'
write app/src/main.rs 'fn main() { println!("{}", m::value() + linked::magnitude() as u64 - 4); }\n'
(cd "$ws" && cargo generate-lockfile --offline 2> /dev/null)

# The read recorder supports arm64 macOS only; elsewhere the refused library stays uncached.
warm_linked=
[ "$(uname -sm)" != "Darwin arm64" ] || warm_linked=hit

build_sources cold
expect cold "0 1 miss miss" "$STATUS $OUTPUT $M $LINKED"
build_sources warm
expect warm "0 1 hit $warm_linked" "$STATUS $OUTPUT $M $LINKED"

write m/src/a.rs 'mod b;\npub const A: u64 = b::B + 1;\n'
write m/src/a/b.rs 'pub const B: u64 = 10;\n'
build_sources new-submodule
expect new-submodule "0 11 miss" "$STATUS $OUTPUT $M"
build_sources new-submodule-warm
expect new-submodule-warm "0 11 hit" "$STATUS $OUTPUT $M"

write m/src/a/b.rs 'pub const B: u64 = 20;\n'
build_sources submodule-edit
expect submodule-edit "0 21 miss" "$STATUS $OUTPUT $M"

write m/src/a/mod.rs 'pub const A: u64 = 99;\n'
build_sources ambiguous
[ "$STATUS" != 0 ] || fail "ambiguous: an ambiguous module must fail compilation, not restore an earlier result"
