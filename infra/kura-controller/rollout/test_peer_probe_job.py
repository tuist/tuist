import json
import unittest
from unittest.mock import patch

import gate
import peer_probe_job


class PeerProbeJobTest(unittest.TestCase):
    def test_only_leaf_credentials_are_sent_over_stdin(self):
        job = peer_probe_job.PeerProbeJob("kura")
        job.pod = "probe-pod"
        secret = {"metadata": {"name": "unused"}, "data": {
            "ca.pem": "account-ca", "tls.crt": "leaf-cert", "tls.key": "private-leaf-key",
            "ca.key": "never-forward-ca-private-key"}}
        with patch.object(peer_probe_job, "command") as command:
            job.probe(gate.peer_probe, "acme.peer.example", {"203.0.113.1"}, secret)
        args, payload = command.call_args.args
        self.assertNotIn("private-leaf-key", " ".join(args))
        self.assertNotIn("never-forward-ca-private-key", payload)
        self.assertEqual(json.loads(payload)["secret"]["data"], {
            key: secret["data"][key] for key in ("ca.pem", "tls.crt", "tls.key")})
        self.assertNotIn("private-leaf-key", json.dumps(job.manifest()))

    def test_job_is_deleted_when_readiness_times_out(self):
        job = peer_probe_job.PeerProbeJob("kura")
        with patch.object(peer_probe_job, "command") as command, \
                patch.object(peer_probe_job.time, "monotonic", side_effect=[0, 121]):
            with self.assertRaisesRegex(RuntimeError, "did not become Ready"):
                job.__enter__()
        self.assertEqual(command.call_args.args[0], [
            "-n", "kura", "delete", "job", job.name, "--ignore-not-found", "--wait=false"])

class IPv6ProbeJobsTest(unittest.TestCase):
    def test_ipv6_uses_owner_node_network_and_cleans_up(self):
        nodes = {"items": [{"metadata": {"name": "ipv6-ingress"}, "status": {"addresses": [
            {"type": "ExternalIP", "address": "2001:db8:0:0::1"}]}}]}
        jobs = peer_probe_job.IPv6ProbeJobs("kura", lambda ns, kind: nodes, 2580)
        with patch.object(peer_probe_job.PeerProbeJob, "__enter__", return_value=None), \
                patch.object(peer_probe_job.PeerProbeJob, "__exit__") as cleanup, \
                patch.object(peer_probe_job.PeerProbeJob, "public_probe") as public, \
                patch.object(peer_probe_job.PeerProbeJob, "probe") as peer:
            with jobs:
                jobs.probe(gate.https_probe, "acme.example", "2001:db8::1")
                jobs.peer_probe(gate.peer_probe, "acme.peer.example", "2001:db8::1", {"data": {}})
                manifest = jobs.jobs["2001:db8::1"].manifest()
                spec = manifest["spec"]["template"]["spec"]
                self.assertTrue(spec["hostNetwork"])
                self.assertEqual(spec["nodeName"], "ipv6-ingress")
                self.assertFalse(spec["automountServiceAccountToken"])
                self.assertTrue(spec["securityContext"]["runAsNonRoot"])
                self.assertEqual(manifest["spec"]["activeDeadlineSeconds"], 2580)
            public.assert_called_once()
            peer.assert_called_once()
            cleanup.assert_called_once()

    def test_unknown_ipv6_owner_fails_without_starting_job(self):
        with patch.object(peer_probe_job.PeerProbeJob, "__enter__") as create:
            with peer_probe_job.IPv6ProbeJobs("kura", lambda ns, kind: {"items": []}, 2580) as jobs:
                with self.assertRaisesRegex(RuntimeError, "no ingress node owns"):
                    jobs.probe(gate.https_probe, "acme.example", "2001:db8::1")
            create.assert_not_called()


if __name__ == "__main__":
    unittest.main()
