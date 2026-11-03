#!/usr/bin/env bash
# Recorded compilations and build-script runs through the public `tuist cargo` command, offline and local-only.
#
# The workspace has a proc macro reading an undeclared file and an environment variable, a library with a build
# script that uses it, and an application whose link is recorded as well, as is the build script's. Strict admission
# rejects the library (it consumes a proc macro), so only the read recorder can cache it. The build script stamps its
# output with the current time: a restored run keeps the cold build's stamp, and a rerun gets a new one. Every expected
# value is computed here, not taken from a build.
set -euo pipefail
[ "$(uname -sm)" = "Darwin arm64" ] || { echo "The read recorder supports arm64 macOS only" >&2; exit 1; }
. "$(dirname "$0")/common.sh" recorded
export TUIST_PROJECT=fixture/recorded

checkout() {
    local path="$ROOT/$1/ws"
    mkdir -p "$path/macros/src" "$path/base/src" "$path/app/src"
    printf '[workspace]\nmembers = ["macros", "base", "app"]\nresolver = "2"\n' > "$path/Cargo.toml"
    printf '7\n' > "$path/value.txt"
    printf '[package]\nname = "macros"\nversion = "0.1.0"\nedition = "2021"\n[lib]\nproc-macro = true\n' \
        > "$path/macros/Cargo.toml"
    cat > "$path/macros/src/lib.rs" << 'RUST'
extern crate proc_macro;
#[proc_macro]
pub fn value(_: proc_macro::TokenStream) -> proc_macro::TokenStream {
    let extra: u64 = std::env::var("MACRO_EXTRA").ok().and_then(|v| v.parse().ok()).unwrap_or(0);
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../value.txt");
    let base: u64 = std::fs::read_to_string(path).unwrap().trim().parse().unwrap();
    (base + extra).to_string().parse().unwrap()
}
RUST
    printf '[package]\nname = "base"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nmacros = { path = "../macros" }\n' \
        > "$path/base/Cargo.toml"
    printf '100\n' > "$path/base/generated.txt"
    cat > "$path/base/build.rs" << 'RUST'
fn main() {
    println!("cargo::rerun-if-changed=generated.txt");
    let input = std::fs::read_to_string("generated.txt").unwrap();
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(
        format!("{out}/generated.rs"),
        format!("pub const GENERATED: u64 = {};\npub const STAMP: u128 = {stamp};\n", input.trim()),
    ).unwrap();
}
RUST
    printf 'include!(concat!(env!("OUT_DIR"), "/generated.rs"));\npub fn base() -> u64 { macros::value!() + GENERATED }\n' \
        > "$path/base/src/lib.rs"
    printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nbase = { path = "../base" }\n' \
        > "$path/app/Cargo.toml"
    printf 'fn main() { println!("{} {}", base::base(), base::STAMP); }\n' > "$path/app/src/main.rs"
    # Recording shares the dependency-unit cache's scope, which is keyed by the lockfile.
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null)
    printf '%s' "$path"
}

# Builds scenario $2 in $1 and sets VALUE, STAMP and the per-crate decisions.
build_recorded() {
    build "$1" "$2"
    read -r VALUE STAMP <<< "$("$1/target/debug/app")"
    APP=$(task "$2" app) BASE=$(task "$2" base) MACROS=$(task "$2" macros) SCRIPT=$(task "$2" build_script_build)
    printf '%s: value=%s app=%s base=%s macros=%s build_script_build=%s\n' "$2" "$VALUE" "$APP" "$BASE" "$MACROS" "$SCRIPT"
}

a=$(checkout a)
build_recorded "$a" cold
expect cold "107 miss" "$VALUE $BASE"
cold=$STAMP

build_recorded "$a" warm
expect warm "107 hit hit" "$VALUE $BASE $MACROS"
# The linked program is restored too, executable; every later scenario runs it, so a stale one fails its value.
expect warm hit "$APP"
# The build script's compilation is restored, then shimmed like a compiled one, so its run is restored as well.
expect warm hit "$SCRIPT"
expect "warm: the build-script run must be restored, not rerun" "$cold" "$STAMP"

printf '9\n' > "$a/value.txt"
build_recorded "$a" macro-file
expect macro-file "109 miss $cold" "$VALUE $BASE $STAMP"

MACRO_EXTRA=5 build_recorded "$a" macro-env
expect macro-env "114 miss" "$VALUE $BASE"

