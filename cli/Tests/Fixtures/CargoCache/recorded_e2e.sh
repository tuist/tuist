#!/usr/bin/env bash
# Recorded compilations and build-script runs through the public `tuist cargo` command, offline and local-only.
#
# The workspace has a proc macro reading an undeclared file and an environment variable, a library with a build
# script that uses it, and an application whose link is recorded as well, as is the build script's. Strict admission
# rejects the library (it consumes a proc macro), so only the read recorder can cache it. The build script stamps its
# output with the current time: a restored run keeps the cold build's stamp, and a rerun gets a new one. Every expected
# value is computed here, not taken from a build.
set -euo pipefail
case "$(uname -sm)" in
"Darwin arm64" | "Linux x86_64" | "Linux aarch64") ;;
*) echo "The read recorder supports arm64 macOS and x86_64/aarch64 Linux only" >&2; exit 1 ;;
esac
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

# Whether scenario $1 in workspace $2 says $3 about a build-script run. A session without the hook server (Linux) runs
# scripts through `tuist cargo __script`, whose messages Cargo keeps with the run's stderr instead of printing them.
said() {
    logged "$1" "$3" || grep -rqsF --include=stderr -- "$3" "$2/target"
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
    // Through `PATH`, as cc-rs finds it: on macOS the session's `cc` shim must keep the compiler recorded, on Linux
    // the compiler loads the recorder itself.
    run("cc", &["-c", "foo.c", "-o", &format!("{out}/foo.o")]);
    let _ = std::fs::remove_file(format!("{out}/libfoo.a"));
    // A protected program modeled from its arguments on macOS; on Linux an ordinary recorded one.
    let ar = if cfg!(target_os = "macos") { "/usr/bin/ar" } else { "ar" };
    run(ar, &["rcs", &format!("{out}/libfoo.a"), &format!("{out}/foo.o")]);
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
said linked-warm "$l" "restored build-script run" || fail "linked-warm: the build-script runs were not restored"
expect linked-warm "1 1 hit hit" "$LINKED $(task linked-warm app) $(task linked-warm natbin)"
for package in foosys natbin; do printf 'int foo(void) { return 2; }\n' > "$l/$package/foo.c"; done
build_linked "$l" linked-archive
expect linked-archive "2 2" "$LINKED"

# Protected programs such as `/usr/bin/git` never load the recorder, so what they read is unknown; a run that asks
# one is keyed by what it printed instead, re-run at lookup. `stamp` is a proc macro that embeds `git describe`, as
# bat's `git_version!` does, and `rev`'s build script asks `git rev-parse --git-dir`, whose answer never changes, and
# reads the commit from `.git` itself. A new commit must reach both.
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
    // As `git_version!`, so Cargo reruns it when the repository changes.
    let git = format!("{}/../.git", std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let git = std::fs::canonicalize(git).unwrap().display().to_string();
    format!(
        "{{ include_bytes!({:?}); include_bytes!({:?}); {:?} }}",
        format!("{git}/index"), format!("{git}/logs/HEAD"), String::from_utf8(output.stdout).unwrap().trim()
    ).parse().unwrap()
}
RUST
    printf '[package]\nname = "rev"\nversion = "0.1.0"\nedition = "2021"\n' > "$path/rev/Cargo.toml"
    cat > "$path/rev/build.rs" << 'RUST'
// Asks git only where the repository is, whose answer never changes, and reads the commit from its files.
fn main() {
    let output = std::process::Command::new("/usr/bin/git").args(["rev-parse", "--git-dir"]).output().unwrap();
    let git = std::path::PathBuf::from(String::from_utf8(output.stdout).unwrap().trim());
    let head = std::fs::read_to_string(git.join("HEAD")).unwrap();
    let reference = head.trim().strip_prefix("ref: ").unwrap();
    let commit = std::fs::read_to_string(git.join(reference)).unwrap();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(format!("{out}/rev.txt"), commit.trim()).unwrap();
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
said query-warm "$q" "restored build-script run" || fail "query-warm: the build-script run was not restored"
git -C "$q" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two
build_queried "$q" query-commit
expect query-commit "$(expected_query "$q") miss" "$QUERIED $(task query-commit app)"
build_queried "$q" query-commit-warm
expect query-commit-warm "$(expected_query "$q") hit" "$QUERIED $(task query-commit-warm app)"
# A copy at another path: its `.git/index` names other inodes and times, but git describes the same commit.
mkdir -p "$ROOT/queried-moved"
cp -R "$q" "$ROOT/queried-moved/ws"
rm -rf "$ROOT/queried-moved/ws/target"
build_queried "$ROOT/queried-moved/ws" query-moved
expect query-moved "$(expected_query "$q") hit" "$QUERIED $(task query-moved app)"

# A program that does not load the recorder reads what it likes unseen: on Linux, a statically linked one has no loader
# to preload it into. A build script that runs one must rerun on every build, never restore, so a change to the file
# only that program reads reaches the application.
static_linked() {
    local path="$ROOT/$1/ws"
    mkdir -p "$path/helper/src" "$path/app/src"
    printf '[workspace]\nmembers = ["helper", "app"]\nresolver = "2"\n' > "$path/Cargo.toml"
    printf '[package]\nname = "helper"\nversion = "0.1.0"\nedition = "2021"\n' > "$path/helper/Cargo.toml"
    printf '#include <stdio.h>\nint main(void) { int v = 0; FILE *f = fopen("secret.txt", "r"); if (!f || fscanf(f, "%%d", &v) != 1) return 1; printf("%%d\\n", v); return 0; }\n' \
        > "$path/helper/reader.c"
    printf '5\n' > "$path/helper/secret.txt"
    cat > "$path/helper/build.rs" << 'RUST'
fn main() {
    println!("cargo::rerun-if-changed=reader.c");
    let out = std::env::var("OUT_DIR").unwrap();
    let reader = format!("{out}/reader");
    let status = std::process::Command::new("cc").args(["-static", "-O2", "reader.c", "-o", &reader]).status().unwrap();
    assert!(status.success());
    let output = std::process::Command::new(&reader).output().unwrap();
    assert!(output.status.success());
    std::fs::write(format!("{out}/value.txt"), String::from_utf8(output.stdout).unwrap().trim()).unwrap();
}
RUST
    printf 'pub const VALUE: &str = include_str!(concat!(env!("OUT_DIR"), "/value.txt"));\n' > "$path/helper/src/lib.rs"
    printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nhelper = { path = "../helper" }\n' \
        > "$path/app/Cargo.toml"
    printf 'fn main() { println!("{}", helper::VALUE); }\n' > "$path/app/src/main.rs"
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null)
    printf '%s' "$path"
}

# Linux programs read what macOS ones cannot hide from the recorder: a shell expands `$SHELL_VALUE` from the variables
# it took from `environ`, which no call reveals, and `/proc/self/cwd` names the reader's own working directory, which
# a lookup would resolve in another process. Neither is declared to Cargo. `shellenv` must rerun when the variable
# changes and still be restored when it does not; `procself` must never be restored.
environ_reads() {
    local path="$ROOT/$1/ws"
    mkdir -p "$path/shellenv/src" "$path/procself/src" "$path/app/src"
    printf '[workspace]\nmembers = ["shellenv", "procself", "app"]\nresolver = "2"\n' > "$path/Cargo.toml"
    for package in shellenv procself; do
        printf '[package]\nname = "%s"\nversion = "0.1.0"\nedition = "2021"\n' "$package" > "$path/$package/Cargo.toml"
        printf 'pub const VALUE: &str = include_str!(concat!(env!("OUT_DIR"), "/value.txt"));\n' \
            > "$path/$package/src/lib.rs"
    done
    cat > "$path/shellenv/build.rs" << 'RUST'
fn main() {
    println!("cargo::rerun-if-changed=build.rs");
    let output = std::process::Command::new("sh").args(["-c", "printf %s \"$SHELL_VALUE\""]).output().unwrap();
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(format!("{out}/value.txt"), format!("{} {stamp}", String::from_utf8(output.stdout).unwrap())).unwrap();
}
RUST
    printf '1\n' > "$path/procself/input.txt"
    cat > "$path/procself/build.rs" << 'RUST'
fn main() {
    println!("cargo::rerun-if-changed=build.rs");
    let value = std::fs::read_to_string("/proc/self/cwd/input.txt").unwrap();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(format!("{out}/value.txt"), value.trim()).unwrap();
}
RUST
    printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\nshellenv = { path = "../shellenv" }\nprocself = { path = "../procself" }\n' \
        > "$path/app/Cargo.toml"
    printf 'fn main() { println!("{} {}", shellenv::VALUE, procself::VALUE); }\n' > "$path/app/src/main.rs"
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null)
    printf '%s' "$path"
}

