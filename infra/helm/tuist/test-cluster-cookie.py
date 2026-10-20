#!/usr/bin/env python3
"""Offline cookie ownership/wiring checks. Never read or print runtime secrets."""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

CHART = Path(__file__).resolve().parent


def render(values, overrides=()):
    command = ["helm", "template", "cookie-validation", str(CHART)]
    for value in values:
        command.extend(["-f", str(CHART / value)])
    command.extend(["-f", str(CHART / "values-ci.yaml")])
    for override in overrides:
        command.extend(["--set", override])
    return subprocess.run(command, capture_output=True, text=True)


def document(output, source):
    return next(
        (doc for doc in output.split("---\n") if f"# Source: tuist/templates/{source}\n" in doc),
        "",
    )


class ClusterCookieTests(unittest.TestCase):
    def rendered(self, values, overrides=()):
        result = render(values, overrides)
        self.assertEqual(result.returncode, 0, "Helm rendering failed (output suppressed)")
        return result.stdout

    def test_managed_environments_use_durable_web_only_cookie(self):
        for environment in ("canary", "production", "staging"):
            with self.subTest(environment=environment):
                output = self.rendered(
                    ["values-managed-common.yaml", f"values-managed-{environment}.yaml"],
                    ["server.cluster.enabled=true"],
                )
                external = document(output, "server-cluster-external-secret.yaml")
                for expected in (
                    "kind: ExternalSecret\n",
                    "name: tuist-server-cluster-cookie\n",
                    'refreshInterval: "1h"',
                    "name: onepassword\n",
                    "kind: ClusterSecretStore\n",
                    "creationPolicy: Owner\n",
                    "deletionPolicy: Retain\n",
                    '"release-cookie":',
                    'key: "SERVER_CLUSTER_COOKIE/password"',
                    '{{ fail "The server cluster cookie must not be empty" }}',
                ):
                    self.assertTrue(expected in external, f"Missing managed wiring: {expected}")
                self.assertFalse(document(output, "server-cluster-secret.yaml"), "Competing Helm Secret owner")
                deployment = document(output, "server-deployment.yaml")
                self.assertTrue(re.search(
                    r"- name: RELEASE_COOKIE\s+valueFrom:\s+secretKeyRef:\s+"
                    r'name: tuist-server-cluster-cookie\s+key: "release-cookie"', deployment
                ) is not None, "Missing nonoptional cookie secretKeyRef")
                for doc in output.split("---\n"):
                    if doc != deployment:
                        self.assertFalse("name: tuist-server-cluster-cookie" in doc and "kind: ExternalSecret\n" not in doc,
                                         "Cookie exposed outside web container")
                self.assertEqual(output.count("name: tuist-server-cluster-cookie"), 3, "Unexpected cookie Secret consumer")

    def test_disabled_cluster_does_not_sync_or_inject_cookie(self):
        output = self.rendered(["values-managed-common.yaml", "values-managed-staging.yaml"])
        self.assertFalse(document(output, "server-cluster-external-secret.yaml"))
        self.assertFalse("- name: RELEASE_COOKIE" in document(output, "server-deployment.yaml"))

    def test_self_hosted_still_generates_cookie_without_eso(self):
        output = self.rendered(["values-self-hosted-ci.yaml", "values-cluster-ci.yaml"])
        self.assertTrue(bool(document(output, "server-cluster-secret.yaml")))
        self.assertFalse(document(output, "server-cluster-external-secret.yaml"))

    def test_preowned_secret_is_not_managed_by_either_template(self):
        output = self.rendered(
            ["values-self-hosted-ci.yaml", "values-cluster-ci.yaml"],
            ["server.cluster.cookieExistingSecret=preowned"],
        )
        self.assertFalse(document(output, "server-cluster-secret.yaml"))
        self.assertFalse(document(output, "server-cluster-external-secret.yaml"))

    def test_custom_source_and_target(self):
        output = self.rendered(
            ["values-managed-common.yaml", "values-managed-canary.yaml"],
            ["server.cluster.cookieExistingSecret=custom-cookie", "server.cluster.cookieExistingSecretKey=custom-key",
             "server.cluster.externalSecret.item=CUSTOM_ITEM", "server.cluster.externalSecret.field=custom-field"],
        )
        external = document(output, "server-cluster-external-secret.yaml")
        self.assertTrue('"custom-key":' in external)
        self.assertTrue('key: "CUSTOM_ITEM/custom-field"' in external)
        self.assertTrue("name: custom-cookie\n" in external)
        self.assertFalse(document(output, "server-cluster-secret.yaml"))

    def test_cookie_value_template_rejects_empty_and_preserves_bytes(self):
        output = self.rendered(["values-managed-common.yaml", "values-managed-canary.yaml"])
        external = document(output, "server-cluster-external-secret.yaml")
        match = re.search(r'"release-cookie": \'(.*)\'', external)
        self.assertTrue(match is not None, "Missing ESO value template")
        # Exercise the emitted Go template with Helm's shared trim/fail functions.
        # This is not an ESO reconciliation or Kubernetes integration test.
        with tempfile.TemporaryDirectory(prefix="cookie-template-") as directory:
            chart = Path(directory)
            (chart / "templates").mkdir()
            (chart / "Chart.yaml").write_text("apiVersion: v2\nname: cookie-value-test\nversion: 0.1.0\n")
            (chart / "templates" / "cookie.yaml").write_text(
                '{{- define "cookie-value" -}}' + match.group(1) + '{{- end -}}\n'
                'apiVersion: v1\nkind: Secret\nmetadata:\n  name: fixture\nstringData:\n'
                '  cookie: {{ include "cookie-value" .Values | quote }}\n'
            )
            for value in ("", "   ", "private-cookie-fixture", " private-cookie-fixture "):
                with self.subTest(empty=not value.strip()):
                    result = subprocess.run(
                        ["helm", "template", "fixture", str(chart), "--set-string", f"cookie={value}"],
                        capture_output=True, text=True,
                    )
                    if value.strip():
                        self.assertEqual(result.returncode, 0)
                        self.assertTrue(f'cookie: "{value}"' in result.stdout, "Cookie bytes were altered")
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertTrue("The server cluster cookie must not be empty" in result.stderr)

    def test_invalid_ownership_or_empty_source_fails_closed(self):
        for setting, error in (
            ("cookieExistingSecret", "requires cookieExistingSecret"),
            ("cookieExistingSecretKey", "cookieExistingSecretKey must not be empty"),
            ("externalSecret.item", "externalSecret.item must not be empty"),
            ("externalSecret.field", "externalSecret.field must not be empty"),
        ):
            with self.subTest(setting=setting):
                result = render(
                    ["values-managed-common.yaml", "values-managed-canary.yaml"],
                    [f"server.cluster.{setting}="],
                )
                self.assertNotEqual(result.returncode, 0, "Invalid cookie configuration rendered successfully")
                self.assertTrue(error in result.stderr, "Expected fail-closed error missing")


if __name__ == "__main__":
    unittest.main()
