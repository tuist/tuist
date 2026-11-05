#!/usr/bin/env bash
# Dependency-unit reuse through the public `tuist cargo` command, offline and local-only.
#
# cold:     the first build publishes the registry dependency's unit.
# moved:    the same project at another path restores it; Cargo compiles only the application.
# snapshot: the same again restores the absent profile from the snapshot the previous restoration left.
# tampered: a snapshot whose files were rewritten is discarded, not restored.
# foreign:  so is a snapshot holding a file its record does not list.
# lockfile: a different `Cargo.lock` (an added path dependency) still restores the unit: the manifest is not keyed by
#           the lockfile, and Cargo's fingerprints decide what a build uses.
# flags:    different rustflags in `.cargo/config.toml` miss, and Cargo compiles the dependency again.
# native:   a `-sys` crate's build-script run that names its Cargo-home sources is restored in another checkout.
# corrupt:  with the stored rlib corrupted and no snapshot, the unit is not restored and Cargo compiles it again.
# Every program must print 42.
set -euo pipefail
. "$(dirname "$0")/common.sh" units
export TUIST_PROJECT=fixture/units

checkout() {
    local path="$ROOT/$1/project"
    mkdir -p "$path"
    cp "$FIXTURE/Cargo.toml" "$FIXTURE/Cargo.lock" "$path/"
    cp -R "$FIXTURE/src" "$path/src"
    if [ -n "${2-}" ]; then
        mkdir "$path/.cargo"
        printf '%s' "$2" > "$path/.cargo/config.toml"
    fi
    printf '%s' "$path"
}

build_units() {
    build "$1" "$2" --locked
    expect "$2: program output" 42 "$("$1/target/debug/tuist-cargo-cache-smoke")"
    COMPILED=$(compiled "$2")
    RESTORED=$(sed -nE 's/.*restored ([0-9]+) of.*/\1/p' "$ROOT/$2.log" | head -1)
    RESTORED=${RESTORED:-0}
    printf '%s: compiled=[%s] restored=%s\n' "$2" "$COMPILED" "$RESTORED"
}

# The project's own Cargo configuration must not tie keys to the checkout's path.
shared=$'[term]\nverbose = false\n'
a=$(checkout a "$shared")
build_units "$a" cold
expect cold "itoa tuist-cargo-cache-smoke" "$COMPILED"
expect cold 0 "$RESTORED"

b=$(checkout b/nested "$shared")
build_units "$b" moved
expect moved tuist-cargo-cache-smoke "$COMPILED"
[ "$RESTORED" -ge 1 ] || fail "moved: nothing restored"

build_units "$b" snapshot
expect snapshot tuist-cargo-cache-smoke "$COMPILED"
logged snapshot "from a snapshot" || fail "snapshot: not restored from the snapshot"

copies=("$ROOT"/xdg/tuist/Cargo/*/snapshots/*/deps/libitoa-*.rlib)
[ -f "${copies[0]}" ] || fail "tampered: no snapshot was saved"
corrupt "${copies[0]}"
build_units "$b" tampered
expect tampered tuist-cargo-cache-smoke "$COMPILED"
logged tampered discarding || fail "tampered: the changed snapshot was not discarded"
! logged tampered "from a snapshot" || fail "tampered: restored from a changed snapshot"

# A file the snapshot's record does not vouch for, such as the output of a Cargo that built in the profile while it
# was taken, must never reach a restored target.
snapshots=("$ROOT"/xdg/tuist/Cargo/*/snapshots/*/deps)
[ -d "${snapshots[0]}" ] || fail "foreign: no snapshot was saved again"
printf 'stale\n' > "${snapshots[0]}/foreign-0123456789abcdef.d"
build_units "$b" foreign
expect foreign tuist-cargo-cache-smoke "$COMPILED"
logged foreign discarding || fail "foreign: the snapshot holding a foreign file was not discarded"
[ ! -e "$b/target/debug/deps/foreign-0123456789abcdef.d" ] || fail "foreign: the foreign file was restored"

lock=$(checkout lock "$shared")
mkdir -p "$lock/extra/src"
printf '[package]\nname = "extra"\nversion = "0.1.0"\nedition = "2021"\n' > "$lock/extra/Cargo.toml"
printf 'pub fn unused() {}\n' > "$lock/extra/src/lib.rs"
printf 'extra = { path = "extra" }\n' >> "$lock/Cargo.toml"
(cd "$lock" && cargo generate-lockfile --offline 2> /dev/null)
! cmp -s "$lock/Cargo.lock" "$a/Cargo.lock" || fail "lockfile: the lockfile did not change"
build_units "$lock" lockfile
expect lockfile "extra tuist-cargo-cache-smoke" "$COMPILED"
[ "$RESTORED" -ge 1 ] || fail "lockfile: nothing restored"

c=$(checkout c $'[build]\nrustflags = ["-C", "overflow-checks=on"]\n')
build_units "$c" flags
expect flags "itoa tuist-cargo-cache-smoke" "$COMPILED"
expect flags 0 "$RESTORED"

# A `-sys` crate whose build script prints its include directory inside Cargo home: its run is bound to Cargo home,
# so another checkout on this machine restores it instead of running cc-rs again.
native() {
    local path="$ROOT/$1/project"
    mkdir -p "$path/src"
    printf '[package]\nname = "native"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nlzma-sys = "=0.1.20"\n' \
        > "$path/Cargo.toml"
    printf 'fn main() { println!("{}", unsafe { lzma_sys::lzma_version_number() } > 0); }\n' > "$path/src/main.rs"
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null)
    printf '%s' "$path"
}
n=$(native native-a)
build "$n" native-cold --locked
expect native-cold true "$("$n/target/debug/native")"
n=$(native native-b/nested)
build "$n" native-moved --locked
expect native-moved true "$("$n/target/debug/native")"
expect native-moved native "$(compiled native-moved)"

# Without a snapshot, so restoration reads the corrupted blob itself.
rm -rf "$ROOT"/xdg/tuist/Cargo/*/snapshots
rlibs=("$b"/target/debug/deps/libitoa-*.rlib)
digest=$(shasum -a 256 "${rlibs[0]}" | cut -d' ' -f1)
blobs=("$ROOT"/xdg/tuist/Cargo/*/blobs)
corrupt "${blobs[0]}/$digest"
build_units "$b" corrupt
expect corrupt "itoa tuist-cargo-cache-smoke" "$COMPILED"
