"""Portable regression checks for the lock-only Browser importer and final APK gate."""

import hashlib
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import dependencies


def archive_bytes(entries):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        for name, value in entries.items():
            archive.writestr(name, value)
    return stream.getvalue()


def aar_bytes(extra=None):
    entries = {"AndroidManifest.xml": '<manifest package="example.library"/>',
               "classes.jar": archive_bytes({"example/Library.class": b"class bytes"}),
               "res/values/strings.xml": '<resources><string name="example">Example</string></resources>'}
    entries.update(extra or {})
    return archive_bytes(entries)


class BrowserDependenciesTest(unittest.TestCase):
    def setUp(self):
        dependencies.VENDOR.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix=".test-", dir=dependencies.VENDOR)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def artifact(self, data):
        return {"coordinate": "androidx.browser:browser", "version": "1.9.0", "packaging": "aar",
                "url": "https://dl.google.com/dl/android/maven2/androidx/browser/browser/1.9.0/browser-1.9.0.aar",
                "sha256": hashlib.sha256(data).hexdigest(), "dependencies": []}

    def test_lock_has_complete_closure_without_toolchain_stdlib(self):
        artifacts = dependencies.load_lock()
        self.assertTrue(all(artifact["coordinate"] not in dependencies.EXCLUDED for artifact in artifacts))
        selected = {artifact["coordinate"]: tuple(map(int, artifact["version"].split("."))) for artifact in artifacts}
        requested = {}
        for artifact in artifacts:
            for edge in artifact["dependencies"]:
                version = tuple(map(int, edge["requested_version"].split(".")))
                requested[edge["coordinate"]] = max(requested.get(edge["coordinate"], ()), version)
        for coordinate, version in requested.items():
            self.assertEqual(selected[coordinate], version, f"Not the highest requested fixed version: {coordinate}")

    def test_prepare_is_repeatable_offline_and_rejects_tampering_without_erasing_previous_output(self):
        data = aar_bytes()
        lock = self.root / "lock.json"
        lock.write_text(json.dumps({"schema_version": 1, "root": "androidx.browser:browser:1.9.0",
                                    "excluded_toolchain_artifacts": sorted(dependencies.EXCLUDED),
                                    "artifacts": [self.artifact(data)]}))
        vendor = self.root / "vendor"
        with patch.object(dependencies, "LOCK", lock), patch.object(dependencies, "VENDOR", vendor), \
                patch.object(dependencies, "fetch", return_value=data) as fetch:
            dependencies.prepare()
            target = vendor / "androidx.browser-browser"
            first = (target / "classes.jar").read_bytes()
            (target / "res/stale.xml").write_text("old")
            (vendor / "old-coordinate").mkdir()
            dependencies.prepare()
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(first, (target / "classes.jar").read_bytes())
            self.assertFalse((target / "res/stale.xml").exists())
            self.assertFalse((vendor / "old-coordinate").exists())
            download = vendor / "downloads/androidx.browser-browser-1.9.0.aar"
            download.write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "Integrity check failed"):
                dependencies.prepare()
            self.assertEqual(first, (target / "classes.jar").read_bytes())

    def test_download_digest_is_checked_before_caching(self):
        artifact = self.artifact(aar_bytes())
        vendor = self.root / "vendor"
        with patch.object(dependencies, "VENDOR", vendor), patch.object(dependencies, "fetch", return_value=b"corrupt"):
            with self.assertRaisesRegex(ValueError, "Integrity check failed"):
                dependencies.verified_bytes(artifact)
            self.assertFalse((vendor / "downloads").exists())

    def test_rejects_traversal_symlinks_and_unhandled_native_assets(self):
        for filename in ("../escape", "/escape", "res/../../escape", "res\\escape", "C:/escape"):
            with zipfile.ZipFile(io.BytesIO(archive_bytes({filename: b"payload"}))) as archive:
                with self.assertRaisesRegex(ValueError, "Unsafe"):
                    dependencies.checked_entries(archive)
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            link = zipfile.ZipInfo("res/link")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, "../../escape")
        with zipfile.ZipFile(io.BytesIO(stream.getvalue())) as archive:
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                dependencies.checked_entries(archive)
        for prefix in ("assets", "jni", "prefab"):
            data = aar_bytes({f"{prefix}/unhandled": b"payload"})
            with self.assertRaisesRegex(ValueError, "importer upgrade"):
                dependencies.materialize(self.artifact(data), data, self.root / prefix)

    def test_merges_embedded_jars_preserving_services_and_rejecting_duplicate_classes(self):
        first = archive_bytes({"example/One.class": b"one", "META-INF/services/example.Factory": "example.One\n"})
        second = archive_bytes({"example/Two.class": b"two", "META-INF/services/example.Factory": "example.Two\n"})
        data = aar_bytes({"classes.jar": first, "libs/second.jar": second})
        target = self.root / "merged"
        dependencies.materialize(self.artifact(data), data, target)
        with zipfile.ZipFile(target / "classes.jar") as archive:
            self.assertEqual(archive.read("META-INF/services/example.Factory"), b"example.One\nexample.Two\n")
            self.assertIn("example/Two.class", archive.namelist())
        duplicate = aar_bytes({"libs/duplicate.jar": archive_bytes({"example/Library.class": b"duplicate"})})
        with self.assertRaisesRegex(ValueError, "Duplicate AAR jar entry"):
            dependencies.materialize(self.artifact(duplicate), duplicate, self.root / "duplicate")

    def test_final_apk_gate_rejects_missing_or_changed_ids_and_empty_symbol_tables(self):
        symbols = self.root / "R.txt"
        symbols.write_text("int drawable icon 0x7f020001\nint style Widget_Browser 0x7f030001\n")
        dump = "resource 0x7f020001 dev.tuist.app.preview:drawable/icon\nresource 0x7f030001 style/Widget.Browser"
        with patch.object(dependencies.subprocess, "check_output", return_value=dump):
            dependencies.verify(["aapt2", str(symbols), "app.apk"])
        for invalid in ("", dump.replace("0x7f020001", "0x7f020002")):
            with patch.object(dependencies.subprocess, "check_output", return_value=invalid):
                with self.assertRaisesRegex(ValueError, "resource mismatch"):
                    dependencies.verify(["aapt2", str(symbols), "app.apk"])
        symbols.write_text("int styleable Example_name 0\n")
        with patch.object(dependencies.subprocess, "check_output", return_value=dump):
            with self.assertRaisesRegex(ValueError, "No APK resource IDs"):
                dependencies.verify(["aapt2", str(symbols), "app.apk"])


if __name__ == "__main__":
    unittest.main()
