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


if __name__ == "__main__":
    unittest.main()
