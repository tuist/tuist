#!/usr/bin/env python3
"""Build deterministic compiler fixtures for the negotiated-upload benchmarks.

These are generated workloads, not customer projects. Compiler output contains
80,000 small arithmetic functions; revision one changes one function's constant.
All files are created in a fresh temporary directory, never in a source checkout.
"""
import argparse
import json
from pathlib import Path
import random
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proxy-socket", help="Also generate an XcodeGen project using this isolated proxy socket")
    args = parser.parse_args()
    directory = Path(tempfile.mkdtemp(prefix="tuist-chunking-fixtures-"))
    randomizer = random.Random(20260907)
    functions = []
    for index in range(80000):
        constants = [randomizer.getrandbits(64) for _ in range(3)]
        functions.append(
            f"unsigned long fixture_{index}(unsigned long x) {{ return "
            f"((x ^ {constants[0]}UL) * {constants[1] | 1}UL) + {constants[2]}UL; }}\n"
        )
    paths = {"objects": []}
    for revision in range(2):
        source = directory / "Fixture.c"
        selected = functions.copy()
        if revision:
            selected[40000] = selected[40000].replace("(x ^", "((x + 17UL) ^")
        source.write_text("".join(selected))
        (directory / f"revision-{revision}.c").write_text("".join(selected))
        artifact = directory / f"revision-{revision}.o"
        subprocess.run(["xcrun", "clang", "-O1", "-c", str(source), "-o", str(artifact)], check=True)
        paths["objects"].append(str(artifact))
    if args.proxy_socket:
        plugin = Path(__file__).resolve().parents[3] / "cas-plugin/target/release/libtuist_cas_plugin.dylib"
        (directory / "Marker.swift").write_text("public func fixtureMarker() -> Int { 1 }\n")
        (directory / "project.yml").write_text(f"""name: ChunkingFixture
options:
  deploymentTarget:
    macOS: "15.0"
settings:
  base:
    CODE_SIGNING_ALLOWED: NO
    COMPILATION_CACHE_ENABLE_CACHING: YES
    COMPILATION_CACHE_ENABLE_PLUGIN: YES
    COMPILATION_CACHE_PLUGIN_PATH: {json.dumps(str(plugin))}
    COMPILATION_CACHE_REMOTE_SERVICE_PATH: {json.dumps(args.proxy_socket)}
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS: YES
    OTHER_SWIFT_FLAGS: "-cas-plugin-option tuist-instance=chunking-test/{directory.name}"
    SWIFT_ENABLE_EXPLICIT_MODULES: YES
    GCC_OPTIMIZATION_LEVEL: "1"
targets:
  ChunkingFixture:
    type: library.static
    platform: macOS
    sources:
      - path: revision-0.c
      - path: Marker.swift
""")
    print(json.dumps({"directory": str(directory), **paths}, indent=2))


if __name__ == "__main__":
    main()
