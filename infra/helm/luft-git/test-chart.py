#!/usr/bin/env python3
"""Offline deployment-boundary checks. No Kubernetes access or credentials."""

import subprocess
import tomllib
import unittest
from pathlib import Path

CHART = Path(__file__).resolve().parent


def render(*overrides):
    command = ["helm", "template", "luft-git-check", str(CHART),
               "--namespace", "luft", "-f", str(CHART / "values-production.yaml"),
               "-f", str(CHART / "values-ci.yaml")]
    for override in overrides:
        command += ["--set", override]
    return subprocess.run(command, capture_output=True, text=True)


def document(output, source):
    return next(doc for doc in output.split("---\n")
                if f"# Source: luft-git/templates/{source}\n" in doc)


class ChartTests(unittest.TestCase):
    def test_private_api_and_loopback_git(self):
        result = render()
        self.assertEqual(result.returncode, 0, result.stderr)
        config = document(result.stdout, "configmap.yaml").split("  enroute.toml: |\n")[1]
        config = tomllib.loads("\n".join(line[4:] for line in config.splitlines()))
        self.assertEqual(config["listen"], {"git": "127.0.0.1:8080", "api": "0.0.0.0:50051"})
        self.assertFalse(config["git"]["create_on_push"])
        self.assertEqual(config["bucket"]["uri"], "s3://luft-git-ci/isolated?region=us-east-1")
        self.assertEqual(config["bucket"]["credentials"], {
            "access_key_id": "${AWS_ACCESS_KEY_ID}",
            "secret_access_key": "${AWS_SECRET_ACCESS_KEY}",
        })
        self.assertEqual(config["node"]["data_dir"], "/var/lib/enroute/data")
        self.assertNotIn("advertise_url", config["node"])
        self.assertEqual(config["node"]["disk_cache"], "5 GiB")
        for forbidden in ("kind: Secret\n", "kind: Ingress\n", "type: LoadBalancer", "nodePort:"):
            self.assertNotIn(forbidden, result.stdout)
        for doc in result.stdout.split("---\n"):
            if "kind: Service\n" in doc:
                self.assertIn("port: 50051", doc)
                self.assertNotIn("7400", doc)
                self.assertNotIn("8080", doc)

    def test_two_sided_same_namespace_network_boundary(self):
        result = render("clientPodLabels.app\\.kubernetes\\.io/instance=custom-luft")
        self.assertEqual(result.returncode, 0, result.stderr)
        policy = document(result.stdout, "networkpolicy.yaml")
        ingress, egress = policy.split("  ingress:\n")[1].split("  egress:\n")
        for expected in ("app.kubernetes.io/name: luft-server",
                         "app.kubernetes.io/instance: custom-luft", "port: 50051"):
            self.assertIn(expected, ingress)
        self.assertNotIn("namespaceSelector", ingress)
        self.assertNotIn("port: 7400", policy)
        self.assertNotIn("port: 8080", policy)
        self.assertIn("k8s-app: kube-dns", egress)
        self.assertIn("except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]", egress)
        self.assertIn("port: 443", egress)
        client = next(doc for doc in result.stdout.split("---\n")
                      if "name: luft-git-check-client\n" in doc)
        self.assertIn("app.kubernetes.io/instance: custom-luft", client)
        self.assertIn("app.kubernetes.io/name: luft-git", client)
        self.assertIn("app.kubernetes.io/instance: luft-git-check", client)
        self.assertNotIn("namespaceSelector", client)
        self.assertEqual(client.count("port:"), 1)

    def test_durable_bounded_single_node_without_secret_ownership(self):
        result = render()
        self.assertEqual(result.returncode, 0, result.stderr)
        statefulset = document(result.stdout, "statefulset.yaml")
        for expected in ("replicas: 1", "whenDeleted: Retain", "whenScaled: Retain",
                         "accessModes: [ReadWriteOnce]", 'storageClassName: "hcloud-volumes"',
                         'storage: "20Gi"', "mountPath: /var/lib/enroute",
                         "runAsNonRoot: true", "readOnlyRootFilesystem: true",
                         "automountServiceAccountToken: false", "checksum/config:",
                         "requests:", "limits:", "memory: 2Gi", "sizeLimit: 256Mi"):
            self.assertIn(expected, statefulset)
        self.assertRegex(statefulset, r'ghcr.io/enroute-sh/enroute@sha256:[a-f0-9]{64}')
        self.assertEqual(statefulset.count('name: "luft-git-ci-s3"'), 2)
        self.assertNotIn("optional:", statefulset)
        self.assertNotIn("emptyDir:", statefulset.split("  volumeClaimTemplates:\n")[1])
        changed = render("bucket.uri=s3://another-isolated-bucket?region=eu-west-1")
        self.assertEqual(changed.returncode, 0, changed.stderr)
        self.assertNotEqual(statefulset.split("checksum/config: ")[1].splitlines()[0],
                            document(changed.stdout, "statefulset.yaml")
                            .split("checksum/config: ")[1].splitlines()[0])

    def test_optional_onepassword_sync_targets_the_consumed_secret(self):
        result = render("bucket.existingSecret=isolated-s3", "externalSecret.item=ISOLATED_S3")
        self.assertEqual(result.returncode, 0, result.stderr)
        secret = document(result.stdout, "externalsecret.yaml")
        for expected in ('name: "isolated-s3"', 'key: "ISOLATED_S3"',
                         "name: onepassword", "kind: ClusterSecretStore",
                         "creationPolicy: Owner", "engineVersion: v2",
                         'AWS_ACCESS_KEY_ID: "{{ .access_key_id | trim }}"',
                         'AWS_SECRET_ACCESS_KEY: "{{ .secret_access_key | trim }}"'):
            self.assertIn(expected, secret)
        statefulset = document(result.stdout, "statefulset.yaml")
        self.assertEqual(statefulset.count('name: "isolated-s3"'), 2)
        disabled = render("externalSecret.enabled=false")
        self.assertEqual(disabled.returncode, 0, disabled.stderr)
        self.assertNotIn("kind: ExternalSecret", disabled.stdout)
        missing = render("externalSecret.item=")
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("externalSecret.item is required", missing.stderr)

    def test_missing_or_unsafe_storage_and_open_client_selector_fail_closed(self):
        for override, message in (
            ("bucket.uri=", "bucket.uri is required"),
            ("bucket.uri=   ", "bucket.uri is required"),
            ("bucket.uri=memory:///", "bucket.uri must use s3://"),
            ("bucket.uri=file:///var/lib/enroute/objects", "bucket.uri must use s3://"),
            ("bucket.uri=s3://bucket?conditional_put=disabled", "conditional_put=disabled is unsafe"),
            ("bucket.existingSecret=", "bucket.existingSecret is required"),
            ("clientPodLabels=null", "clientPodLabels must restrict API access"),
        ):
            with self.subTest(override=override):
                result = render(override)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
