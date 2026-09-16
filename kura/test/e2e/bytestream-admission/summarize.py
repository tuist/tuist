"""Summarize retained local admission runs without treating missing metrics as zero."""
import argparse
import json
from pathlib import Path


def metrics(path):
    values = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        name, value, *_ = line.split()
        values[name] = float(value)
    return values


def cpu_seconds(sample):
    return sum(
        float(value) * 60**index
        for index, value in enumerate(reversed(sample["cpu"].split(":")))
    )


def summarize(path):
    samples = json.loads((path / "samples.json").read_text())
    for sample in samples:
        sample["metrics"] = metrics(path / sample["file"])
    idle = [sample for sample in samples if sample["phase"] == "idle"][-1]
    recovery = [sample for sample in samples if sample["phase"] == "settled"]
    load = [sample for sample in samples if sample["phase"] == "read"]
    result = next(
        json.loads(line.removeprefix("LOAD_RESULT_JSON "))
        for line in (path / "read.log").read_text().splitlines()
        if line.startswith("LOAD_RESULT_JSON ")
    )
    completed_bytes = result["codes"].get("OK", 0) * result["size_kb"] * 1024
    cpu = cpu_seconds(recovery[0]) - cpu_seconds(idle)
    gauges = {}
    for name in (
        "kura_jemalloc_allocated_bytes",
        "kura_jemalloc_resident_bytes",
        "kura_memory_pressure_state",
        "kura_memory_transient_reserved_bytes",
        "kura_response_stream_reserved_bytes",
        "kura_response_stream_waiters",
        "kura_response_stream_active",
    ):
        def value(sample):
            values = [v for k, v in sample["metrics"].items() if k.split("{")[0] == name]
            return sum(values) if values else None

        peaks = [value(sample) for sample in load + recovery]
        gauges[name] = {
            "idle": value(idle),
            "peak_including_recovery": max((v for v in peaks if v is not None), default=None),
            "settled": value(recovery[-1]),
        }
    counter_families = (
        "kura_artifact_read_bytes_total_total",
        "kura_artifact_write_bytes_total_total",
        "kura_artifact_egress_bytes_total_total",
        "kura_segment_refresh_bytes_total_total",
        "kura_response_stream_admissions_total_total",
    )
    deltas = {
        name: value - idle["metrics"].get(name, 0)
        for name, value in recovery[-1]["metrics"].items()
        if name.split("{")[0] in counter_families
    }
    return {
        "directory": str(path),
        "load": result,
        "gauges": gauges,
        "counter_deltas": deltas,
        "cpu_seconds": round(cpu, 3),
        "cpu_seconds_per_completed_gib": cpu / (completed_bytes / 1024**3) if completed_bytes else None,
        "received_grpc_bytes_per_completed_byte": result["received_grpc_bytes"] / completed_bytes if completed_bytes else None,
        "disk_allocated_kib": int((path / "disk.txt").read_text().split()[0]),
    }


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("runs", nargs="+", type=Path)
args = parser.parse_args()
print(json.dumps([summarize(path) for path in args.runs], indent=2))
