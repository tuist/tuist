#!/usr/bin/env python3
"""Run the shipped Kura probe-loop expression through promtool.

Each case is its own Kura instance with one or two pods. Counters advance every
five minutes for 32 hours. The expression is checked at 26h, where its [24h]
increases are exact multiples of the per-step increments (288 steps a day).
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

DIRECTORY = Path(__file__).resolve().parent
[rule] = json.loads((DIRECTORY / "kura-probe-loop-alert-rules.json").read_text())

condition = next(d for d in rule["data"] if d["refId"] == rule["condition"])["model"]
assert condition["type"] == "threshold" and condition["expression"] == "A"
assert condition["conditions"][0]["evaluator"] == {"params": [0], "type": "gt"}
# Policy routing to Slack only: no contact point on the rule and no page.
assert rule["notification_settings"] is None
assert rule["labels"] == {"severity": "warning"}
assert rule["ruleGroup"] == "Cache" and rule["isPaused"] is False
assert rule["noDataState"] == "OK"
query = next(d for d in rule["data"] if d["refId"] == "A")
assert query["datasourceUid"] == "cg3i1jh2k1v5sb"  # production Pulse
# The 24h windows need the query's time range to cover them.
assert query["relativeTimeRange"]["from"] >= 24 * 3600
expr = query["model"]["expr"]

STEPS = 32 * 12  # five-minute samples over 32 hours
PER_DAY = 288

# name -> {pod ordinal -> (not_found, ok, writes or None for no series)}, as
# increments per five-minute step; x288 is the 24h increase.
CASES = {
    # The 2026-11-27 case: ~25M misses, no hits, no write series.
    "loop": ({1: (90000, 0, None), 0: (5, 0, 0)}, True),
    # A genuinely low hit rate that writes a lot (seen on 2026-11-27): a real
    # cache problem, so it must stay in the fleet number.
    "low-hit-writing": ({1: (13000, 5800, 600)}, False),
    # Busy and healthy.
    "healthy": ({0: (4700, 110000, 50), 1: (4700, 110000, 50)}, False),
    # Volume floor: 864K misses a day is under 1M.
    "below-floor": ({1: (3000, 0, 0)}, False),
    # Hit-share boundary: 1.48% is a cache that hits, 0.5% is not.
    "hits-1.5pct": ({1: (10000, 150, 0)}, False),
    "hits-0.5pct": ({1: (10000, 50, 0)}, True),
    # Write-ratio boundary: 2 writes per 100 reads clears it, 0.5 does not.
    # The looping client's own CI wrote up to 28 per 10K on 2026-11-25, so the
    # threshold sits well above that and well below real low-hit writers
    # (the lowest on 2026-11-27: 1,575 per 10K).
    "writes-2-per-100": ({1: (10000, 0, 200)}, False),
    "writes-0.5-per-100": ({1: (10000, 0, 50)}, True),
    # Reads on one replica, writes on the other: per instance this client
    # writes, so a per-pod rule would wrongly flag pod 1.
    "writes-on-other-replica": ({1: (10000, 0, None), 0: (0, 0, 500)}, False),
    # Misses split across replicas, each under the floor (576K), together
    # over it (1.15M): only a per-instance rule sees the loop.
    "split-across-replicas": ({0: (2000, 0, 0), 1: (2000, 0, 0)}, True),
    # No ok series at all must not hide a loop.
    "no-ok-series": ({1: (10000, None, None)}, True),
}


def counter(name, labels, increment):
    encoded = ",".join(f'{key}="{value}"' for key, value in labels.items())
    return {"series": f"{name}{{{encoded}}}", "values": f"0+{increment}x{STEPS}"}


series = []
for instance, (pods, _) in CASES.items():
    for ordinal, (not_found, ok, writes) in pods.items():
        base = {"cluster": "tuist-production", "pod": f"kura-{instance}-eu-west-1-{ordinal}"}
        series.append(counter("kura_artifact_reads_total_total", {**base, "result": "not_found"}, not_found))
        if ok is not None:
            series.append(counter("kura_artifact_reads_total_total", {**base, "result": "ok"}, ok))
        if writes is not None:
            series.append(counter("kura_artifact_writes_total_total", {**base, "result": "ok"}, writes))
# Another cluster's loop is out of scope for the production rule.
series.append(counter("kura_artifact_reads_total_total",
                      {"cluster": "tuist-staging", "pod": "kura-staging-loop-eu-west-1-0", "result": "not_found"},
                      90000))

flagged = [instance for instance, (_, fires) in CASES.items() if fires]
expected_values = [
    {"labels": f'{{cluster="tuist-production",kura_instance="{instance}-eu-west-1"}}',
     "value": sum(pod[0] for pod in CASES[instance][0].values()) * PER_DAY}
    for instance in flagged
]
labels = lambda instance: {"cluster": "tuist-production", "kura_instance": f"{instance}-eu-west-1",
                           "severity": "warning"}

tests = {
    "rule_files": ["rules.json"],
    "evaluation_interval": "5m",
    "tests": [{
        "interval": "5m",
        "input_series": series,
        # The alert value is the instance's 24h not_found count.
        "promql_expr_test": [{"expr": expr, "eval_time": "26h", "exp_samples": expected_values}],
        # By 32h every case has held its full-window answer for 8h, past the
        # 6h pending period.
        "alert_rule_test": [{"eval_time": "32h", "alertname": rule["uid"], "exp_alerts": [
            {"exp_labels": labels(instance)} for instance in flagged
        ]}],
    }],
}
rules = {"groups": [{"name": rule["ruleGroup"], "interval": "5m", "rules": [
    {"alert": rule["uid"], "expr": f"({expr}) > 0", "for": rule["for"], "labels": rule["labels"]},
]}]}

with tempfile.TemporaryDirectory() as temporary:
    temporary = Path(temporary)
    (temporary / "rules.json").write_text(json.dumps(rules))
    (temporary / "tests.json").write_text(json.dumps(tests))
    promtool = os.environ.get("PROMTOOL", "promtool")
    subprocess.run([promtool, "check", "rules", "rules.json"], cwd=temporary, check=True)
    subprocess.run([promtool, "test", "rules", "tests.json"], cwd=temporary, check=True)
print(f"probe-loop rule flags {', '.join(flagged)} and nothing else")
