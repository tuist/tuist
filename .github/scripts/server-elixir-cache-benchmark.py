#!/usr/bin/env python3
"""Full locked server graph: seed remote, then alternating disabled/remote builds.

Run only in a disposable GitHub Actions checkout. Dependency downloads, source
reset and cache seeding are reported separately, never counted as warm savings.
"""
import collections
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import signal
import subprocess
import time


def cache_config(source, mode, store):
    anchor = 'tuist: [project: "tuist/server", cache: true]'
    if source.count(anchor) != 1:
        raise ValueError("Expected the server's unfiltered cache: true configuration")
    if mode == "disabled":
        config = "false"
    elif mode in ("seed", "remote"):
        config = f'[path: {json.dumps(str(store))}, upload: {str(mode == "seed").lower()}]'
    else:
        raise ValueError(f"Unknown mode: {mode}")
    return source.replace(anchor, f'tuist: [project: "tuist/server", cache: {config}]')


def summarize(events):
    outcomes = collections.Counter(event["outcome"] for event in events)
    return {
        "outcomes": dict(outcomes),
        "keyed_local_hits": sum(e["outcome"] == "local_hit" and bool(e.get("key")) for e in events),
        "up_to_date": sum(e["reason"] == "up_to_date" for e in events),
        "remote_hits": outcomes["remote_hit"],
        "remote_writes": sum(e.get("write_source") == "remote" for e in events),
        "remote_read_bytes": sum(e.get("read_bytes", 0) for e in events if e["outcome"] == "remote_hit"),
        "remote_read_us": sum(e.get("read_duration_us", 0) for e in events if e["outcome"] == "remote_hit"),
    }


def validate(sample):
    if sample["status"] != 0 or not sample.get("completed"):
        raise RuntimeError("Build did not complete, regardless of process exit status")
    if sample["mode"] == "remote":
        if sample["local_entries_before"] != 0 or sample["keyed_local_hits"] != 0:
            raise RuntimeError("Remote comparison was contaminated by local artifact hits")
        if sample["remote_hits"] == 0:
            raise RuntimeError("Remote failed open without any actual remote restores")
    if sample["mode"] == "seed" and sample["remote_writes"] == 0:
        raise RuntimeError("Seed build did not confirm any remote artifact publications")


def compiled_apps(log):
    matches = re.findall(r"^(?:Generated (\w+) app|===> Compiling (\w+))$", log, re.MULTILINE)
    return sorted({app for pair in matches for app in pair if app})


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("Use only a disposable GitHub Actions checkout; this resets dependency/build directories")
    root = pathlib.Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    results = pathlib.Path(os.environ["RUNNER_TEMP"]) / "elixir-cache-benchmark"
    results.mkdir(exist_ok=False)
    server = root / "server"
    mixfile = server / "mix.exs"
    original = mixfile.read_text()
    lock_hash = hashlib.sha256((server / "mix.lock").read_bytes()).hexdigest()
    pristine = results / "pristine-deps"
    shutil.copytree(server / "deps", pristine, symlinks=True)
    store = results / "local-artifacts"
    env = os.environ.copy()
    for name in ("MIX_BUILD_PATH", "MIX_DEPS_PATH", "MIX_PATH", "ERL_AFLAGS"):
        env.pop(name, None)
    env.update(ERL_FLAGS="+S 4:4", MIX_ENV="dev", MIX_TARGET="host", MIX_OS_DEPS_COMPILE_PARTITION_COUNT="3", TUIST_PROJECT="tuist/server", TUIST_URL="https://tuist.dev", TUIST_DEBUG="1")
    metadata = {"commit": os.environ["GITHUB_SHA"], "platform": platform.platform(), "runner": os.environ.get("RUNNER_NAME"), "cpu_count": os.cpu_count(), "schedulers": 4, "dependency_workers": 3, "endpoint": env.get("TUIST_CACHE_ENDPOINT", "account discovery"), "lock_sha256": lock_hash}
    (results / "environment.json").write_text(json.dumps(metadata, indent=2))
    samples = []
    try:
        for index, mode in enumerate(["seed", "disabled", "remote", "remote", "disabled"]):
            label = f"{index}-{mode}"
            for path in (server / "_build", root / "tuist_ex/_build", root / "noora/_build", root / "tuist_common/_build", store, server / "deps"):
                if path.exists():
                    shutil.rmtree(path)
            shutil.copytree(pristine, server / "deps", symlinks=True)
            mixfile.write_text(cache_config(original, mode, store))
            local_entries_before = len(list(store.glob("*/manifest.json")))
            result_file = results / f"{label}.json"
            event_file = results / f"{label}-events.json"
            env.update(BENCH_RESULT=str(result_file), BENCH_EVENTS=str(event_file))
            started = time.monotonic()
            load_before = os.getloadavg()
            print(f"START {label}", flush=True)
            with (results / f"{label}.log").open("w") as output:
                process = subprocess.Popen(["elixir", str(root / ".github/scripts/server-elixir-cache-measure.exs")], cwd=server, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    status = process.wait(timeout=1200)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    status = 124
            wall = time.monotonic() - started
            sample = json.loads(result_file.read_text()) if result_file.exists() else {}
            events = json.loads(event_file.read_text()).get("dependency_cache", []) if event_file.exists() else []
            sample.update(summarize(events))
            sample.update(mode=mode, index=index, status=status, process_wall_s=wall, local_entries_before=local_entries_before, load_before=load_before, load_after=os.getloadavg())
            sample["compiled_apps"] = compiled_apps((results / f"{label}.log").read_text())
            samples.append(sample)
            result_file.write_text(json.dumps(sample, indent=2))
            (results / "samples.json").write_text(json.dumps(samples, indent=2))
            print("END " + label + " " + json.dumps(sample), flush=True)
            if hashlib.sha256((server / "mix.lock").read_bytes()).hexdigest() != lock_hash:
                raise RuntimeError("Benchmark changed the committed lock")
            validate(sample)
    finally:
        mixfile.write_text(original)
        shutil.rmtree(pristine)


if __name__ == "__main__":
    main()
