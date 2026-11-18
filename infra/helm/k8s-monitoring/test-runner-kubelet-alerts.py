#!/usr/bin/env python3
"""Exercise the shipped PromQL, thresholds and pending periods with promtool."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

DIRECTORY = Path(__file__).resolve().parent
rules = json.loads((DIRECTORY / "runner-kubelet-alert-rules.json").read_text())
assert len(rules) == 4
for rule in rules:
    assert rule["isPaused"] and rule["noDataState"] == "OK"
    assert rule["execErrState"] == "Error"
    assert "notification_settings" not in rule
    assert rule["condition"] == "C"
    condition = next(item["model"] for item in rule["data"] if item["refId"] == "C")
    assert condition["type"] == "threshold" and condition["expression"] == "A"
    assert condition["conditions"][0]["evaluator"]["type"] == "gt"

prometheus_rules = []
for rule in rules:
    query = next(item for item in rule["data"] if item["refId"] == "A")
    if query["datasourceUid"] != "grafanacloud-prom":
        # LogQL is replayed separately with Loki; promtool cannot evaluate it.
        assert rule["uid"] == "linux-kubelet-restart-loop"
        threshold = next(item["model"] for item in rule["data"] if item["refId"] == "C")
        assert threshold["conditions"][0]["evaluator"]["params"] == [3]
        assert rule["for"] == "5m"
        continue
    prometheus_rules.append({
        "alert": rule["uid"], "expr": f'({query["model"]["expr"]}) > 0',
        "for": rule["for"], "labels": rule["labels"],
    })

UNREACHABLE = "runner-kubelet-unreachable"
LEASE = "runner-kubelet-lease-stale"
INVENTORY = "runner-kubelet-inventory-missing"
CLUSTERS = ["tuist-staging", "tuist-canary", "tuist-production"]


def series(metric, labels, values):
    encoded = ",".join(f"{key}={json.dumps(value)}" for key, value in labels.items())
    return {"series": f"{metric}{{{encoded}}}", "values": values}


def inventory(cluster, node="host", pool="runners-linux", values="1+0x30"):
    return series("kube_node_labels", {
        "cluster": cluster, "node": node, "label_node_cluster_x_k8s_io_pool": pool,
    }, values)


def up(cluster, values):
    return series("up", {
        "cluster": cluster, "node": "host", "job": "integrations/kubernetes/kubelet",
    }, values)


def lease(cluster, values, namespace="kube-node-lease", instance="ksm"):
    return series("kube_lease_renew_time", {
        "cluster": cluster, "lease": "host", "namespace": namespace, "instance": instance,
    }, values)


def test(name, inputs, expectations):
    return {
        "name": name, "interval": "1m", "input_series": inputs,
        "alert_rule_test": [
            {"eval_time": when, "alertname": rule["alert"], "exp_alerts": [
                {"exp_labels": dict(labels, **rule["labels"])}
                for alert, labels in firing if alert == rule["alert"]
            ]}
            for when, firing in expectations for rule in prometheus_rules
        ],
    }


tests = []
for cluster in CLUSTERS:
    labels = {"cluster": cluster, "node": "host"}
    # A healthy same-named node in another cluster must not mask a failure.
    peers = [metric for other in CLUSTERS if other != cluster for metric in [
        inventory(other), up(other, "1+0x30"), lease(other, "0+60x30"),
    ]]
    base = peers + [inventory(cluster)]
    cases = [
        ("healthy", [up(cluster, "1+0x30"), lease(cluster, "0+60x30")], [], "20m"),
        ("dead_kubelet", [up(cluster, "1 0+0x29"), lease(cluster, "0+0x30")],
         [(UNREACHABLE, labels), (LEASE, labels)], "11m"),
        ("missing_target", [lease(cluster, "0+60x30")], [(UNREACHABLE, labels)], "6m"),
        ("stuck_heartbeat_but_scrape_healthy", [up(cluster, "1+0x30"), lease(cluster, "0+0x30")],
         [(LEASE, labels)], "6m"),
        ("missing_lease", [up(cluster, "1+0x30")], [(LEASE, labels)], "3m"),
        ("lease_age_exactly_two_minutes", [up(cluster, "1+0x30"), lease(cluster, "-120+60x30")], [], "6m"),
        ("lease_age_over_two_minutes", [up(cluster, "1+0x30"), lease(cluster, "-121+60x30")],
         [(LEASE, labels)], "3m"),
        ("leader_lease_cannot_mask_missing_node_lease", [up(cluster, "1+0x30"),
         lease(cluster, "0+60x30", namespace="kube-system")], [(LEASE, labels)], "3m"),
        ("brief_scrape_failure", [up(cluster, "1+0x2 0 1+0x26"), lease(cluster, "0+60x30")], [], "10m"),
        ("duplicate_ksm_latest_renewal_wins", [up(cluster, "1+0x30"), lease(cluster, "0+0x30"),
         lease(cluster, "0+60x30", instance="ksm-new")], [], "10m"),
    ]
    for name, inputs, firing, when in cases:
        tests.append(test(f"{cluster}_{name}", base + inputs, [(when, firing)]))
    tests.append(test(f"{cluster}_pending_and_recovery", base + [
        up(cluster, "1 0+0x10 1+0x19"), lease(cluster, "0+0x11 720+60x18"),
    ], [("2m", []), ("5m", []),
        ("10m", [(UNREACHABLE, labels), (LEASE, labels)]), ("12m", [])]))
    tests.append(test(f"{cluster}_node_removed_during_pending", peers + [
        inventory(cluster, values="1 stale"),
        inventory(cluster, node="control", pool="general"),
    ], [("10m", [])]))
    tests.append(test(f"{cluster}_tart_excluded", peers + [
        inventory(cluster, pool="runners-macos"),
    ], [("10m", [])]))
    tests.append(test(f"{cluster}_inventory_missing", peers + [
        inventory(cluster, node="control", pool="general", values="1 stale"),
    ], [("9m", []), ("10m", [(INVENTORY, {"cluster": cluster})])]))

tests.append(test("complete_collector_outage", [], [
    ("10m", [(INVENTORY, {"cluster": cluster}) for cluster in CLUSTERS]),
]))

with tempfile.TemporaryDirectory(prefix="runner-kubelet-alerts-") as temporary:
    temporary = Path(temporary)
    rule_file = temporary / "rules.json"
    rule_file.write_text(json.dumps({"groups": [{
        "name": "Runner kubelet health", "interval": "1m", "rules": prometheus_rules,
    }]}))
    test_file = temporary / "tests.json"
    test_file.write_text(json.dumps({
        "rule_files": [str(rule_file)], "evaluation_interval": "1m", "tests": tests,
    }))
    promtool = os.environ.get("PROMTOOL", "promtool")
    subprocess.run([promtool, "check", "rules", str(rule_file)], check=True)
    subprocess.run([promtool, "test", "rules", str(test_file)], check=True)
print(f"Passed {len(tests)} kubelet alert scenarios; all rules remain paused.")
