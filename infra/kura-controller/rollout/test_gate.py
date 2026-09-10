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
        with patch.object(gate, "kube", return_value=None):
            self.assertTrue(gate.needs_preparation(config))
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

    def test_serving_gate_waits_for_rollout_and_probes_all_addresses(self):
        self.regions[0]["ingressClass"] = "kura-eu-west"
        config = gate.plan([self.server, self.controller])
        config["regions"] = self.regions
        domain = self.regions[0]["domain"]
        host = "acme." + domain
        workload = {"metadata": {"name": "kura-acme", "generation": 2}, "spec": {"replicas": 2},
                    "status": {"readyReplicas": 2, "updatedReplicas": 2, "observedGeneration": 2,
                               "currentRevision": "new", "updateRevision": "new"}}
        resources = {
            "certificate": {"metadata": {"generation": 2}, "spec": {"dnsNames": ["*." + domain]},
                            "status": {"conditions": [{"type": "Ready", "status": "True", "observedGeneration": 2}]}},
            "kurainstances": {"items": [{"metadata": {"name": "kura-acme"}, "spec": {
                "accountHandle": "acme", "region": "eu-west", "publicHostNetwork": True,
                "ingressClassName": "kura-eu-west", "meshPublicPeerHost": "old.example"}}]},
            "ingresses": {"items": [{"metadata": {"name": name, "annotations": {
                "external-dns.alpha.kubernetes.io/controller": "kura-controller"}},
                "spec": {"rules": [{"host": host}]}} for name in ("kura-acme", "kura-acme-grpc")]},
            "statefulsets": {"items": [workload]},
            "dnsendpoints": {"items": [{"metadata": {"name": "kura-regional-eu-west-dns"}, "spec": {"endpoints": [{"dnsName": "*." + domain,
                "recordType": "A", "targets": ["203.0.113.1", "203.0.113.2"]}, {
                "dnsName": "*.peer." + domain, "recordType": "A", "targets": ["203.0.113.3"]}]}}]},
            "secret": {},
        }
        with patch.object(gate, "kube", side_effect=lambda ns, kind, name=None: resources[kind]), \
                patch.object(gate, "verify_dns"), patch.object(gate, "https_probe") as public, \
                patch.object(gate, "peer_probe") as peer:
            self.assertEqual(gate.check(config), 3)
            self.assertEqual(public.call_count, 2)
            peer.assert_called_once()
            workload["status"]["currentRevision"] = "old"
            with self.assertRaisesRegex(RuntimeError, "rollout incomplete"):
                gate.check(config)
            workload["status"]["currentRevision"] = "new"
            peer.side_effect = OSError("peer still serves old certificate")
            with self.assertRaisesRegex(OSError, "old certificate"):
                gate.check(config)
            peer.side_effect = None
            resources["dnsendpoints"]["items"].append({"metadata": {"name": "kura-acme-public-dns"},
                "spec": {"endpoints": [{"dnsName": host, "recordType": "A", "targets": ["203.0.113.1"]}]}})
            with self.assertRaisesRegex(RuntimeError, "individual regional DNS"):
                gate.check(config)


if __name__ == "__main__":
    unittest.main()
