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
    // Through `PATH`, as cc-rs finds it: the session's `cc` shim must keep the compiler recorded.
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
build_linked "$l" linked-warm
logged linked-warm "restored build-script run" || fail "linked-warm: the build-script runs were not restored"
expect linked-warm "1 1 hit hit" "$LINKED $(task linked-warm app) $(task linked-warm natbin)"
for package in foosys natbin; do printf 'int foo(void) { return 2; }\n' > "$l/$package/foo.c"; done
build_linked "$l" linked-archive
expect linked-archive "2 2" "$LINKED"

# Protected programs such as `/usr/bin/git` never load the recorder, so what they read is unknown; a run that asks
# one is keyed by what it printed instead, re-run at lookup. `stamp` is a proc macro that embeds `git describe`, as
# bat's `git_version!` does, and `rev`'s build script records `git rev-parse HEAD`. A new commit must reach both.
queried() {
    local path="$ROOT/$1/ws"
    mkdir -p "$path/stamp/src" "$path/rev/src" "$path/app/src"
    printf '[workspace]\nmembers = ["stamp", "rev", "app"]\nresolver = "2"\n' > "$path/Cargo.toml"
    printf '[package]\nname = "stamp"\nversion = "0.1.0"\nedition = "2021"\n[lib]\nproc-macro = true\n' \
        > "$path/stamp/Cargo.toml"
    cat > "$path/stamp/src/lib.rs" << 'RUST'
extern crate proc_macro;
#[proc_macro]
pub fn describe(_: proc_macro::TokenStream) -> proc_macro::TokenStream {
    let output = std::process::Command::new("git").args(["describe", "--always", "--dirty"]).output().unwrap();
    format!("{:?}", String::from_utf8(output.stdout).unwrap().trim()).parse().unwrap()
}
RUST
    printf '[package]\nname = "rev"\nversion = "0.1.0"\nedition = "2021"\n' > "$path/rev/Cargo.toml"
    cat > "$path/rev/build.rs" << 'RUST'
fn main() {
    let output = std::process::Command::new("/usr/bin/git").args(["rev-parse", "HEAD"]).output().unwrap();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(format!("{out}/rev.txt"), String::from_utf8(output.stdout).unwrap().trim()).unwrap();
}
RUST
    printf 'pub const REV: &str = include_str!(concat!(env!("OUT_DIR"), "/rev.txt"));\n' > "$path/rev/src/lib.rs"
    printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nstamp = { path = "../stamp" }\nrev = { path = "../rev" }\n' \
        > "$path/app/Cargo.toml"
    printf 'fn main() { println!("{} {}", stamp::describe!(), rev::REV); }\n' > "$path/app/src/main.rs"
    printf 'target\n' > "$path/.gitignore"
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null && git init -q && git add -A \
        && git -c user.name=t -c user.email=t@t commit -qm one)
    printf '%s' "$path"
}

build_queried() {
    build "$1" "$2"
    QUERIED=$("$1/target/debug/app")
    printf '%s: %s app=%s script=%s\n' "$2" "$QUERIED" "$(task "$2" app)" "$(task "$2" build_script_build)"
}

expected_query() {
    printf '%s %s' "$(git -C "$1" rev-parse --short HEAD)" "$(git -C "$1" rev-parse HEAD)"
}

q=$(queried queried)
build_queried "$q" query-cold
expect query-cold "$(expected_query "$q")" "$QUERIED"
build_queried "$q" query-warm
expect query-warm "$(expected_query "$q") hit" "$QUERIED $(task query-warm app)"
logged query-warm "restored build-script run" || fail "query-warm: the build-script run was not restored"
git -C "$q" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two
build_queried "$q" query-commit
expect query-commit "$(expected_query "$q") miss" "$QUERIED $(task query-commit app)"
build_queried "$q" query-commit-warm
expect query-commit-warm "$(expected_query "$q") hit" "$QUERIED $(task query-commit-warm app)"

