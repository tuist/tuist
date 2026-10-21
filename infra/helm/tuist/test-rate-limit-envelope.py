#!/usr/bin/env python3
"""Offline rollout-envelope checks. Rendered secrets are never printed or saved."""

import re
import runpy
import unittest
from pathlib import Path

HELPERS = runpy.run_path(str(Path(__file__).with_name("test-cluster-cookie.py")))


class RateLimitEnvelopeTests(unittest.TestCase):
    def check_envelope(self, expected, *overrides):
        result = HELPERS["render"](["values-self-hosted-ci.yaml"], ["server.cluster.enabled=true", *overrides])
        self.assertEqual(result.returncode, 0, "Helm rendering failed; output suppressed")
        deployment = HELPERS["document"](result.stdout, "server-deployment.yaml")
        match = re.search(r"name: TUIST_RATE_LIMIT_FALLBACK_REPLICAS\s+value: \"(\d+)\"", deployment)
        self.assertIsNotNone(match)
        self.assertEqual(int(match.group(1)), expected)

    def test_default_floor(self):
        self.check_envelope(5)

    def test_fixed_replicas_include_terminating_generation_and_surge(self):
        self.check_envelope(9, "server.replicaCount=4")

    def test_hpa_maximum_not_current_replicas(self):
        self.check_envelope(11, "server.autoscaling.enabled=true", "server.autoscaling.maxReplicas=5")

    def test_percentage_surge_rounds_up(self):
        self.check_envelope(7, "server.replicaCount=3", "server.strategy.rollingUpdate.maxSurge=33%")

    def test_larger_explicit_allowance(self):
        self.check_envelope(20, "server.rateLimitFallbackReplicas=20")

    def test_invalid_or_insufficient_allowances_are_rejected(self):
        for value in ("-1", "invalid", "4", "5"):
            with self.subTest(value=value):
                result = HELPERS["render"](["values-self-hosted-ci.yaml"], ["server.cluster.enabled=true", "server.replicaCount=4", f"server.rateLimitFallbackReplicas={value}"])
                self.assertNotEqual(result.returncode, 0, "invalid allowance unexpectedly rendered")
                self.assertIn("server.rateLimitFallbackReplicas", result.stderr)


if __name__ == "__main__":
    unittest.main()
