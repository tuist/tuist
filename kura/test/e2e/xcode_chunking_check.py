#!/usr/bin/env python3
"""Check Swift compilation-cache restores against a locally running Kura.

Supply two revisions of the standalone generated Swift fixture. Builds always
use the same source and derived-data paths. Each remote restore starts with an
empty compiler store; only the reader's transfer chunks survive its restart.
All products, logs, inventories, and the report stay in a fresh temporary folder.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
from urllib.parse import urlparse


def output_hashes(derived):
    products = derived / "Build/Intermediates.noindex/SwiftChunkFixture.build/Debug/SwiftChunkFixture.build/Objects-normal/arm64"
    return {
        name: hashlib.sha256((products / name).read_bytes()).hexdigest()
        for name in (
            "SwiftChunkFixture.swiftmodule", "Fixture.o", "Fixture.swiftdeps",
            "SwiftChunkFixture.swiftsourceinfo", "SwiftChunkFixture.swiftdoc",
            "SwiftChunkFixture-Swift.h", "SwiftChunkFixture.abi.json", "Fixture.swiftconstvalues",
            "Fixture.d", "Fixture.dia", "SwiftChunkFixture-primary-emit-module.d",
            "SwiftChunkFixture-primary-emit-module.dia",
        )
    }


def inventory_summary(path):
    outputs = [json.loads(line) for line in path.read_text().splitlines()]
    return [
        {
            "kind": output["kind"],
            "nodes": len(output["nodes"]),
            "raw_bytes": sum(node["bytes"] for node in output["nodes"].values()),
            "whole_frame_bytes": sum(node["whole_frame_bytes"] for node in output["nodes"].values()),
            "negotiated_frame_bytes": sum(node["negotiated_frame_bytes"] for node in output["nodes"].values()),
            "eligible_nodes": sum(node["chunk_eligible"] for node in output["nodes"].values()),
        }
        for output in outputs
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--edited-source", required=True, type=Path)
    parser.add_argument("--url", default="http://127.0.0.1:18765")
    args = parser.parse_args()
    endpoint = urlparse(args.url)
    if endpoint.scheme != "http" or endpoint.hostname != "127.0.0.1" or not endpoint.port:
        parser.error("--url must point at a local loopback Kura")
    sources = [args.source.read_bytes(), args.edited_source.read_bytes()]
    if sources[0] == sources[1]:
        parser.error("the fixture revisions must differ")
    repo = Path(__file__).resolve().parents[3]
    binaries = repo / "cas-plugin/target/release"
    proxy = binaries / "tuist-cas-proxy"
    inventory = binaries / "examples/cache_output_inventory"
    plugin = binaries / "libtuist_cas_plugin.dylib"
    for binary in (proxy, inventory, plugin):
        if not binary.is_file():
            parser.error(f"build the release plugin and inventory example first: {binary}")
    root = Path(tempfile.mkdtemp(prefix="tuist-xcode-check-"))
    derived = root / "DerivedData"
    socket = root / "proxy.sock"
    instance = f"chunking-test/{root.name}"
    source = root / "Fixture.swift"
    source.write_bytes(sources[0])
    (root / "project.yml").write_text(f"""name: SwiftChunkFixture
settings:
  base:
    CODE_SIGNING_ALLOWED: NO
    COMPILATION_CACHE_ENABLE_CACHING: YES
    COMPILATION_CACHE_ENABLE_PLUGIN: YES
    COMPILATION_CACHE_PLUGIN_PATH: {json.dumps(str(plugin))}
    COMPILATION_CACHE_REMOTE_SERVICE_PATH: {json.dumps(str(socket))}
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS: YES
    OTHER_SWIFT_FLAGS: "-cas-plugin-option tuist-instance={instance}"
    SWIFT_ENABLE_EXPLICIT_MODULES: YES
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "15.0"
targets:
  SwiftChunkFixture:
    type: library.static
    platform: macOS
    sources: [Fixture.swift]
