#!/usr/bin/env python3
"""Generate and validate two real Swift modules for transfer benchmarks.

The generated public names are intentionally high entropy to keep the compressed
module above the transfer threshold. This is not a representative app build.
Both revisions compile at the same source path and change one stored property's
name. Compilation time is not a chunking benchmark: both revisions must compile.
"""
import argparse
import json
from pathlib import Path
import random
import shutil
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proxy-socket", help="Also generate an XcodeGen project for a real compilation-cache restore check")
    parser.add_argument("--sources-only", action="store_true", help="Generate revision sources without standalone compilation")
    parser.add_argument("--types", type=int, default=16000, help="Number of generated structs (default: 16000)")
    args = parser.parse_args()
    if args.types < 2:
        parser.error("--types must be at least 2")
    directory = Path(tempfile.mkdtemp(prefix="tuist-swift-chunking-"))
    randomizer = random.Random(20260907)
    declarations = []
    first_type = first_property = None
    for index in range(args.types):
        name = f"Type_{randomizer.getrandbits(96):024x}"
        properties = [f"p_{randomizer.getrandbits(96):024x}" for _ in range(6)]
        if index == 0:
            first_type, first_property = name, properties[0]
        declarations.append(f"public struct {name} {{\n" + "".join(
            f"public var {prop}: Int\n" for prop in properties
        ) + "}\n")
    source = directory / "Fixture.swift"
    consumer = directory / "Consumer.swift"
    consumer.write_text(f"import SwiftChunkFixture\nfunc read(_ value: {first_type}) -> Int {{ value.{first_property} }}\n")
    paths = []
    source_paths = []
    timings = []
    for revision in range(2):
        selected = declarations.copy()
        if revision:
            midpoint = args.types // 2
            selected[midpoint] = selected[midpoint].replace("public var p_", "public var edited_", 1)
        source.write_text("".join(selected))
        revision_source = directory / f"revision-{revision}.swift"
        shutil.copyfile(source, revision_source)
        source_paths.append(str(revision_source))
        if args.sources_only:
            continue
        module = directory / "SwiftChunkFixture.swiftmodule"
        start = time.monotonic()
        subprocess.run(["xcrun", "swiftc", "-emit-module", "-parse-as-library", "-module-name", "SwiftChunkFixture",
                        "-emit-module-path", str(module), str(source)], check=True)
        timings.append(round(time.monotonic() - start, 3))
        subprocess.run(["xcrun", "swiftc", "-typecheck", "-I", str(directory), str(consumer)], check=True)
        artifact = directory / f"revision-{revision}.swiftmodule"
        shutil.copyfile(module, artifact)
        paths.append(str(artifact))
    if args.proxy_socket:
        plugin = Path(__file__).resolve().parents[3] / "cas-plugin/target/release/libtuist_cas_plugin.dylib"
        (directory / "project.yml").write_text(f"""name: SwiftChunkFixture
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
    SWIFT_VERSION: "6.0"
targets:
  SwiftChunkFixture:
    type: library.static
    platform: macOS
    sources:
      - path: Fixture.swift
""")
    print(json.dumps({"directory": str(directory), "swift_modules": paths,
                      "source_revisions": source_paths, "compile_seconds": timings}, indent=2))


if __name__ == "__main__":
    main()
