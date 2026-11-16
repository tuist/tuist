#!/usr/bin/env bash
# Metadata-only compilations (`cargo check`, `cargo clippy`) through the public `tuist cargo` command, offline and
# local-only.
#
# `m` is a workspace library with a rustc warning and a Clippy warning, behind `dep`, another workspace library: a warm
# check restores `dep`, certifies its metadata and restores `m` against it, replaying the warning; without its list, a
# served hook restores `m` from its dep-info while rustc runs. Check entries never serve a build. `ext` lives outside
# the workspace, so `cargo clippy` compiles it with rustc and it keeps its check entry. Clippy compilations have entries
# of their own, replay Clippy's warnings, and miss when Clippy's arguments, its configuration file or the package
# manifest change; enabling the `cargo` lints, which run `cargo metadata`, is never
# cached. `uses` calls a workspace proc macro, so only the read recorder (arm64 macOS, x86_64 and aarch64 Linux)
# caches it, for both commands.
# Expected values are computed here.
set -euo pipefail
. "$(dirname "$0")/common.sh" check
export TUIST_PROJECT=fixture/check
ws="$ROOT/ws"

write() {
    mkdir -p "$(dirname "$ROOT/$1")"
    printf "$2" > "$ROOT/$1"
}

# Runs `tuist cargo $2` in the workspace from a fresh target as scenario $1, with any further Cargo arguments, and sets
# the decisions for `dep`, `m`, `ext` and `uses`.
cargo_run() {
    local scenario=$1 command=$2
    shift 2
    rm -rf "$ws/target"
    (cd "$ws" && "$BINARY" cargo "$command" --offline "$@") > /dev/null 2> "$ROOT/$scenario.log" \
        || fail "$scenario: cargo $command failed, see $ROOT/$scenario.log"
    DEP=$(task "$scenario" dep) M=$(task "$scenario" m) EXT=$(task "$scenario" ext) USES=$(task "$scenario" uses)
    printf '%s: dep=%s m=%s ext=%s uses=%s\n' "$scenario" "$DEP" "$M" "$EXT" "$USES"
}

write ws/Cargo.toml '[workspace]\nmembers = ["dep", "m", "mac", "uses", "app"]\nresolver = "2"\n'
write ws/dep/Cargo.toml '[package]\nname = "dep"\nversion = "0.1.0"\nedition = "2021"\n'
write ws/dep/src/lib.rs 'pub const BASE: u64 = 40;\n'
write ext/Cargo.toml '[package]\nname = "ext"\nversion = "0.1.0"\nedition = "2021"\n'
write ext/src/lib.rs 'pub const ONE: u64 = 1;\n'
write ws/m/Cargo.toml '[package]\nname = "m"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\ndep = { path = "../dep" }\next = { path = "../../ext" }\n'
write ws/m/src/lib.rs 'mod a;\nfn unused() {}\npub fn empty(values: &[u64]) -> bool { values.len() == 0 }\npub fn add(left: u64, right: u64) -> u64 { left + right }\npub fn value() -> u64 { dep::BASE + ext::ONE + a::A }\n'
write ws/m/src/a.rs 'pub const A: u64 = 1;\n'
write ws/mac/Cargo.toml '[package]\nname = "mac"\nversion = "0.1.0"\nedition = "2021"\n[lib]\nproc-macro = true\n'
write ws/mac/src/lib.rs 'use proc_macro::TokenStream;\n#[proc_macro]\npub fn answer(_: TokenStream) -> TokenStream { "42".parse().unwrap() }\n'
write ws/uses/Cargo.toml '[package]\nname = "uses"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nmac = { path = "../mac" }\n'
write ws/uses/src/lib.rs 'pub fn answer() -> u64 { mac::answer!() }\n'
write ws/app/Cargo.toml '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nm = { path = "../m" }\nuses = { path = "../uses" }\n'
write ws/app/src/main.rs 'fn main() { println!("{}", m::value() + uses::answer() + u64::from(m::empty(&[])) + m::add(0, 0)); }\n'
(cd "$ws" && cargo generate-lockfile --offline 2> /dev/null)

# Where the read recorder runs, the proc macro's user is recorded; elsewhere it stays uncached.
recorded=
case "$(uname -sm)" in "Darwin arm64" | "Linux x86_64" | "Linux aarch64") recorded=hit ;; esac
dead_code='function `unused` is never used'
len_zero='length comparison to zero'

