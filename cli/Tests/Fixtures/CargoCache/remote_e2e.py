#!/usr/bin/env python3
"""Public CLI + real Kura/analytics smoke. Use an isolated local development project."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import socket
import statistics
import subprocess
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import uuid


def command(arguments, directory, environment, log=None):
    started = time.perf_counter()
    if log:
        with log.open("w") as output:
            subprocess.run(arguments, cwd=directory, env=environment, stdout=output,
                           stderr=subprocess.STDOUT, check=True, timeout=120)
    else:
        subprocess.run(arguments, cwd=directory, env=environment, stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE, check=True, timeout=120)
    return time.perf_counter() - started


def benchmark_registry(root, environment):
    """Generate a real registry leaf crate with enough compiler work to measure reuse."""
    name, version = "tuist-cache-benchmark-leaf", "0.0.1"
    registry = root / "registry"
    registry.mkdir()
    files = {"Cargo.toml": f'[package]\nname="{name}"\nversion="{version}"\nedition="2021"\n'}
    modules = 20
    files["src/lib.rs"] = "".join(f"pub mod section{i};\n" for i in range(modules))
    files["src/lib.rs"] += "pub use section0::value_0;\n"
    for module in range(modules):
        source = []
        for offset in range(200):
            index = module * 200 + offset
            source.append(f"#[inline(never)]\npub fn value_{index}(mut value: u64) -> u64 {{\n")
            for step in range(40):
                source.append(f"value = value.rotate_left(7).wrapping_add({(index + 1) * (step + 1)}) ^ value.rotate_right(3);\n")
            source.append("value\n}\n")
        files[f"src/section{module}.rs"] = "".join(source)
    archive = registry / f"{name}-{version}.crate"
    with tarfile.open(archive, "w:gz") as output:
        for path, source in files.items():
            data = source.encode()
            entry = tarfile.TarInfo(f"{name}-{version}/{path}")
            entry.size, entry.mode = len(data), 0o644
            output.addfile(entry, io.BytesIO(data))
    index = registry / "index/tu/is" / name
    index.parent.mkdir(parents=True)
    index.write_text(json.dumps(dict(name=name, vers=version, deps=[], features={}, yanked=False,
                                    cksum=hashlib.sha256(archive.read_bytes()).hexdigest())) + "\n")
    home = root / "cargo-home"
    home.mkdir()
    (home / "config.toml").write_text(
        '[source.crates-io]\nreplace-with="fixture"\n[source.fixture]\nlocal-registry=' + json.dumps(str(registry)) + "\n")
    environment["CARGO_HOME"] = str(home)
    checkout = root / "checkout"
    (checkout / "Cargo.toml").write_text(
        '[package]\nname="tuist-cargo-cache-smoke"\nversion="0.1.0"\nedition="2021"\n'
        '[dependencies]\ngenerated_leaf={package="tuist-cache-benchmark-leaf",version="=0.0.1"}\n')
    mask, expected = (1 << 64) - 1, 42
    for step in range(40):
        left = ((expected << 7) | (expected >> 57)) & mask
        right = (expected >> 3) | ((expected << 61) & mask)
        expected = ((left + step + 1) & mask) ^ right
    (checkout / "src/main.rs").write_text(
        f'fn main() {{ assert_eq!(generated_leaf::value_0(42), {expected}); println!("42"); }}\n')
    command(["cargo", "generate-lockfile", "--offline"], checkout, environment)
    return "tuist_cache_benchmark_leaf"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", action="store_true", help="Generate a large registry leaf; not a representative application benchmark")
    arguments = parser.parse_args()
    for key in ("TUIST_CLI_BINARY", "TUIST_PROJECT", "TUIST_URL", "TUIST_TOKEN", "TUIST_CACHE_ENDPOINT",
                "TUIST_CARGO_E2E_CLICKHOUSE_URL", "TUIST_CARGO_E2E_CLICKHOUSE_DB"):
        if not os.environ.get(key):
            parser.error(f"Set {key}")
    for key in ("TUIST_URL", "TUIST_CACHE_ENDPOINT", "TUIST_CARGO_E2E_CLICKHOUSE_URL"):
        endpoint = urllib.parse.urlsplit(os.environ[key])
        if endpoint.scheme not in ("http", "https") or endpoint.hostname not in ("localhost", "127.0.0.1", "::1"):
            parser.error(f"{key} must point to an isolated loopback fixture; protected-push simulation must not target production")
    database = os.environ["TUIST_CARGO_E2E_CLICKHOUSE_DB"]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", database):
        parser.error("Invalid ClickHouse database identifier")
    root = Path(tempfile.mkdtemp(prefix="tuist-cargo-public-e2e-"))
    print(f"Artifacts: {root}", flush=True)
    environment = dict(os.environ)
    for key in ("RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "OUT_DIR",
                "TUIST_CARGO_ACTIVE", "TUIST_CARGO_INNER_WRAPPER", "TUIST_SHARD_INDEX", "TUIST_SHARD_PLAN_ID"):
        environment.pop(key, None)
    # Exercise write eligibility locally, without claiming this ran on GitHub or inventing a run URL.
    environment.update(GITHUB_ACTIONS="true", GITHUB_EVENT_NAME="push", GITHUB_REF_TYPE="branch",
                       GITHUB_REF_PROTECTED="true", CARGO_INCREMENTAL="0", TUIST_DEBUG="1",
                       XDG_CACHE_HOME=str(root / "cache-home"))
    fixture, checkout = Path(__file__).resolve().parent, root / "checkout"
    checkout.mkdir()
    shutil.copytree(fixture / "src", checkout / "src")
    for file in ("Cargo.toml", "Cargo.lock"):
        shutil.copyfile(fixture / file, checkout / file)
    library = benchmark_registry(root, environment) if arguments.benchmark else "itoa"
    branch = "cargo-cache-e2e-" + uuid.uuid4().hex
    command(["git", "init", "-q", "-b", branch], checkout, environment)
    command(["git", "add", "Cargo.toml", "Cargo.lock", "src"], checkout, environment)
    command(["git", "-c", "user.name=Cargo E2E", "-c", "user.email=cargo@example.test", "-c",
             "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "Fixture"], checkout, environment)
    identity = hashlib.sha256(("swift-cargo-v1/" + environment["TUIST_URL"] + "/" + environment["TUIST_PROJECT"].lower()).encode()).hexdigest()
    cache = root / "cache-home/tuist/Cargo" / identity
    cargo_arguments = ["build", "--locked", "--offline", "--release", "-j", "4", "--target-dir", str(root / "target")]
    timings = {}
    phases = ["native-1", "native-2", "native-3", "cold", "remote", "local-1", "local-2", "local-3", "corrupt", "unavailable", "recovered"]
    for phase in phases:
        command(["cargo", "clean", "--target-dir", str(root / "target")], checkout, environment)
        if phase == "remote":
            assert cache.is_dir(), "The public CLI did not initialize its cache"
            cache.rename(root / "publisher-cache")
        if phase == "corrupt":
            blob = next((cache / "blobs").iterdir())
            blob.write_bytes(b"corrupt fixture artifact")
        current = dict(environment)
        reserved = None
        if phase in ("unavailable", "recovered"):
            shutil.rmtree(cache)
        if phase == "unavailable":
            reserved = socket.socket()
            reserved.bind(("127.0.0.1", 0))  # Bound but not listening: reserved, unreachable local endpoint.
            current["TUIST_CACHE_ENDPOINT"] = f"http://127.0.0.1:{reserved.getsockname()[1]}"
        prefix = ["cargo"] if phase.startswith("native") else [environment["TUIST_CLI_BINARY"], "cargo"]
        if not phase.startswith("native"):
            time.sleep(1.05)  # Keep the server's second-resolution report timestamps distinct; not part of the timing.
        try:
            timings[phase] = command(prefix + cargo_arguments, checkout, current, root / (phase + ".log"))
        finally:
            if reserved:
                reserved.close()
        result = subprocess.check_output([str(root / "target/release/tuist-cargo-cache-smoke")], text=True).strip()
        assert result == "42", (phase, result)
        print(f"{phase}: {timings[phase]:.3f}s, executable output={result}", flush=True)
    (root / "timings.json").write_text(json.dumps(timings, indent=2))

    def query(sql):
        url = environment["TUIST_CARGO_E2E_CLICKHOUSE_URL"].rstrip("/") + "/?" + urllib.parse.urlencode({"query": sql + " FORMAT JSONEachRow"})
        with urllib.request.urlopen(url, timeout=15) as response:
            return [json.loads(line) for line in response.read().decode().splitlines()]

    expected_phases = [phase for phase in phases if not phase.startswith("native")]
    for attempt in range(40):
        rows = query(f"SELECT id, cache_metrics FROM {database}.cargo_builds WHERE git_branch='{branch}' ORDER BY inserted_at, id")
        observations = query(f"SELECT build_id, groupArray(name) AS names FROM {database}.cargo_compilations WHERE build_id IN "
                             f"(SELECT id FROM {database}.cargo_builds WHERE git_branch='{branch}') GROUP BY build_id")
        if len(rows) == len(expected_phases) and len(observations) == len(expected_phases):
            break
        time.sleep(1)
    else:
        raise AssertionError("The server did not ingest all real build/compiler reports")
    (root / "builds.json").write_text(json.dumps(rows, indent=2))
    compiler_names = {row["build_id"]: row["names"] for row in observations}
    for phase, row in zip(expected_phases, rows):
        metrics = json.loads(row["cache_metrics"])
        miss = phase in ("cold", "unavailable")
        assert (metrics["hits"], metrics["misses"]) == ((0, 1) if miss else (1, 0)), (phase, metrics)
        names = compiler_names[row["id"]]
        assert len(names) == (2 if miss else 1) and ((library in names) == miss), (phase, names)
        if phase in ("remote", "corrupt", "recovered"):
            assert metrics["downloaded_bytes"] > 0, (phase, metrics)
        # Chunked benchmark uploads may reuse chunks; their parent sizes are not measured transfer bytes.
        # The following remote-hit phase independently proves publication after removing the publisher cache.
        if phase == "cold" and not arguments.benchmark:
            assert metrics["uploaded_bytes"] > 0, metrics
        if phase == "unavailable":
            assert metrics["remote_failures"] > 0, metrics
        else:
            assert metrics["remote_failures"] == metrics["background_upload_failures"] == 0, (phase, metrics)
        if phase.startswith("local"):
            assert metrics["downloaded_bytes"] == 0, metrics
        assert not metrics["details"]["truncated"], metrics
        print(f"PASS {phase}: hits={metrics['hits']} misses={metrics['misses']} compiler executions={len(names)} "
              f"downloaded={metrics['downloaded_bytes']} uploaded={metrics['uploaded_bytes']}")
    print(f"Median native clean build: {statistics.median(timings[p] for p in phases if p.startswith('native')):.3f}s")
    print(f"Median public CLI local hit: {statistics.median(timings[p] for p in phases if p.startswith('local')):.3f}s")
    print("Timings include CLI setup/reporting; generated-workload results are not a general Cargo performance claim.")
    print(f"PASS: public CLI, Kura reuse/repair/fallback, compiler avoidance and server ingestion. Artifacts: {root}")


if __name__ == "__main__":
    main()