build_environ() {
    SHELL_VALUE=$3 build "$1" "$2"
    read -r SHELL_READ STAMP PROC_READ <<< "$("$1/target/debug/app")"
    printf '%s: shell=%s proc=%s\n' "$2" "$SHELL_READ" "$PROC_READ"
}

if [ "$(uname -s)" = Linux ]; then
    e=$(environ_reads environ)
    build_environ "$e" environ-cold 1
    expect environ-cold "1 1" "$SHELL_READ $PROC_READ"
    cold=$STAMP
    said environ-cold "$e" "read /proc/self/cwd/input.txt" \
        || fail "environ-cold: the run that read /proc/self/cwd must explain why it was not stored"
    build_environ "$e" environ-warm 1
    expect "environ-warm: the shell's run must be restored" "1 1 $cold" "$SHELL_READ $PROC_READ $STAMP"
    printf '2\n' > "$e/procself/input.txt"
    build_environ "$e" environ-changed 2
    expect environ-changed "2 2" "$SHELL_READ $PROC_READ"
    [ "$STAMP" != "$cold" ] || fail "environ-changed: the shell's build script must rerun"

    # Only where the system has a static C library.
    if printf 'int main(void) { return 0; }\n' | cc -static -x c - -o "$ROOT/static-probe" 2> /dev/null; then
        s=$(static_linked static)
        build "$s" static-cold
        expect static-cold 5 "$("$s/target/debug/app")"
        said static-cold "$s" "recorded processes" \
            || fail "static-cold: the run with a static program must explain why it was not stored"
        printf '6\n' > "$s/helper/secret.txt"
        build "$s" static-warm
        ! said static-warm "$s" "restored build-script run" || fail "static-warm: the build-script run must not be restored"
        expect static-warm 6 "$("$s/target/debug/app")"
    else
        printf 'Linux: skipping the static program scenario, which needs a static C library\n'
    fi
    printf 'Linux: skipping the macOS developer tools scenario\n'
    exit 0
