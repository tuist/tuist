"""Exercise delivery-only version stamping and real ad-hoc signatures on macOS."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import unittest


DISTRIBUTION = Path(__file__).resolve().parent


class PreviewVersionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cached = self.root / "cached" / "Atlas.app"
        self.cached.mkdir(parents=True)
        self.info = {
            "CFBundleIdentifier": "dev.tuist.atlas",
            "CFBundleExecutable": "Atlas",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
        }
        (self.cached / "Info.plist").write_bytes(plistlib.dumps(self.info))
        self.app = self.root / "delivery with spaces" / "Atlas.app"
        shutil.copytree(self.cached, self.app)

    def stamp(self, version=None, script="version.sh"):
        env = {key: value for key, value in os.environ.items()
               if key != "ATLAS_BUILD_VERSION"}
        if version is not None:
            env["ATLAS_BUILD_VERSION"] = version
        return subprocess.run(
            ["bash", str(DISTRIBUTION / script), str(self.app)],
            env=env, capture_output=True, text=True,
        )

    def read_info(self, app):
        return plistlib.loads((app / "Info.plist").read_bytes())

    def test_versions_cached_binary_copies_without_changing_source(self):
        for version in ["1792508540", "1792508541"]:
            with self.subTest(version=version):
                result = self.stamp(version)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.read_info(self.app), {
                    **self.info, "CFBundleVersion": version,
                })
                self.assertEqual(self.read_info(self.cached), self.info)

    def test_local_packaging_defaults_to_current_timestamp(self):
        before = int(time.time())
        result = self.stamp()
        self.assertEqual(result.returncode, 0, result.stderr)
        version = int(self.read_info(self.app)["CFBundleVersion"])
        self.assertGreaterEqual(version, before)
        self.assertLessEqual(version, int(time.time()))

    def test_invalid_versions_fail_without_modifying_bundle(self):
        for version in ["0", "-1", "1; Delete :CFBundleIdentifier", "nightly"]:
            with self.subTest(version=version):
                result = self.stamp(version)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.read_info(self.app), self.info)

    def test_simulator_signature_and_entitlements_survive_version_update(self):
        shutil.copyfile("/bin/echo", self.app / "Atlas")
        (self.app / "Atlas").chmod(0o755)
        entitlements = {"keychain-access-groups": ["dev.tuist.atlas"]}
        entitlements_path = self.root / "entitlements.plist"
        entitlements_path.write_bytes(plistlib.dumps(entitlements))
        subprocess.run([
            "codesign", "--force", "--sign", "-", "--timestamp=none",
            "--entitlements", str(entitlements_path), str(self.app),
        ], check=True, capture_output=True)

        result = self.stamp("1792508541", script="simulator.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_info(self.app)["CFBundleVersion"], "1792508541")
        subprocess.run([
            "codesign", "--verify", "--deep", "--strict", str(self.app),
        ], check=True, capture_output=True)
        signed = subprocess.run([
            "codesign", "--display", "--entitlements", ":-", str(self.app),
        ], check=True, capture_output=True)
        self.assertEqual(plistlib.loads(signed.stdout), entitlements)
        self.assertEqual(self.read_info(self.cached), self.info)


if __name__ == "__main__":
    unittest.main()
