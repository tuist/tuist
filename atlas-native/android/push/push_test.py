import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

import configure
import dependencies
import manifest
import resources


class PushPackagingTest(unittest.TestCase):
    def test_accepts_only_fixed_versions(self):
        self.assertEqual(dependencies.fixed_version("[1.2.3]"), "1.2.3")
        for version in ["[1,2)", "latest.release", "${version}", "../escape"]:
            with self.assertRaises(ValueError):
                dependencies.fixed_version(version)

    def test_materialization_verifies_hashes_and_removes_old_resources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            vendor = root / "vendor"
            target = vendor / "library"
            target.mkdir(parents=True)
            (target / "stale.txt").write_text("old release")
            data = io.BytesIO()
            jar = io.BytesIO()
            with zipfile.ZipFile(jar, "w") as archive:
                archive.writestr("example.class", "test")
            with zipfile.ZipFile(data, "w") as archive:
                archive.writestr("AndroidManifest.xml", '<manifest package="example"/>')
                archive.writestr("classes.jar", jar.getvalue())
            artifact = {"coordinate": "example:library", "version": "1.0", "packaging": "aar",
                        "sha256": hashlib.sha256(data.getvalue()).hexdigest(), "url": "https://invalid.example"}
            lock = root / "lock.json"
            lock.write_text(json.dumps({"schema_version": 1, "artifacts": [artifact]}))
            with patch.object(dependencies, "LOCK", lock), patch.object(dependencies, "VENDOR", vendor), \
                    patch.object(dependencies, "fetch", return_value=data.getvalue()):
                dependencies.prepare()
                self.assertFalse((target / "stale.txt").exists())
                self.assertTrue((target / "classes.jar").exists())
                (vendor / "downloads/library-1.0.aar").write_bytes(b"tampered")
                with self.assertRaisesRegex(ValueError, "Integrity"):
                    dependencies.prepare()

    def test_manifest_audit_rejects_new_permissions_and_component_attributes(self):
        android = manifest.ANDROID
        required = ET.Element("service", {android + "name": "service", android + "exported": "false"})
        actual = ET.Element("service", {android + "name": "service", android + "exported": "true"})
        with self.assertRaises(ValueError):
            manifest.require_subset(required, actual)
        actual.set(android + "exported", "false")
        manifest.require_subset(required, actual)
        ET.SubElement(required, "meta-data", {android + "name": "new-required-registrar"})
        with self.assertRaises(ValueError):
            manifest.require_subset(required, actual)

    def test_resource_gate_checks_final_apk_ids_not_just_generated_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            symbols = Path(temporary) / "R.txt"
            symbols.write_text("int drawable ic_notification 0x7f020001\n")
            with patch.object(resources.subprocess, "check_output", return_value="resource 0x7f020001 drawable/ic_notification"):
                resources.verify(["aapt2", str(symbols), "app.apk"])
            with patch.object(resources.subprocess, "check_output", return_value="resource 0x7f020002 drawable/ic_notification"):
                with self.assertRaises(ValueError):
                    resources.verify(["aapt2", str(symbols), "app.apk"])

    def test_configuration_never_accepts_server_credentials(self):
        with self.assertRaises(ValueError):
            configure.public_identifiers({"type": "service_account", "private_key": "secret"})
        document = {
            "project_info": {"project_id": "atlas-example", "project_number": "123456"},
            "client": [{"client_info": {"android_client_info": {"package_name": "dev.tuist.atlas"},
                                        "mobilesdk_app_id": "1:123456:android:example"},
                        "api_key": [{"current_key": "public-api-key"}]}],
        }
        values = configure.public_identifiers(document)
        self.assertEqual(len(values), 4)
        self.assertNotIn("private_key", configure.render(values))
        document["client"][0]["client_info"]["android_client_info"]["package_name"] = "another.app"
        with self.assertRaises(ValueError):
            configure.public_identifiers(document)


if __name__ == "__main__":
    unittest.main()
