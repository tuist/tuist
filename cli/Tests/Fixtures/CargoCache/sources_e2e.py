#!/usr/bin/env python3
"""Remembered source lists through the public `tuist cargo` command, offline and local-only.

Strict admission keys a path library by the sources an earlier compilation read, without running rustc to discover
them. The library has a warning, which a hit must replay. A list that no longer matches must never hide a change: a new submodule misses and is cached on that same build,
an edited submodule misses, and a file that makes module resolution ambiguous fails compilation instead of hitting.
A library whose sources strict admission refuses (`#[link]`) learns that only after rustc ran: that same build must
record its reads, so the next build hits. Expected values are computed here.
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
root = Path(tempfile.mkdtemp(prefix="tuist-cargo-sources."))
workspace = root / "ws"
env = {k: v for k, v in os.environ.items()
       if not k.startswith(("TUIST_", "GITHUB_", "LD_", "DYLD_")) and k not in ("RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WRAPPER")}
env.update(CARGO_INCREMENTAL="0", CARGO_TERM_COLOR="never", XDG_CACHE_HOME=str(root / "xdg"),
           TUIST_PROJECT="fixture/sources", TUIST_URL="http://127.0.0.1:9", TUIST_DEBUG="1")


def write(path, text):
    (workspace / path).parent.mkdir(parents=True, exist_ok=True)
    (workspace / path).write_text(text)


def build(scenario):
    shutil.rmtree(workspace / "target", ignore_errors=True)
    result = subprocess.run([binary, "cargo", "build", "--offline"], cwd=workspace, env=env, capture_output=True, text=True)
    (root / f"{scenario}.log").write_text(result.stderr)
    tasks = dict((name, status) for status, name in
                 re.findall(r"^Tuist Cargo cache: (hit|miss) rust (\S+)$", result.stderr, re.M))
    output = None
    if result.returncode == 0:
        output = subprocess.run([workspace / "target/debug/app"], capture_output=True, text=True).stdout.strip()
    print(f"{scenario}: exit={result.returncode}, output={output}, tasks={tasks}", flush=True)
    if result.returncode == 0:
        assert "function `unused` is never used" in result.stderr, f"{scenario}: the warning was not shown"
    linked.append(tasks.get("linked"))
    return result.returncode, output, tasks.get("m")


linked = []
# The read recorder supports arm64 macOS only; elsewhere the refused library stays uncached.
recorded = (platform.system(), platform.machine()) == ("Darwin", "arm64")
try:
    write("Cargo.toml", '[workspace]\nmembers = ["m", "linked", "app"]\nresolver = "2"\n')
    write("linked/Cargo.toml", '[package]\nname = "linked"\nversion = "0.1.0"\nedition = "2021"\n')
    # In a submodule, as in `libc`: the root source alone is admissible, so the compilation is deferred.
    write("linked/src/lib.rs", "mod sys;\npub fn magnitude() -> i32 { unsafe { sys::abs(-4) } }\n")
    write("linked/src/sys.rs", '#[link(name = "c")]\nextern "C" { pub fn abs(value: i32) -> i32; }\n')
    write("m/Cargo.toml", '[package]\nname = "m"\nversion = "0.1.0"\nedition = "2021"\n')
    write("m/src/lib.rs", "mod a;\nfn unused() {}\npub fn value() -> u64 { a::A }\n")
    write("m/src/a.rs", "pub const A: u64 = 1;\n")
    write("app/Cargo.toml", '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n'
                            '[dependencies]\nm = { path = "../m" }\nlinked = { path = "../linked" }\n')
    write("app/src/main.rs", 'fn main() { println!("{}", m::value() + linked::magnitude() as u64 - 4); }\n')
    subprocess.run(["cargo", "generate-lockfile", "--offline"], cwd=workspace, env=env, check=True, capture_output=True)

    assert build("cold") == (0, "1", "miss")
    assert build("warm") == (0, "1", "hit")
    assert linked == ["miss", "hit" if recorded else None], linked
    write("m/src/a.rs", "mod b;\npub const A: u64 = b::B + 1;\n")
    write("m/src/a/b.rs", "pub const B: u64 = 10;\n")
    assert build("new-submodule") == (0, "11", "miss")
    assert build("new-submodule-warm") == (0, "11", "hit")
    write("m/src/a/b.rs", "pub const B: u64 = 20;\n")
    assert build("submodule-edit") == (0, "21", "miss")
    write("m/src/a/mod.rs", "pub const A: u64 = 99;\n")
    status, _, _ = build("ambiguous")
    assert status != 0, "an ambiguous module must fail compilation, not restore an earlier result"
    shutil.rmtree(root)
except BaseException:
    print(f"Fixture retained at {root}", file=sys.stderr)
    raise