# `swiftc` and `codesign` run from protected `xcrun` shims too. A build script that compiles a Swift helper and signs
# it ad hoc, as mise's does, is keyed by the helper's source and the Xcode, SDK and OS builds; a changed source must
# rerun it. The script stamps its output like `base`'s, so a restored run keeps the cold stamp.
tools() {
    local path="$ROOT/$1/ws"
    mkdir -p "$path/helper/src" "$path/app/src"
    printf '[workspace]\nmembers = ["helper", "app"]\nresolver = "2"\n' > "$path/Cargo.toml"
    printf '[package]\nname = "helper"\nversion = "0.1.0"\nedition = "2021"\n' > "$path/helper/Cargo.toml"
    printf 'print(41 + 1)\n' > "$path/helper/helper.swift"
    printf '#include "digit.h"\n#include <stdio.h>\nint main(void) { printf("%%d\\n", DIGIT); return 0; }\n' \
        > "$path/helper/native.c"
    printf '#define DIGIT 7\n' > "$path/helper/digit.h"
    cat > "$path/helper/build.rs" << 'RUST'
fn main() {
    println!("cargo::rerun-if-changed=helper.swift");
    println!("cargo::rerun-if-changed=native.c");
    println!("cargo::rerun-if-changed=digit.h");
    let out = std::env::var("OUT_DIR").unwrap();
    let helper = format!("{out}/helper");
    let run = |program: &str, arguments: &[&str]| {
        let output = std::process::Command::new(program).args(arguments).output().unwrap();
        assert!(output.status.success(), "{program}: {}", String::from_utf8_lossy(&output.stderr));
        String::from_utf8(output.stdout).unwrap()
    };
    run("swiftc", &["-O", "helper.swift", "-o", &helper]);
    // Through `PATH`, as cc-rs runs it: the session's `cc` shim must keep the compiler recorded.
    run("cc", &["-O2", "native.c", "-o", &format!("{out}/native")]);
    let native = run(&format!("{out}/native"), &[]);
    run("/usr/bin/codesign", &["--force", "--sign", "-", &helper]);
    let value = run(&helper, &[]);
    // As cc-rs asks for the SDK: a `PATH` of its own makes Rust fork and search with `execvp`, and the query runs
    // with an environment the script changed.
    let sdk = std::process::Command::new("xcrun").arg("--show-sdk-path")
        .env("PATH", std::env::var("PATH").unwrap()).env("TUIST_FIXTURE_QUERY", "1").output().unwrap();
    assert!(sdk.status.success() && sdk.stdout.starts_with(b"/"));
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    std::fs::write(format!("{out}/value.txt"), format!("{}{} {stamp}", value.trim(), native.trim())).unwrap();
}
RUST
    printf 'pub const VALUE: &str = include_str!(concat!(env!("OUT_DIR"), "/value.txt"));\n' > "$path/helper/src/lib.rs"
    printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nhelper = { path = "../helper" }\n' \
        > "$path/app/Cargo.toml"
    printf 'fn main() { println!("{}", helper::VALUE); }\n' > "$path/app/src/main.rs"
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null)
    printf '%s' "$path"
}

build_tools() {
    # The protected shim runs the selected Xcode's compiler whatever else `PATH` holds.
    PATH="/usr/bin:$PATH" build "$1" "$2"
    read -r VALUE STAMP <<< "$("$1/target/debug/app")"
    printf '%s: value=%s app=%s\n' "$2" "$VALUE" "$(task "$2" app)"
}

t=$(tools tools)
build_tools "$t" tools-cold
expect tools-cold 427 "$VALUE"
cold=$STAMP
build_tools "$t" tools-warm
logged tools-warm "restored build-script run" || fail "tools-warm: the build-script run was not restored"
expect "tools-warm: the build-script run must be restored, not rerun" "427 $cold hit" "$VALUE $STAMP $(task tools-warm app)"
printf 'print(41 + 2)\n' > "$t/helper/helper.swift"
build_tools "$t" tools-source
expect tools-source 437 "$VALUE"
[ "$STAMP" != "$cold" ] || fail "tools-source: the build script must rerun"
# The header only the compiler reads, never named in its arguments.
printf '#define DIGIT 8\n' > "$t/helper/digit.h"
build_tools "$t" tools-header
expect tools-header 438 "$VALUE"