fi

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
    // Through `PATH`, as cc-rs runs it: the session's `cc` shim must keep the compiler recorded. With debug
    // information, as mise's notification helper, which its library embeds.
    run("cc", &["-g", "-O2", "native.c", "-o", &format!("{out}/native")]);
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
    printf 'pub const VALUE: &str = include_str!(concat!(env!("OUT_DIR"), "/value.txt"));\npub static NATIVE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/native"));\n' \
        > "$path/helper/src/lib.rs"
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
said tools-warm "$t" "restored build-script run" || fail "tools-warm: the build-script run was not restored"
expect "tools-warm: the build-script run must be restored, not rerun" "427 $cold hit" "$VALUE $STAMP $(task tools-warm app)"
printf 'print(41 + 2)\n' > "$t/helper/helper.swift"
build_tools "$t" tools-source
expect tools-source 437 "$VALUE"
[ "$STAMP" != "$cold" ] || fail "tools-source: the build script must rerun"
# The header only the compiler reads, never named in its arguments.
printf '#define DIGIT 8\n' > "$t/helper/digit.h"
build_tools "$t" tools-header
expect tools-header 438 "$VALUE"
header=$STAMP
# The same sources at another path: the helper's debug information must not name the checkout, or the library that
# embeds it is bound to the first path and misses here.
m=$(tools tools-moved/nested)
printf 'print(41 + 2)\n' > "$m/helper/helper.swift"
printf '#define DIGIT 8\n' > "$m/helper/digit.h"
build_tools "$m" tools-moved
expect "tools-moved: the run must be restored and the library must hit" "438 $header hit" \
    "$VALUE $STAMP $(task tools-moved helper)"

