import copy
import json
import unittest
from unittest.mock import patch

import gate


def deployment(component, namespace, containers):
    return {"kind": "Deployment", "metadata": {"name": component, "namespace": namespace,
            "labels": {"app.kubernetes.io/component": component}},
            "spec": {"template": {"spec": {"containers": containers}}}}


class PublicationGateTest(unittest.TestCase):
    def setUp(self):
        self.regions = [{"region": "eu-west", "domain": "eu-west.staging.kura.tuist.dev"}]
        self.server = deployment("server", "tuist-staging", [{"env": [{
            "name": "TUIST_KURA_REGIONAL_DNS_DOMAINS",
            "value": json.dumps({"eu-west": self.regions[0]["domain"]})}]}])
        self.controller = deployment("kura-controller", "kura", [{"args": [
            "--regional-routing-config=" + json.dumps(self.regions),
            "--public-tls-secret-name=kura-public-wildcard-tls"]}])

    def test_preparation_is_required_only_for_unpublished_domains(self):
        config = gate.plan([self.server, self.controller])
        old_server = copy.deepcopy(self.server)
        old_server["spec"]["template"]["spec"]["containers"][0]["env"] = []
        with patch.object(gate, "kube", return_value=old_server):
            self.assertTrue(gate.needs_preparation(config))
        with patch.object(gate, "kube", return_value=self.server):
            self.assertFalse(gate.needs_preparation(config))
        with patch.object(gate, "kube", side_effect=RuntimeError("unavailable")):
            with self.assertRaises(RuntimeError):
                gate.needs_preparation(config)

    def test_disabled_publication_does_not_touch_cluster(self):
        self.server["spec"]["template"]["spec"]["containers"][0]["env"] = []
        config = gate.plan([self.server, self.controller])
        with patch.object(gate, "kube") as kube:
            self.assertFalse(gate.needs_preparation(config))
            kube.assert_not_called()

    def test_mismatched_configuration_fails_closed(self):
        self.server["spec"]["template"]["spec"]["containers"][0]["env"][0]["value"] = '{"eu-west":"different.example"}'
        with self.assertRaises(ValueError):
            gate.plan([self.server, self.controller])

    def test_release_namespace_overrides_client_dry_run_default(self):
        self.server["metadata"]["namespace"] = "default"
        self.assertEqual(gate.plan([self.server, self.controller], "tuist-staging")["serverNamespace"], "tuist-staging")

    def test_dns_requires_exact_nonempty_address_set(self):
        answer = [(None, None, None, None, ("203.0.113.10", 0))]
        with patch.object(gate.socket, "getaddrinfo", return_value=answer):
            gate.verify_dns("probe.example", {"203.0.113.10"})
            for expected in [set(), {"203.0.113.11"}, {"203.0.113.10", "203.0.113.11"}]:
                with self.assertRaises(RuntimeError):
                    gate.verify_dns("probe.example", expected)

    def test_unready_certificate_blocks_before_serving_path_checks(self):
        config = gate.plan([self.server, self.controller])
        with patch.object(gate, "kube", return_value={"status": {"conditions": [{"type": "Ready", "status": "False"}]}}):
            with self.assertRaisesRegex(RuntimeError, "certificate"):
                gate.check(config)


if __name__ == "__main__":
    unittest.main()
