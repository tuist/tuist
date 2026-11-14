"""Credential-free checks for the private staging Grafana chart."""

import json
import pathlib
import subprocess
import unittest

import yaml


CHART = pathlib.Path(__file__).resolve().parent


class ChartTest(unittest.TestCase):
    def test_private_readonly_staging_contract(self):
        rendered = subprocess.check_output(
            ["helm", "template", "greptime-grafana-staging", str(CHART), "-n", "observability"],
            text=True,
        )
        objects = {obj["kind"]: obj for obj in yaml.safe_load_all(rendered)}
        self.assertEqual(set(objects), {"ExternalSecret", "ConfigMap", "Service", "Ingress", "NetworkPolicy", "Deployment"})
        secret = objects["ExternalSecret"]["spec"]
        self.assertEqual(secret["data"], [{"secretKey": "dashboardPassword", "remoteRef": {"key": "PULSE_TOKEN/password"}}])
        sources = yaml.safe_load(objects["ConfigMap"]["data"]["datasources.yaml"])["datasources"]
        self.assertEqual(len(sources), 2)
        for source in sources:
            self.assertEqual(source["basicAuthUser"], "dashboard")
            self.assertTrue(source["basicAuth"])
            self.assertFalse(source["editable"])
            self.assertEqual(source["secureJsonData"]["basicAuthPassword"], "$GREPTIME_DASHBOARD_PASSWORD")
            self.assertEqual(source["secureJsonData"]["httpHeaderValue1"], "public")
        self.assertEqual(sources[0]["url"], "http://pulse.observability.svc.cluster.local:4000/v1/prometheus")
        self.assertEqual(sources[1]["jsonData"]["defaultDatabase"], "public")
        self.assertEqual(objects["Service"]["spec"]["type"], "ClusterIP")
        ingress = objects["Ingress"]
        self.assertEqual(ingress["spec"]["ingressClassName"], "tailscale")
        self.assertNotIn("annotations", ingress["metadata"])
        peers = objects["NetworkPolicy"]["spec"]["ingress"][0]["from"]
        self.assertEqual(len(peers), 1)
        self.assertEqual(peers[0]["namespaceSelector"]["matchLabels"], {"kubernetes.io/metadata.name": "tailscale-operator"})
        self.assertEqual(peers[0]["podSelector"]["matchLabels"], {
            "tailscale.com/managed": "true",
            "tailscale.com/parent-resource-type": "ingress",
            "tailscale.com/parent-resource": "greptime-grafana-staging",
            "tailscale.com/parent-resource-ns": "observability",
        })
        pod = objects["Deployment"]["spec"]["template"]["spec"]
        self.assertFalse(pod["automountServiceAccountToken"])
        env = {entry["name"]: entry for entry in pod["containers"][0]["env"]}
        for key, value in {
            "GF_AUTH_PROXY_ENABLED": "true",
            "GF_AUTH_PROXY_HEADER_NAME": "Tailscale-User-Login",
            "GF_USERS_AUTO_ASSIGN_ORG_ROLE": "Viewer",
            "GF_AUTH_ANONYMOUS_ENABLED": "false",
            "GF_AUTH_BASIC_ENABLED": "false",
            "GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION": "true",
        }.items():
            self.assertEqual(env[key]["value"], value)
        self.assertIn("valueFrom", env["GREPTIME_DASHBOARD_PASSWORD"])
        dashboard = json.loads(objects["ConfigMap"]["data"]["staging.json"])
        self.assertEqual([panel["type"] for panel in dashboard["panels"]], ["timeseries", "logs", "table", "traces"])
        self.assertFalse(dashboard["editable"])

    def test_other_environments_and_namespaces_rejected(self):
        for args in [["-n", "observability", "--set", "environment=production"], ["-n", "tuist-staging"]]:
            result = subprocess.run(["helm", "template", "test", str(CHART), *args], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("staging-only", result.stderr)


if __name__ == "__main__":
    unittest.main()
