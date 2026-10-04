#!/usr/bin/env python3
"""Check rendered staging node-exporter scheduling (requires Helm and PyYAML)."""

import pathlib
import subprocess
import unittest

import yaml

CHART = pathlib.Path(__file__).resolve().parent / "k8s-monitoring"
ROLE_TAINTS = [
    ("node-role.kubernetes.io/control-plane", ""),
    ("tuist.dev/stateful", "clickhouse"),
    ("tuist.dev/stable-egress", "true"),
    ("tuist.dev/runner-cache", "true"),
    ("tuist.dev/kura-cache", "true"),
    ("tuist.dev/runner-tier", "bare-metal"),
    ("tuist.dev/rack-edge", "ber1"),
]


def tolerates(toleration, key, value=""):
    if toleration.get("effect", "") not in ("", "NoSchedule"):
        return False
    if toleration.get("operator", "Equal") == "Exists":
        return toleration.get("key", "") in ("", key)
    return toleration.get("key") == key and toleration.get("value", "") == value


class StagingMonitoringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["helm", "dependency", "build", str(CHART)], check=True, stdout=subprocess.PIPE)
        rendered = subprocess.check_output(
            ["helm", "template", "k8s-monitoring", str(CHART), "-f", str(CHART / "values-staging.yaml")],
            text=True,
        )
        exporter = next(
            r
            for r in yaml.safe_load_all(rendered)
            if r and r["kind"] == "DaemonSet" and r["metadata"]["name"] == "k8s-monitoring-node-exporter"
        )
        cls.tolerations = exporter["spec"]["template"]["spec"].get("tolerations", [])

    def test_unreachable_nodes_do_not_remain_desired_exporter_targets(self):
        for key in ["node.kubernetes.io/unreachable", "node.kubernetes.io/not-ready"]:
            with self.subTest(key=key):
                self.assertFalse(any(tolerates(t, key) for t in self.tolerations))

    def test_reachable_infrastructure_roles_keep_host_metrics(self):
        for key, value in ROLE_TAINTS:
            with self.subTest(key=key):
                self.assertTrue(any(tolerates(t, key, value) for t in self.tolerations))


if __name__ == "__main__":
    unittest.main()
