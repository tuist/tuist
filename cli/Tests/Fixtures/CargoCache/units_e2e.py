#!/usr/bin/env python3
"""Dependency-unit reuse through the public `tuist cargo` command, offline and local-only.

A: cold build publishes the registry dependency's unit.
B: same project at another path restores it; Cargo compiles only the application.
C: different rustflags in `.cargo/config.toml` miss, and Cargo compiles the dependency again.
D: B again after removing `target`, with the restored unit's rlib corrupted in the store: Cargo
   (or the blob check) must not link it, and the program must still print 42.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

binary = os.environ.get("TUIST_CLI_BINARY") or sys.exit("Set TUIST_CLI_BINARY to the freshly built tuist executable")
fixture = Path(__file__).resolve().parent
root = Path(tempfile.mkdtemp(prefix="tuist-cargo-units."))
env = {k: v for k, v in os.environ.items()
       if not k.startswith(("TUIST_", "GITHUB_")) and k not in ("RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WRAPPER")}
env.update(CARGO_INCREMENTAL="0", CARGO_TERM_COLOR="never", XDG_CACHE_HOME=str(root / "xdg"),
           TUIST_PROJECT="fixture/units", TUIST_URL="http://127.0.0.1:9", TUIST_DEBUG="1")


def checkout(name, config=None):
    path = root / name / "project"
    path.mkdir(parents=True)
    for item in ("Cargo.toml", "Cargo.lock"):
        shutil.copy(fixture / item, path)
    shutil.copytree(fixture / "src", path / "src")
    if config:
        (path / ".cargo").mkdir()
        (path / ".cargo" / "config.toml").write_text(config)
    return path


def build(path, scenario):
    shutil.rmtree(path / "target", ignore_errors=True)
    result = subprocess.run([binary, "cargo", "build", "--locked", "--offline"], cwd=path, env=env,
                            capture_output=True, text=True)
    (root / f"{scenario}.log").write_text(result.stderr)
    assert result.returncode == 0, f"{scenario}: build failed"
    output = subprocess.run([path / "target/debug/tuist-cargo-cache-smoke"], capture_output=True, text=True).stdout
    assert output.strip() == "42", f"{scenario}: unexpected output {output!r}"
    compiled = sorted(re.findall(r"^\s+Compiling (\S+)", result.stderr, re.M))
    restored = re.search(r"restored (\d+) of", result.stderr)
    print(f"{scenario}: compiled={compiled}, restored={restored.group(1) if restored else 0}")
    return compiled, int(restored.group(1)) if restored else 0


try:
    # The project's own Cargo configuration must not tie keys to the checkout's path.
    shared = '[term]\nverbose = false\n'
    a = checkout("a", shared)
    assert build(a, "cold") == (["itoa", "tuist-cargo-cache-smoke"], 0)
    b = checkout("b/nested", shared)
    compiled, restored = build(b, "moved")
    assert compiled == ["tuist-cargo-cache-smoke"] and restored >= 1
    c = checkout("c", '[build]\nrustflags = ["-C", "overflow-checks=on"]\n')
    compiled, restored = build(c, "flags")
    assert compiled == ["itoa", "tuist-cargo-cache-smoke"] and restored == 0
    blobs = next((root / "xdg").glob("tuist/Cargo/*/blobs"))
    rlib = next((b / "target/debug/deps").glob("libitoa-*.rlib"))
    digest = subprocess.run(["shasum", "-a", "256", rlib], capture_output=True, text=True).stdout.split()[0]
    (blobs / digest).write_bytes(b"corrupt" + (blobs / digest).read_bytes()[7:])
    build(b, "corrupt")
    shutil.rmtree(root)
except BaseException:
    print(f"Fixture retained at {root}", file=sys.stderr)
    raise