# A linked binary's debug map names the objects lldb reads by absolute path, and a restored binary's names the
# checkout that built it. lldb must stop in a workspace library with its locals in place, in a restored binary whose
# producing checkout is gone, and after `cargo clean`: the binary is stored with a `.dSYM`.
debugged() {
    local path="$ROOT/$1/ws"
    mkdir -p "$path/dep/src" "$path/app/src"
    printf '[workspace]\nmembers = ["dep", "app"]\nresolver = "2"\n' > "$path/Cargo.toml"
    printf '[package]\nname = "dep"\nversion = "0.1.0"\nedition = "2021"\n' > "$path/dep/Cargo.toml"
    printf 'pub fn add(a: u64, b: u64) -> u64 {\n    let sum = a + b;\n    sum * 2\n}\n' > "$path/dep/src/lib.rs"
    printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n[dependencies]\ndep = { path = "../dep" }\n' \
        > "$path/app/Cargo.toml"
    printf 'fn main() {\n    println!("{}", dep::add(1, 2));\n}\n' > "$path/app/src/main.rs"
    (cd "$path" && cargo generate-lockfile --offline 2> /dev/null)
    printf '%s' "$path"
}

# Builds scenario $2 in $1 and sets DEBUGGED to the program's output, where lldb stopped and the local `sum` there.
build_debugged() {
    build "$1" "$2"
    local stop sum
    # Failures are reported by `expect`, not by `set -e`: lldb and `grep -c` exit non-zero when lldb never stops.
    stop=$(lldb -b -o "breakpoint set -f lib.rs -l 3" -o run -o "frame variable sum" "$1/target/debug/app" 2>&1 \
        | tee "$ROOT/$2.lldb" || true)
    sum=$(printf '%s\n' "$stop" | sed -nE 's/^\(unsigned long\) sum = ([0-9]+)$/\1/p')
    DEBUGGED="$("$1/target/debug/app") $(printf '%s\n' "$stop" | grep -cE 'dep::add\(a=1, b=2\) at lib.rs:3' || true) $sum"
    printf '%s: program, stops, sum=%s app=%s\n' "$2" "$DEBUGGED" "$(task "$2" app)"
}

d=$(debugged debug)
build_debugged "$d" debug-cold
expect "debug-cold: lldb must find the workspace library in a fresh link" "6 1 3 miss" "$DEBUGGED $(task debug-cold app)"
e=$(debugged debug-moved/nested)
build_debugged "$e" debug-moved-ready
expect debug-moved-ready hit "$(task debug-moved-ready app)"
rm -rf "$d"
lldb -b -o "breakpoint set -f lib.rs -l 3" -o run -o "frame variable sum" "$e/target/debug/app" > "$ROOT/debug-moved.lldb" 2>&1 || true
expect "debug-moved: lldb must debug a restored binary whose producing checkout is gone" 3 \
    "$(sed -nE 's/^\(unsigned long\) sum = ([0-9]+)$/\1/p' "$ROOT/debug-moved.lldb")"
build_debugged "$e" debug-clean
expect "debug-clean: lldb must debug a binary restored after its target was removed" "6 1 3 hit" \
    "$DEBUGGED $(task debug-clean app)"
