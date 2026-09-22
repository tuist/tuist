#!/usr/bin/env python3
"""Run promtool against the exact expression shipped in the Grafana artifact."""

import json
from pathlib import Path
import subprocess
import tempfile


directory = Path(__file__).resolve().parent
rule = json.loads((directory / "kura-availability-alert-rules.json").read_text())[0]
query = next(item["model"]["expr"] for item in rule["data"] if item["refId"] == "A")
assert rule["condition"] == "B"
assert next(item["model"]["expression"] for item in rule["data"] if item["refId"] == "B") == "$A > 0"
assert rule["isPaused"] is True
assert rule["noDataState"] == "NoData" and rule["execErrState"] == "Error"
assert "notification_settings" not in rule
assert rule["labels"]["affected_service"] == "Cache", "Match the case-sensitive IRM component ID"

tests = []
for name, desired, ready, pending, firing in [
    ("healthy", "2+0x6", "2+0x6", False, False),
    ("one_ready", "2+0x6", "1+0x6", False, False),
    ("outage", "2+0x6", "0+0x6", False, True),
    ("scaled_down", "0+0x6", "0+0x6", False, False),
    ("brief_rollout", "2+0x6", "2 0 2 2 2 2 2", False, False),
    ("recovered", "2+0x6", "0 0 0 2 2 2 2", True, False),
]:
    labels = {"cluster": "tuist-production", "namespace": "kura", "statefulset": name}
    encoded = ",".join(f'{key}="{value}"' for key, value in labels.items())
    series = [
        {"series": f"kube_statefulset_replicas{{{encoded}}}", "values": desired},
        {"series": f"kube_statefulset_status_replicas_ready{{{encoded}}}", "values": ready},
    ]
    checks = []
    for at, should_fire in [("1m", False), ("2m", pending or firing), ("4m", firing)]:
        checks.append({
            "eval_time": at,
            "alertname": "KuraInstanceHasNoReadyReplicas",
            "exp_alerts": [{"exp_labels": {**labels, **rule["labels"]}}] if should_fire else [],
        })
    tests.append({"name": name, "interval": "1m", "input_series": series, "alert_rule_test": checks})

# Missing readiness is unknown, not a fabricated zero. A non-Kura workload must
# never enter this alert. The bool expression keeps a healthy sample explicit.
tests.append({
    "name": "missing_and_unrelated_series",
    "interval": "1m",
    "input_series": [
        {"series": 'kube_statefulset_replicas{namespace="kura",statefulset="missing"}', "values": "2+0x6"},
        {"series": 'kube_statefulset_replicas{namespace="other",statefulset="other"}', "values": "2+0x6"},
        {"series": 'kube_statefulset_status_replicas_ready{namespace="other",statefulset="other"}', "values": "0+0x6"},
    ],
    "promql_expr_test": [{"expr": query, "eval_time": "4m", "exp_samples": []}],
})
tests.append({
    "name": "cluster_label_absent",
    "interval": "1m",
    "input_series": [
        {"series": 'kube_statefulset_replicas{namespace="kura",statefulset="no-cluster"}', "values": "2+0x6"},
        {"series": 'kube_statefulset_status_replicas_ready{namespace="kura",statefulset="no-cluster"}', "values": "0+0x6"},
    ],
    "alert_rule_test": [{"eval_time": "2m", "alertname": "KuraInstanceHasNoReadyReplicas", "exp_alerts": [
        {"exp_labels": {"namespace": "kura", "statefulset": "no-cluster", **rule["labels"]}},
    ]}],
})

with tempfile.TemporaryDirectory(prefix="kura-alert-") as temporary:
    root = Path(temporary)
    rules = root / "rules.json"
    rules.write_text(json.dumps({"groups": [{"name": "Cache", "rules": [{
        "alert": "KuraInstanceHasNoReadyReplicas", "expr": f"({query}) > 0",
        "for": rule["for"], "labels": rule["labels"],
    }]}]}))
    fixture = root / "tests.json"
    fixture.write_text(json.dumps({"rule_files": [str(rules)], "evaluation_interval": "1m", "tests": tests}))
    subprocess.run(["promtool", "check", "rules", str(rules)], check=True)
    subprocess.run(["promtool", "test", "rules", str(fixture)], check=True)
