#!/usr/bin/env python3
"""Render checks; opt into upgrade tests only on a disposable K3s cluster."""

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

CHART = Path(__file__).resolve().parent
SERVICE = "tailnet-validation-tuist-clickhouse-tailnet"
KUBECTL = os.environ.get("KUBECTL", "kubectl")


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def render(environment="canary", overrides=()):
    values = (["values-self-hosted-ci.yaml"] if environment is None else
              ["values-managed-common.yaml", f"values-managed-{environment}.yaml"])
    command = ["helm", "template", "tailnet-validation", str(CHART)]
    for value in (*values, "values-ci.yaml"):
        command.extend(["-f", str(CHART / value)])
    for override in overrides:
        command.extend(["--set", override])
    return run(*command)


def tailnet_service(output):
    return next((doc for doc in output.split("---\n")
                 if "kind: Service\n" in doc and f"  name: {SERVICE}\n" in doc), "")


class ClickHouseTailnetTests(unittest.TestCase):
    def test_managed_proxygroups_expose_only_http_without_nodeports(self):
        for environment in ("staging", "canary", "production"):
            with self.subTest(environment=environment):
                service = tailnet_service(render(environment))
                self.assertIn("  type: LoadBalancer\n", service)
                self.assertIn("  loadBalancerClass: tailscale\n", service)
                self.assertIn("  allocateLoadBalancerNodePorts: false\n", service)
                self.assertIn("      nodePort: null\n", service)
                self.assertEqual(re.findall(r"^    - name: (.+)$", service, re.M), ["http"])
                self.assertIn("      port: 8123\n      targetPort: 8123\n", service)
                self.assertIn('tailscale.com/proxy-group: "tailnet-ingress"', service)

    def test_standalone_proxy_remains_clusterip(self):
        service = tailnet_service(render(overrides=["clickhouse.managed.tailscale.proxyGroup="]))
        self.assertIn('tailscale.com/expose: "true"', service)
        self.assertNotIn("type: LoadBalancer", service)
        self.assertNotIn("allocateLoadBalancerNodePorts:", service)
        self.assertNotIn("nodePort:", service)

    def test_disabled_tailnet_and_self_hosted_defaults_have_no_tailnet_service(self):
        self.assertFalse(tailnet_service(render(overrides=["clickhouse.managed.tailscale.enabled=false"])))
        self.assertFalse(tailnet_service(render(environment=None)))

    @unittest.skipUnless(os.environ.get("TUIST_HELM_TEST_UPGRADE") == "1",
                         "Set TUIST_HELM_TEST_UPGRADE=1 only on disposable K3s")
    def test_existing_allocation_is_removed_without_recreating_service(self):
        nodes = json.loads(run(KUBECTL, "get", "nodes", "-o", "json"))["items"]
        self.assertTrue(nodes and all("k3s" in node["status"]["nodeInfo"]["kubeletVersion"]
                                     for node in nodes), "Upgrade tests require disposable K3s")
        hardened = tailnet_service(render())
        legacy = re.sub(r"^.*(?:allocateLoadBalancerNodePorts:|nodePort:).*$\n?", "", hardened, flags=re.M)
        # Test auto-upgrade inheritance for both Helm 3-style client updates
        # and Helm 4 server-side apply, not just fresh installs.
        for server_side in ("false", "true"):
            with self.subTest(server_side=server_side), tempfile.TemporaryDirectory() as directory:
                namespace = f"tailnet-upgrade-{server_side}"
                chart = Path(directory)
                (chart / "templates").mkdir()
                (chart / "Chart.yaml").write_text("apiVersion: v2\nname: tailnet-test\nversion: 0.1.0\n")
                manifest = chart / "templates/service.yaml"
                manifest.write_text(legacy)
                run(KUBECTL, "create", "namespace", namespace)
                try:
                    run("helm", "install", "tailnet-validation", directory, "-n", namespace,
                        f"--server-side={server_side}")

                    def live():
                        return json.loads(run(KUBECTL, "-n", namespace, "get", "service", SERVICE, "-o", "json"))

                    before = live()
                    self.assertGreater(before["spec"]["ports"][0]["nodePort"], 0)
                    manifest.write_text(hardened)
                    run("helm", "upgrade", "tailnet-validation", directory, "-n", namespace)
                    after = live()
                    self.assertIs(after["spec"]["allocateLoadBalancerNodePorts"], False)
                    self.assertFalse(any(port.get("nodePort") for port in after["spec"]["ports"]))
                    self.assertEqual(after["metadata"]["uid"], before["metadata"]["uid"])
                    self.assertEqual(after["metadata"]["annotations"], before["metadata"]["annotations"])
                    for field in ("clusterIP", "clusterIPs", "selector", "loadBalancerClass"):
                        self.assertEqual(after["spec"][field], before["spec"][field])
                    self.assertEqual(after["spec"]["ports"], [{"name": "http", "port": 8123,
                                                              "protocol": "TCP", "targetPort": 8123}])
                    # Another ordinary upgrade must not restore an allocation.
                    run("helm", "upgrade", "tailnet-validation", directory, "-n", namespace)
                    self.assertFalse(any(port.get("nodePort") for port in live()["spec"]["ports"]))
                finally:
                    run(KUBECTL, "delete", "namespace", namespace, "--wait=false")


if __name__ == "__main__":
    unittest.main()
