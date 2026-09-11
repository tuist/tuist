#!/usr/bin/env python3
"""Summarize paired gateway measurements, preserving placement and round."""
import argparse
import gzip
import json
import math
from pathlib import Path
import random
import statistics as stats


def client_counters(diagnostics):
    values = {}
    for filename, raw in diagnostics.items():
        lines = raw.splitlines()
        if filename.endswith("cpu.stat"):
            values.update({k: int(v) for k, v in (line.split() for line in lines)})
        elif filename.endswith(("snmp", "netstat")):
            for index in range(0, len(lines), 2):
                names, numbers = lines[index].split(), lines[index + 1].split()
                values.update({names[0].rstrip(":") + "." + k: int(v)
                               for k, v in zip(names[1:], numbers[1:])})
    return values


def delta(before, after):
    return {key: value - before[key] for key, value in after.items() if key in before}


def distribution(values):
    return {"median": stats.median(values), "min": min(values), "max": max(values)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    rows = []
    for filename in args.inputs:
        opener = gzip.open if filename.endswith(".gz") else open
        with opener(filename, "rt") as source:
            rows.extend(json.loads(line) for line in source if line.strip())
    groups, details = {}, []
    for row in rows:
        key = (row["protocol"], row["operation"], row["size_bytes"], row["concurrency"])
        pair = (row["backend"], row["round"])
        paths = groups.setdefault(key, {}).setdefault(pair, {})
        if row["label"] in paths:
            raise ValueError(f"duplicate case: {key} {pair} {row['label']}")
        paths[row["label"]] = row
        counters = delta(client_counters(row.get("diagnostics_before", {})),
                         client_counters(row.get("diagnostics_after", {})))
        servers = {role: delta(before, row["server_counters_after"][role])
                   for role, before in row.get("server_counters_before", {}).items()}
        full_seconds = range(1, math.floor(row["wall_s"]))
        steady_counts = [row.get("completed_requests_by_second", {}).get(str(s), 0)
                         for s in full_seconds]
        details.append({**{k: v for k, v in row.items()
                           if not k.startswith(("diagnostics_", "server_counters_"))},
                        "client_counter_deltas": counters,
                        "client_cpu_cores": counters["usage_usec"] / 1e6 / row["wall_s"]
                        if "usage_usec" in counters else None,
                        "server_counter_deltas": servers,
                        "steady_mbps": stats.mean(steady_counts) * row["size_bytes"] * 8 / 1e6
                        if steady_counts else None})
    summary = []
    rng = random.Random(20260910)
    for key, pairs in sorted(groups.items()):
        complete = [paths for paths in pairs.values() if set(paths) == {"local", "remote"}]
        changes = [100 * (p["remote"]["successful_mbps"] / p["local"]["successful_mbps"] - 1)
                   for p in complete]
        if not changes:
            continue
        boot = sorted(stats.median(rng.choices(changes, k=len(changes))) for _ in range(10000))
        summary.append({"protocol": key[0], "operation": key[1], "size_bytes": key[2],
                        "concurrency": key[3], "pairs": len(complete),
                        "local_mbps": distribution([p["local"]["successful_mbps"] for p in complete]),
                        "remote_mbps": distribution([p["remote"]["successful_mbps"] for p in complete]),
                        "paired_throughput_change_pct": distribution(changes),
                        "paired_median_bootstrap_95_pct": [boot[249], boot[9749]],
                        "paired_p50_latency_delta_ms": distribution([
                            p["remote"]["p50_ms"] - p["local"]["p50_ms"] for p in complete]),
                        "placements": {backend: distribution([
                            100 * (p["remote"]["successful_mbps"] / p["local"]["successful_mbps"] - 1)
                            for (b, _), p in pairs.items() if b == backend and len(p) == 2])
                            for backend in sorted({b for (b, _), p in pairs.items() if len(p) == 2})}})
    output = {"cases": len(rows), "unpaired_cases": sum(
                  len(paths) for pairs in groups.values() for paths in pairs.values() if len(paths) != 2),
              "requests": sum(r["requests"] for r in rows),
              "errors": sum(r["errors"] for r in rows),
              "timed_payload_gib": sum((r["requests"] - r["errors"]) * r["size_bytes"] for r in rows) / 2**30,
              "summary": summary, "case_details": details}
    Path(args.output).write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps({k: v for k, v in output.items() if k != "case_details"}, indent=2))


if __name__ == "__main__":
    main()
