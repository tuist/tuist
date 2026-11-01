#!/usr/bin/env python3
"""Recorded compilations and build-script runs through the public `tuist cargo` command, offline and local-only.

The workspace has a proc macro reading an undeclared file and an environment variable, a library with a build
script that uses it, and an application. Strict admission rejects the library (it consumes a proc macro), so only
the read recorder can cache it. The build script stamps its output with the current time: a restored run keeps the
cold build's stamp, and a rerun gets a new one. Every expected value is computed here, not taken from a build.
"""
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

binary = os.environ.get("TUIST_CLI_BINARY") or sys.exit("Set TUIST_CLI_BINARY to the freshly built tuist executable")
if (platform.system(), platform.machine()) != ("Darwin", "arm64"):
    sys.exit("The read recorder supports arm64 macOS only")
root = Path(tempfile.mkdtemp(prefix="tuist-cargo-recorded."))
env = {k: v for k, v in os.environ.items()
       if not k.startswith(("TUIST_", "GITHUB_", "LD_", "DYLD_")) and k not in ("RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WRAPPER")}
env.update(CARGO_INCREMENTAL="0", CARGO_TERM_COLOR="never", XDG_CACHE_HOME=str(root / "xdg"),
           TUIST_PROJECT="fixture/recorded", TUIST_URL="http://127.0.0.1:9", TUIST_DEBUG="1")

FILES = {
    "Cargo.toml": '[workspace]\nmembers = ["macros", "base", "app"]\nresolver = "2"\n',
    "value.txt": "7\n",
    "macros/Cargo.toml": '[package]\nname = "macros"\nversion = "0.1.0"\nedition = "2021"\n[lib]\nproc-macro = true\n',
    "macros/src/lib.rs": '''extern crate proc_macro;
#[proc_macro]
pub fn value(_: proc_macro::TokenStream) -> proc_macro::TokenStream {
    let extra: u64 = std::env::var("MACRO_EXTRA").ok().and_then(|v| v.parse().ok()).unwrap_or(0);
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../value.txt");
    let base: u64 = std::fs::read_to_string(path).unwrap().trim().parse().unwrap();
    (base + extra).to_string().parse().unwrap()
}
''',
    "base/Cargo.toml": '[package]\nname = "base"\nversion = "0.1.0"\nedition = "2021"\n'
                       '[dependencies]\nmacros = { path = "../macros" }\n',
    "base/generated.txt": "100\n",
    "base/build.rs": '''fn main() {
    println!("cargo::rerun-if-changed=generated.txt");
    let input = std::fs::read_to_string("generated.txt").unwrap();
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(
        format!("{out}/generated.rs"),
        format!("pub const GENERATED: u64 = {};\\npub const STAMP: u128 = {stamp};\\n", input.trim()),
    ).unwrap();
}
''',
    "base/src/lib.rs": 'include!(concat!(env!("OUT_DIR"), "/generated.rs"));\n'
                       'pub fn base() -> u64 { macros::value!() + GENERATED }\n',
    "app/Cargo.toml": '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n'
                      '[dependencies]\nbase = { path = "../base" }\n',
    "app/src/main.rs": 'fn main() { println!("{} {}", base::base(), base::STAMP); }\n',
}


def checkout(name):
    path = root / name / "ws"
    for relative, text in FILES.items():
        (path / relative).parent.mkdir(parents=True, exist_ok=True)
        (path / relative).write_text(text)
    # Recording shares the dependency-unit cache's scope, which is keyed by the lockfile.
    subprocess.run(["cargo", "generate-lockfile", "--offline"], cwd=path, env=env, check=True, capture_output=True)
    return path


def build(path, scenario, **extra):
    shutil.rmtree(path / "target", ignore_errors=True)
    result = subprocess.run([binary, "cargo", "build", "--offline"], cwd=path, env=dict(env, **extra),
                            capture_output=True, text=True)
    (root / f"{scenario}.log").write_text(result.stderr)
    assert result.returncode == 0, f"{scenario}: build failed"
    value, stamp = subprocess.run([path / "target/debug/app"], capture_output=True, text=True).stdout.split()
    tasks = dict((name, status) for status, name in
                 re.findall(r"^Tuist Cargo cache: (hit|miss) rust (\S+)$", result.stderr, re.M))
    print(f"{scenario}: value={value}, tasks={tasks}", flush=True)
    return int(value), stamp, tasks


try:
    a = checkout("a")
    value, cold, tasks = build(a, "cold")
    assert value == 7 + 100 and tasks.get("base") == "miss", tasks

    value, stamp, tasks = build(a, "warm")
    assert value == 7 + 100 and tasks.get("base") == "hit" and tasks.get("macros") == "hit", tasks
    assert stamp == cold, "warm: the build-script run must be restored, not rerun"

    (a / "value.txt").write_text("9\n")
    value, stamp, tasks = build(a, "macro-file")
    assert value == 9 + 100 and tasks.get("base") == "miss" and stamp == cold, tasks

    value, stamp, tasks = build(a, "macro-env", MACRO_EXTRA="5")
    assert value == 9 + 5 + 100 and tasks.get("base") == "miss", tasks

    value, stamp, tasks = build(a, "macro-env-warm", MACRO_EXTRA="5")
    assert value == 9 + 5 + 100 and tasks.get("base") == "hit", tasks

    (a / "base/generated.txt").write_text("200\n")
    value, rerun, tasks = build(a, "script-input")
    assert value == 9 + 200 and rerun != cold and tasks.get("base") == "miss", tasks

    # The same sources at another path: the macro embeds its manifest directory, so its users may miss, but the
    # program must still read the moved checkout's files.
    b = checkout("b/nested")
    (b / "value.txt").write_text("3\n")
    value, _, _ = build(b, "moved")
    assert value == 3 + 100, value
    shutil.rmtree(root)
except BaseException:
    print(f"Fixture retained at {root}", file=sys.stderr)
    raise