MACRO_EXTRA=5 build_recorded "$a" macro-env-warm
expect macro-env-warm "114 hit" "$VALUE $BASE"

printf '200\n' > "$a/base/generated.txt"
build_recorded "$a" script-input
expect script-input "209 miss" "$VALUE $BASE"
[ "$STAMP" != "$cold" ] || fail "script-input: the build script must rerun"

# The same sources at another path: the macro embeds its manifest directory, so its users may miss, but the program
# must still read the moved checkout's files.
b=$(checkout b/nested)
printf '3\n' > "$b/value.txt"
build_recorded "$b" moved
expect moved 103 "$VALUE"

# Native code reaches a link the recorder cannot see: `natbin` links an archive its build script leaves in a search
# directory, and `app` links one bundled into `foosys`, two levels down, whose change leaves `mid` unchanged. A new
# archive must relink both, never restore the binaries linked with the old one.
linked() {
    local path="$ROOT/$1/ws"
    mkdir -p "$path/foosys/src" "$path/mid/src" "$path/app/src" "$path/natbin/src"
    printf '[workspace]\nmembers = ["foosys", "mid", "app", "natbin"]\nresolver = "2"\n' > "$path/Cargo.toml"
    cat > "$path/archive.rs" << 'RUST'
fn main() {
    let out = std::env::var("OUT_DIR").unwrap();
    println!("cargo::rerun-if-changed=foo.c");
    let run = |program: &str, arguments: &[&str]| {
        // As cc-rs does, so the archive is the same bytes every run.
        let status = std::process::Command::new(program).args(arguments).env("ZERO_AR_DATE", "1").status();
        assert!(status.unwrap().success())
    };
    // Through `PATH`, as cc-rs finds it, so the session's `cc` shim compiles it.
    run("cc", &["-c", "foo.c", "-o", &format!("{out}/foo.o")]);
    let _ = std::fs::remove_file(format!("{out}/libfoo.a"));
    run("/usr/bin/ar", &["rcs", &format!("{out}/libfoo.a"), &format!("{out}/foo.o")]);
    println!("cargo::rustc-link-search=native={out}");
    println!("cargo::rustc-link-lib=static=foo");
}
RUST
    for package in foosys natbin; do
        printf '[package]\nname = "%s"\nversion = "0.1.0"\nedition = "2021"\nbuild = "../archive.rs"\n' "$package" \
            > "$path/$package/Cargo.toml"
        printf 'int foo(void) { return 1; }\n' > "$path/$package/foo.c"
    done
    printf 'links = "foo"\n' >> "$path/foosys/Cargo.toml"
    printf 'extern "C" { pub fn foo() -> i32; }\n' > "$path/foosys/src/lib.rs"
    printf 'fn main() { println!("{}", unsafe { foo() }); }\nextern "C" { fn foo() -> i32; }\n' > "$path/natbin/src/main.rs"
    printf '[package]\nname = "mid"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nfoosys = { path = "../foosys" }\n' \
        > "$path/mid/Cargo.toml"
    printf 'pub fn value() -> i32 { unsafe { foosys::foo() } }\n' > "$path/mid/src/lib.rs"
    printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nmid = { path = "../mid" }\n' \
        > "$path/app/Cargo.toml"
    printf 'fn main() { println!("{}", mid::value()); }\n' > "$path/app/src/main.rs"
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null)
    printf '%s' "$path"
}

build_linked() {
    build "$1" "$2"
    LINKED="$("$1/target/debug/app") $("$1/target/debug/natbin")"
    printf '%s: app natbin=%s app=%s natbin=%s\n' "$2" "$LINKED" "$(task "$2" app)" "$(task "$2" natbin)"
}

l=$(linked linked)
build_linked "$l" linked-cold
expect linked-cold "1 1" "$LINKED"
logged linked-cold "miss compiler" || fail "linked-cold: the served cc shim made no cache decision"
build_linked "$l" linked-warm
logged linked-warm "hit compiler" || fail "linked-warm: the C compilation was not restored"
expect linked-warm "1 1 hit hit" "$LINKED $(task linked-warm app) $(task linked-warm natbin)"
for package in foosys natbin; do printf 'int foo(void) { return 2; }\n' > "$l/$package/foo.c"; done
build_linked "$l" linked-archive
expect linked-archive "2 2" "$LINKED"
