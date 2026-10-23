#!/usr/bin/env python3
"""Credential-free checks of the real profile capability guard."""
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("associated-domains.sh")
KEY = "com.apple.developer.associated-domains"
DOMAIN = "applinks:atlas.tuist.dev"


class AssociatedDomainsTests(unittest.TestCase):
    def configure(self, domains):
        with tempfile.TemporaryDirectory(prefix="atlas profile ") as root:
            profile = Path(root) / "profile.plist"
            entitlements = Path(root) / "entitlements.plist"
            values = {} if domains is None else {KEY: domains}
            profile.write_bytes(plistlib.dumps({"Entitlements": values}))
            entitlements.write_bytes(plistlib.dumps(values))
            result = subprocess.run(
                ["bash", "-c", 'source "$1"; configure_associated_domains "$2" "$3"',
                 "bash", str(SCRIPT), str(profile), str(entitlements)],
                capture_output=True, text=True, check=False,
            )
            return result, plistlib.loads(entitlements.read_bytes())

    def test_scalar_wildcard_profile_requests_only_the_hosted_domain(self):
        result, entitlements = self.configure("*")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(entitlements[KEY], [DOMAIN])

    def test_scalar_exact_profile_requests_only_the_hosted_domain(self):
        result, entitlements = self.configure(DOMAIN)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(entitlements[KEY], [DOMAIN])

    def test_wildcard_profile_requests_only_the_hosted_domain(self):
        result, entitlements = self.configure(["*"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(entitlements[KEY], [DOMAIN])

    def test_exact_profile_requests_only_the_hosted_domain(self):
        result, entitlements = self.configure(["applinks:other.example.org", DOMAIN])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(entitlements[KEY], [DOMAIN])

    def test_missing_or_wrong_capability_fails_closed(self):
        for domains in [
            None, [], "", True, 1, {"0": "*"}, [["*"]],
            "applinks:other.example.org", "webcredentials:atlas.tuist.dev", "**",
            ["applinks:other.example.org"], ["webcredentials:atlas.tuist.dev"],
        ]:
            with self.subTest(domains=domains):
                result, entitlements = self.configure(domains)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(entitlements, {} if domains is None else {KEY: domains})
                self.assertIn("regenerate the Atlas ad-hoc provisioning profile", result.stderr)


if __name__ == "__main__":
    unittest.main()
