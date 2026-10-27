import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("push.sh")


class PushEntitlementsTest(unittest.TestCase):
    def configure(self, environment):
        with tempfile.TemporaryDirectory() as root:
            profile = Path(root) / "profile.plist"
            entitlements = Path(root) / "entitlements.plist"
            values = {} if environment is None else {"aps-environment": environment}
            profile.write_bytes(plistlib.dumps({"Entitlements": values}))
            entitlements.write_bytes(plistlib.dumps(values))
            result = subprocess.run(
                ["bash", "-c", 'source "$1"; configure_push_notifications "$2" "$3"',
                 "bash", str(SCRIPT), str(profile), str(entitlements)], capture_output=True, text=True,
            )
            return result, plistlib.loads(entitlements.read_bytes())

    def test_production_profile_preserves_authorized_environment(self):
        result, entitlements = self.configure("production")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(entitlements["aps-environment"], "production")

    def test_missing_capability_fails_before_reading_private_certificate(self):
        result, _ = self.configure(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("regenerate", result.stderr)

    def test_development_profile_cannot_sign_distribution_app(self):
        result, _ = self.configure("development")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