cargo_run check-cold check
expect check-cold "miss miss miss" "$DEP $M $EXT"
logged check-cold "$dead_code" || fail "check-cold: the warning was not shown"
cargo_run check-warm check
expect check-warm "hit hit hit $recorded" "$DEP $M $EXT $USES"
logged check-warm "$dead_code" || fail "check-warm: the restored crate's warning was not replayed"
logged check-warm "$len_zero" && fail "check-warm: rustc showed a Clippy warning"

# Without its remembered list, a session's hook keys `m` from its dep-info while rustc runs and restores the check entry,
# whose outputs are only metadata and dep-info. Elsewhere `m` compiles first.
rm -rf "$XDG_CACHE_HOME"/tuist/Cargo/*/reads
early=miss
[ "$(uname -s)" != Darwin ] || early=hit
cargo_run check-forgotten-list check
expect check-forgotten-list "$early" "$M"
expect check-forgotten-list-warnings 1 "$(grep -cF "$dead_code" "$ROOT/check-forgotten-list.log")"

# A check's metadata never stands in for a build's.
cargo_run build-after-check build
expect build-after-check "miss miss miss" "$DEP $M $EXT"
expect build-after-check-output 85 "$("$ws/target/debug/app")"

cargo_run clippy-cold clippy
expect clippy-cold "miss hit" "$M $EXT"
logged clippy-cold "$len_zero" || fail "clippy-cold: Clippy's warning was not shown"
cargo_run clippy-warm clippy
expect clippy-warm "hit hit hit $recorded" "$DEP $M $EXT $USES"
logged clippy-warm "$len_zero" || fail "clippy-warm: the restored crate's Clippy warning was not replayed"
logged clippy-warm "$dead_code" || fail "clippy-warm: the restored crate's rustc warning was not replayed"

# What Clippy reads besides its arguments: `CLIPPY_ARGS`, its configuration file and the package manifest.
cargo_run clippy-args clippy -- -W clippy::pedantic
expect clippy-args miss "$M"
cargo_run clippy-args-warm clippy -- -W clippy::pedantic
expect clippy-args-warm hit "$M"
write ws/clippy.toml 'too-many-arguments-threshold = 1\n'
cargo_run clippy-configuration clippy
expect clippy-configuration miss "$M"
logged clippy-configuration 'this function has too many arguments (2/1)' \
    || fail "clippy-configuration: the configuration was not applied"
cargo_run clippy-configuration-warm clippy
expect clippy-configuration-warm hit "$M"
logged clippy-configuration-warm 'this function has too many arguments (2/1)' \
    || fail "clippy-configuration-warm: the configured warning was not replayed"
write ws/clippy.toml 'too-many-arguments-threshold = 2\n'
cargo_run clippy-configuration-edit clippy
expect clippy-configuration-edit miss "$M"
logged clippy-configuration-edit 'too many arguments' && fail "clippy-configuration-edit: an earlier result was replayed"
printf '# A comment changes no variable Cargo sets.\n' >> "$ws/m/Cargo.toml"
cargo_run clippy-manifest clippy
expect clippy-manifest miss "$M"
cargo_run check-manifest check
expect check-manifest hit "$M"

# The `cargo` lints run `cargo metadata`, which reads every manifest and the lockfile.
cargo_run clippy-cargo-lints clippy -- -W clippy::cargo
cargo_run clippy-cargo-lints-warm clippy -- -W clippy::cargo
[ "$M" != hit ] || fail "clippy-cargo-lints-warm: a compilation that ran cargo metadata was restored"
# Joined flags and hyphenated lint names, which rustc reads as underscores.
cargo_run clippy-cargo-joined clippy -- -Wclippy::multiple-crate-versions
cargo_run clippy-cargo-joined-warm clippy -- -Wclippy::multiple-crate-versions
[ "$M" != hit ] || fail "clippy-cargo-joined-warm: a compilation that ran cargo metadata was restored"
# The same lints, enabled by the crate itself.
write ws/dep/src/lib.rs '#![warn(clippy::cargo)]\npub const BASE: u64 = 40;\n'
cargo_run clippy-cargo-attribute clippy
cargo_run clippy-cargo-attribute-warm clippy
[ "$DEP" != hit ] || fail "clippy-cargo-attribute-warm: a compilation that ran cargo metadata was restored"
