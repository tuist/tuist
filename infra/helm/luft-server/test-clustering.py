#!/usr/bin/env python3
"""Offline Helm and release-env regressions; no Kubernetes access or real secrets."""

import subprocess
import unittest
from pathlib import Path

CHART = Path(__file__).resolve().parent
ENV_SCRIPT = CHART.parents[2] / "luft-server/rel/env.sh.eex"


def render(*overrides, production=False):
    command = ["helm", "template", "luft-check", str(CHART), "--namespace", "luft"]
    if production:
        command += ["-f", str(CHART / "values-production.yaml")]
    command += ["-f", str(CHART / "values-ci.yaml")]
    for override in overrides:
        command += ["--set", override]
    return subprocess.run(command, capture_output=True, text=True)


def document(output, source):
    return next((doc for doc in output.split("---\n")
                 if f"# Source: luft-server/templates/{source}\n" in doc), "")


class ChartTests(unittest.TestCase):
    def test_default_single_replica(self):
        result = render()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("replicas: 1", result.stdout)
        for absent in ("DNS_CLUSTER_QUERY", "RELEASE_COOKIE", "containerPort: 9100",
                       "clusterIP: None"):
            self.assertNotIn(absent, result.stdout)
        self.assertNotIn("kind: ExternalSecret", result.stdout)

    def test_production_cluster_wiring(self):
        result = render(production=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        deployment = document(result.stdout, "deployment.yaml")
        for expected in ("replicas: 2", "name: DNS_CLUSTER_QUERY",
                         'value: "luft-check-headless.luft.svc"',
                         "fieldPath: status.podIP", "name: RELEASE_COOKIE",
                         'name: "luft-server-cluster-cookie"', 'key: "release-cookie"',
                         "containerPort: 4369", "containerPort: 9100"):
            self.assertIn(expected, deployment)
        self.assertNotIn("optional:", deployment)
        headless = document(result.stdout, "service-headless.yaml")
        self.assertIn("clusterIP: None", headless)
        self.assertIn("publishNotReadyAddresses: true", headless)
        self.assertIn("app.kubernetes.io/instance: luft-check", headless)
        public = document(result.stdout, "service.yaml")
        self.assertNotIn("4369", public)
        self.assertNotIn("9100", public)
        self.assertNotIn("kind: Secret\n", result.stdout)
        cookie = document(result.stdout, "cluster-externalsecret.yaml")
        for expected in ("name: luft-server-cluster-cookie", "refreshPolicy: OnChange",
                         "deletionPolicy: Retain", "name: onepassword",
                         'key: "LUFT_SERVER_CLUSTER_COOKIE/password"',
                         '"release-cookie":', 'fail "The Luft cluster cookie must not be empty"'):
            self.assertIn(expected, cookie)
        self.assertNotIn("refreshInterval:", cookie)

    def test_cluster_cookie_external_secret_is_optional_and_configurable(self):
        result = render("cluster.externalSecret.enabled=false", production=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(document(result.stdout, "cluster-externalsecret.yaml"), "")
        result = render("cluster.cookieExistingSecret=custom-cookie",
                        "cluster.cookieSecretKey=custom-key",
                        "cluster.externalSecret.item=CUSTOM_COOKIE",
                        "cluster.externalSecret.field=value", production=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        cookie = document(result.stdout, "cluster-externalsecret.yaml")
        self.assertIn("name: custom-cookie", cookie)
        self.assertIn('"custom-key":', cookie)
        self.assertIn('key: "CUSTOM_COOKIE/value"', cookie)

    def test_private_distribution_rules(self):
        result = render(production=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        policy = document(result.stdout, "networkpolicy.yaml")
        ingress, egress = policy.split("  ingress:\n")[1].split("  egress:\n")
        self.assertIn("port: 8080", ingress.split("    - from:")[1])
        self.assertNotIn("4369", ingress.split("    - from:")[1])
        for section in (ingress, egress):
            peer = section.split("port: 4369")[0].split("- podSelector:")[-1]
            self.assertIn("app.kubernetes.io/name: luft-server", peer)
            self.assertIn("app.kubernetes.io/instance: luft-check", peer)
            self.assertNotIn("namespaceSelector", peer)
            self.assertEqual(section.count("port: 4369"), 1)
            self.assertEqual(section.count("port: 9100"), 1)
        self.assertIn("except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]", egress)
        self.assertIn("port: 443", egress)

    def test_invalid_cluster_settings(self):
        for overrides, message in (
            (("cluster.enabled=false",), "Multiple Luft replicas require"),
            (("cluster.cookieExistingSecret=",), "cluster.cookieExistingSecret is required"),
            (("cluster.cookieExistingSecret=   ",), "cluster.cookieExistingSecret is required"),
            (("cluster.cookieSecretKey=",), "cluster.cookieSecretKey is required"),
            (("networkPolicy.enabled=false",), "Clustering requires networkPolicy.enabled"),
        ):
            with self.subTest(overrides=overrides):
                result = render(*overrides, production=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)


class ReleaseEnvTests(unittest.TestCase):
    def run_env(self, **env):
        # Isolate tests from the orb's environment; use only a disposable cookie.
        return subprocess.run(
            ["/bin/sh", "-c", '. "$1"; printf "%s\\n" "$RELEASE_DISTRIBUTION" '
             '"$RELEASE_NODE" "$ELIXIR_ERL_OPTIONS"', "test", str(ENV_SCRIPT)],
            env={"RELEASE_COMMAND": "start", **env}, capture_output=True, text=True,
        )

    def test_single_replica_disables_distribution(self):
        result = self.run_env()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "none\n\n\n")

    def test_cluster_sets_node_and_fixed_listener(self):
        result = self.run_env(DNS_CLUSTER_QUERY="peer.luft.svc", POD_IP="10.1.2.3",
                              RELEASE_COOKIE="test-only-cookie", ELIXIR_ERL_OPTIONS="+sbwt none")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "name\nluft_server@10.1.2.3\n+sbwt none "
                         "-kernel inet_dist_listen_min 9100 inet_dist_listen_max 9100\n")

    def test_missing_or_invalid_cookie_fails_closed(self):
        for command in ("start", "start_iex", "daemon", "daemon_iex"):
            for cookie in ("", " ", "test\ncookie"):
                result = self.run_env(DNS_CLUSTER_QUERY="peer.luft.svc", POD_IP="10.1.2.3",
                                      RELEASE_COOKIE=cookie, RELEASE_COMMAND=command)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("requires an explicit private RELEASE_COOKIE", result.stderr)
                self.assertNotIn("test\ncookie", result.stderr)

    def test_missing_pod_ip_fails(self):
        result = self.run_env(DNS_CLUSTER_QUERY="peer.luft.svc")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires POD_IP", result.stderr)

    def test_explicit_distribution_also_requires_cookie(self):
        result = self.run_env(RELEASE_DISTRIBUTION="name")
        self.assertNotEqual(result.returncode, 0)

    def test_remote_command_keeps_ephemeral_listener(self):
        result = self.run_env(DNS_CLUSTER_QUERY="peer.luft.svc", POD_IP="10.1.2.3",
                              RELEASE_COOKIE="test-only-cookie", RELEASE_COMMAND="remote")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("inet_dist_listen", result.stdout)


if __name__ == "__main__":
    unittest.main()