""")
    subprocess.run(["mise", "x", "xcodegen@2.46.0", "--", "xcodegen", "generate"], cwd=root, check=True)
    env = {
        **os.environ,
        "TUIST_CAS_PROXY_SOCKET": str(socket),
        "TUIST_CAS_REMOTE_GRPC_URL": args.url,
        "TUIST_CAS_TOKEN": "local-fixture",
        "TUIST_CAS_PREFETCH": "0",
        "TUIST_CAS_TUIST_BIN": "/usr/bin/false",
        "TUIST_CAS_ANALYTICS_DB": "",
    }
    command = [
        "xcodebuild", "build", "-project", "SwiftChunkFixture.xcodeproj", "-scheme", "SwiftChunkFixture",
        "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(derived),
        "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
    ]
    report = {"directory": str(root), "builds": []}

    def phase(name, writer, clean=False, expected=None, inspect=False):
        registry = root / ("writer" if writer else "reader") / "registry"
        registry.parent.mkdir(exist_ok=True)
        log = root / f"{name}.proxy.log"
        phase_env = {**env, "TUIST_CAS_LOG": str(log), "TUIST_CAS_UPLOAD": "true" if writer else "false",
                     "TUIST_CAS_PROXY_REGISTRY": str(registry)}
        started = time.monotonic()
        with (root / f"{name}.proxy-stdout.log").open("w") as proxy_log:
            process = subprocess.Popen([str(proxy)], env=phase_env, stdout=proxy_log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 10
                while not socket.exists():
                    if process.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError(f"proxy failed to start; see {proxy_log.name}")
                    time.sleep(0.05)
                build_log = root / f"{name}.build.log"
                with build_log.open("w") as output:
                    subprocess.run(command[:1] + (["clean"] if clean else []) + command[1:],
                                   cwd=root, env=phase_env, stdout=output, stderr=subprocess.STDOUT,
                                   timeout=300, check=True)
                if writer:
                    subprocess.run([str(proxy), "--drain", str(derived / "CompilationCache.noindex/plugin"),
                                    "--socket", str(socket), "--timeout-ms", "30000"], check=True, timeout=40)
                hits = re.findall(r"(\d+) hits / (\d+) cacheable tasks", build_log.read_text())
                if not hits:
                    raise RuntimeError(f"no cache task summary in {build_log}")
                hit_count, total = map(int, hits[-1])
                hashes = output_hashes(derived)
                if expected is not None:
                    assert hit_count == total and total > 0, (name, hits[-1])
                    assert hashes == expected, f"{name}: restored compiler products differ"
                result = {"phase": name, "hits": hit_count, "tasks": total,
                          "seconds": round(time.monotonic() - started, 3), "hashes": hashes}
                if not writer:
                    finished_ms = int(time.time() * 1000)
                    deadline = time.monotonic() + 12
                    while True:
                        stats = re.findall(
                            r"t=(\d+).*proxy stats:.*batch_download_bytes=(\d+) reused_chunk_bytes=(\d+)",
                            log.read_text() if log.exists() else "",
                        )
                        if stats and int(stats[-1][0]) >= finished_ms:
                            result["downloaded_bytes"] = int(stats[-1][1])
                            result["reused_bytes"] = int(stats[-1][2])
                            break
                        if time.monotonic() >= deadline:
                            raise RuntimeError(f"missing final transfer counters in {log}")
                        time.sleep(0.1)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                # Only paths owned by this short-lived fixture are removed.
                socket.unlink(missing_ok=True)
        if inspect:
            inventory_path = root / f"{name}.inventory.jsonl"
            with inventory_path.open("w") as output:
                subprocess.run([str(inventory), str(derived / "CompilationCache.noindex/plugin"), str(build_log)],
                               stdout=output, check=True, timeout=120)
            result["outputs"] = inventory_summary(inventory_path)
        report["builds"].append(result)
        (root / "report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps({key: value for key, value in result.items() if key != "hashes"}), flush=True)
        return hashes

    print(f"Evidence: {root}", flush=True)
    original = phase("base-compile", writer=True)
    phase("base-local", writer=True, clean=True, expected=original, inspect=True)
    derived.rename(root / "base-compiled")
    phase("base-remote", writer=False, expected=original)
    derived.rename(root / "base-restored")
    phase("base-restarted", writer=False, expected=original)
    cold, warm = report["builds"][-2:]
    assert warm["reused_bytes"] > 0, "the restarted reader did not reuse transfer chunks"
    assert warm["downloaded_bytes"] < cold["downloaded_bytes"], "local chunks did not reduce downloads"
    derived.rename(root / "base-restored-after-restart")
    source.write_bytes(sources[1])
    edited = phase("edited-compile", writer=True)
    phase("edited-local", writer=True, clean=True, expected=edited, inspect=True)
    derived.rename(root / "edited-compiled")
    phase("edited-remote", writer=False, expected=edited)
    print(f"Passed; report and per-output inventories: {root}", flush=True)


if __name__ == "__main__":
    main()
