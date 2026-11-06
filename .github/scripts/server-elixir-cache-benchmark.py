#!/usr/bin/env python3
"""Compare the full locked server graph using a run-scoped remote cache.

Run only in a disposable GitHub Actions checkout. Downloads/source reset are
outside build timers. Native download caches remain shared between samples.
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
from urllib.parse import urlsplit


SAMPLE_TIMEOUT = 1200
TOTAL_TIMEOUT = 3000  # Measured from the job's first step, leaving 10 minutes for cleanup.


def cache_config(source, mode, store):
    anchor = 'tuist: [project: "tuist/server", cache: true]'
    if source.count(anchor) != 1:
        raise ValueError("Expected the server's unfiltered cache: true configuration")
    if mode == "disabled":
        config = "false"
    elif mode in ("seed", "remote"):
        config = (
            f'[path: {json.dumps(str(store))}, upload: {str(mode == "seed").lower()}, '
            'env: ["TUIST_ELIXIR_CACHE_BENCHMARK_RUN"]]'
        )
    else:
        raise ValueError(f"Unknown mode: {mode}")
    return source.replace(anchor, f'tuist: [project: "tuist/server", cache: {config}]')


def endpoint_origin(endpoint):
    if not endpoint:
        return "account discovery"
    try:
        parsed = urlsplit(endpoint)
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            return "invalid endpoint override"
        host = f"[{parsed.hostname}]" if ":" in parsed.hostname else parsed.hostname
        port = f":{parsed.port}" if parsed.port else ""
        return f"{parsed.scheme}://{host}{port}"
    except ValueError:
        return "invalid endpoint override"


def summarize(events, seeded_keys=(), seeded_apps=()):
    outcomes = collections.Counter(event["outcome"] for event in events)
    misses = {e["key"] for e in events if e["outcome"] == "miss" and e.get("key")}
    available = {
        e["key"] for e in events
        if e.get("key") and (e["outcome"] == "remote_hit" or e.get("write_source") == "remote")
    }
    available_apps = {
        e["dependency"] for e in events
        if e.get("dependency") and e.get("key") and
        (e["outcome"] == "remote_hit" or e.get("write_source") == "remote")
    }
    restored_apps = {e["dependency"] for e in events if e["outcome"] == "remote_hit" and e.get("dependency")}
    missing_apps = set(seeded_apps) - restored_apps
    return {
        "outcomes": dict(outcomes),
        "keyed_local_hits": sum(e["outcome"] == "local_hit" and bool(e.get("key")) for e in events),
        "up_to_date": sum(e["reason"] == "up_to_date" for e in events),
        "remote_hits": outcomes["remote_hit"],
        "remote_writes": sum(e.get("write_source") == "remote" for e in events),
        "remote_read_bytes": sum(e.get("read_bytes", 0) for e in events if e["outcome"] == "remote_hit"),
        "remote_read_us": sum(e.get("read_duration_us", 0) for e in events if e["outcome"] == "remote_hit"),
        "remote_available_keys": sorted(available),
        "seeded_key_misses": sorted(misses.intersection(seeded_keys)),
        "remote_available_apps": sorted(available_apps),
        "seeded_app_misses": sorted(missing_apps),
        "degraded": bool(misses or missing_apps),
    }


def validate(sample):
    if sample["status"] != 0 or not sample.get("completed") or sample.get("record_errors"):
        raise RuntimeError("Build did not complete with valid records, regardless of process exit status")
    if sample["mode"] == "disabled" and sample["outcomes"]:
        raise RuntimeError("Disabled sample unexpectedly used dependency caching")
    if sample["mode"] in ("seed", "remote"):
        if sample["keyed_local_hits"] != 0:
            raise RuntimeError("Remote comparison was contaminated by local artifact hits")
    if sample["mode"] == "remote" and sample["remote_hits"] == 0:
        raise RuntimeError("Remote failed open without any actual remote restores")
    if sample["mode"] == "seed" and sample["remote_writes"] == 0:
        raise RuntimeError("Run-scoped seed did not confirm any remote artifact publications")


def compiled_apps(log):
    matches = re.findall(r"^(?:\d+> )?(?:Generated (\w+) app|===> Compiling (\w+))$", log, re.MULTILINE)
    return sorted({app for pair in matches for app in pair if app})


def read_record(path, errors):
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError("expected an object")
        return value
    except (OSError, ValueError) as error:
        errors.append(f"{path.name}: {type(error).__name__}")
        return {}


def terminate(process):
    # Finish before the runner's cancellation escalation, and do not let a
    # second cancellation interrupt cleanup of our isolated process group.
    handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            pass
        # The leader may have exited while descendants still compile or upload.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


def measure(root, results, env, index, mode, timeout, seeded_keys, seeded_apps=()):
    label = f"{index}-{mode}"
    result_file = results / f"{label}.json"
    event_file = results / f"{label}-events.json"
    log_file = results / f"{label}.log"
    env = env | {"BENCH_RESULT": str(result_file), "BENCH_EVENTS": str(event_file)}
    started = time.monotonic()
    load_before = os.getloadavg()
    interruption = None
    print(f"START {label}", flush=True)
    with log_file.open("w") as output:
        process = None
        try:
            process = subprocess.Popen(
                ["elixir", str(root / ".github/scripts/server-elixir-cache-measure.exs")],
                cwd=root / "server", env=env, stdout=output,
                stderr=subprocess.STDOUT, start_new_session=True,
            )
            status = process.wait(timeout=timeout)
        except BaseException as error:
            if process is not None:
                terminate(process)
            interruption = error
            status = 124 if isinstance(error, subprocess.TimeoutExpired) else 130
    wall = time.monotonic() - started
    errors = []
    sample = read_record(result_file, errors)
    events = read_record(event_file, errors).get("dependency_cache", [])
    sample.update(summarize(events, seeded_keys, seeded_apps))
    sample["degraded"] = mode == "remote" and sample["degraded"]
    sample.update(
        mode=mode, index=index, status=status, process_wall_s=wall,
        compilation=env.get("TUIST_ELIXIR_CACHE_BENCHMARK_COMPILATION", "default"),
        erl_compiler_options=env.get("ERL_COMPILER_OPTIONS"),
        load_before=load_before, load_after=os.getloadavg(),
        compiled_apps=compiled_apps(log_file.read_text(errors="replace")), record_errors=errors,
        interrupted=interruption is not None,
    )
    if interruption is not None:
        sample["interruption_reason"] = type(interruption).__name__
        sample["completed"] = False
    return sample, interruption


def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2))
    temporary.replace(path)


def write_samples(results, samples):
    write_json(results / f"{samples[-1]['index']}-{samples[-1]['mode']}.json", samples[-1])
    write_json(results / "samples.json", samples)


def raise_interruption(signum, _frame):
    raise KeyboardInterrupt(signal.Signals(signum).name)


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("Use only a disposable GitHub Actions checkout; this resets dependency/build directories")
    elapsed = max(0, time.time() - float(os.environ["BENCH_JOB_STARTED"]))
    deadline = time.monotonic() + max(0, TOTAL_TIMEOUT - elapsed)
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
    env.update(
        ERL_FLAGS="+S 4:4", MIX_ENV="dev", MIX_TARGET="host",
        MIX_OS_DEPS_COMPILE_PARTITION_COUNT="3", TUIST_PROJECT="tuist/server",
        TUIST_URL="https://tuist.dev", TUIST_DEBUG="1",
        TUIST_ELIXIR_CACHE_BENCHMARK_RUN=f"{env['GITHUB_RUN_ID']}-{env['GITHUB_RUN_ATTEMPT']}",
    )
    metadata = {
        "commit": os.environ["GITHUB_SHA"], "platform": platform.platform(),
        "runner": os.environ.get("RUNNER_NAME"), "cpu_count": os.cpu_count(),
        "schedulers": 4, "dependency_workers": 3,
        "compilation": env.get("TUIST_ELIXIR_CACHE_BENCHMARK_COMPILATION", "default"),
        "erl_compiler_options": env.get("ERL_COMPILER_OPTIONS"),
        "endpoint": endpoint_origin(env.get("TUIST_CACHE_ENDPOINT")),
        "namespace": env["TUIST_ELIXIR_CACHE_BENCHMARK_RUN"], "lock_sha256": lock_hash,
    }
    write_json(results / "environment.json", metadata)
    samples = []
    seeded_keys = set()
    seeded_apps = set()
    previous_handler = signal.signal(signal.SIGTERM, raise_interruption)
    try:
        for index, mode in enumerate(["seed", "disabled", "remote", "remote", "disabled"]):
            for path in (server / "_build", root / "tuist_ex/_build", root / "noora/_build", root / "tuist_common/_build", store, server / "deps"):
                if path.exists():
                    shutil.rmtree(path)
            shutil.copytree(pristine, server / "deps", symlinks=True)
            mixfile.write_text(cache_config(original, mode, store))
            timeout = min(SAMPLE_TIMEOUT, max(0, deadline - time.monotonic()))
            samples.append(dict(mode=mode, index=index, completed=False, status=None))
            write_samples(results, samples)
            sample, interruption = measure(root, results, env, index, mode, timeout, seeded_keys, seeded_apps)
            samples[-1] = sample
            write_samples(results, samples)
            print(f"END {index}-{mode} " + json.dumps(sample), flush=True)
            if interruption is not None:
                raise interruption
            if hashlib.sha256((server / "mix.lock").read_bytes()).hexdigest() != lock_hash:
                raise RuntimeError("Benchmark changed the committed lock")
            validate(sample)
            if mode == "seed":
                seeded_keys.update(sample["remote_available_keys"])
                seeded_apps.update(sample["remote_available_apps"])
        if any(s["seeded_key_misses"] or s["seeded_app_misses"] for s in samples if s["mode"] == "remote"):
            raise RuntimeError("Remote samples failed to restore seeded dependencies; results are degraded")
    finally:
        signal.signal(signal.SIGTERM, previous_handler)
        mixfile.write_text(original)
        shutil.rmtree(pristine)


if __name__ == "__main__":
    main()
