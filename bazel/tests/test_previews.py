"""Protocol/packaging checks, plus optional real Android SDK regressions."""

import hashlib
import json
import os
import plistlib
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
import xml.etree.ElementTree as ET
import zipfile
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

PRIVATE = Path(__file__).resolve().parents[1] / "private"
sys.path.insert(0, str(PRIVATE))
import apple


@contextmanager
def receiver():
    state = {"uploads": {}, "receipts": {}, "fail": None, "requests": []}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def response(self, status, value):
            self.send_response(status)
            self.end_headers()
            self.wfile.write(json.dumps(value).encode())

        def do_GET(self):
            state["requests"].append(("GET", self.path))
            if self.headers.get("Authorization") != "Bearer test-token":
                return self.response(401, {})
            if self.path.endswith("/artifacts/"):
                return self.response(
                    200,
                    {
                        "schema": "once.publication_service.v1",
                        "destination": "project:123",
                    },
                )
            if state["fail"] == "empty-lookup":
                return self.response(200, None)
            receipt = state["receipts"].get(self.path)
            return self.response(200 if receipt else 404, receipt)

        def do_POST(self):
            state["requests"].append(("POST", self.path))
            if state["fail"] == "redirect":
                self.send_response(307)
                self.send_header("Location", "/must-not-follow")
                self.end_headers()
                return
            if state["fail"] == "upload":
                return self.response(503, {})
            body = self.rfile.read(int(self.headers["Content-Length"]))
            if "/content/" in self.path:
                checksum = "sha256:" + hashlib.sha256(body).hexdigest()
                if not self.path.endswith("/" + checksum):
                    return self.response(422, {})
                state["uploads"][checksum] = body
                return self.response(200, {})
            intent = json.loads(body)
            canonical = json.dumps(
                intent, sort_keys=True, separators=(",", ":"), ensure_ascii=False
            ).encode()
            key = "sha256:" + hashlib.sha256(canonical).hexdigest()
            if not self.path.endswith("/" + key):
                return self.response(422, {})
            root = json.loads(state["uploads"][intent["root"]["digest"]])
            for member in root["members"].values():
                artifact = json.loads(state["uploads"][member["artifact"]["digest"]])
                for descriptor in artifact["payloads"].values():
                    if (
                        len(state["uploads"][descriptor["digest"]])
                        != descriptor["size_bytes"]
                    ):
                        return self.response(422, {})
            receipt = {
                "schema": "once.publication_receipt.v1",
                "destination": "project:123",
                "key": key,
                "root": intent["root"],
            }
            state["receipts"][self.path] = receipt
            if state["fail"] == "lost-ack":
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            if state["fail"] == "receipt":
                receipt = dict(receipt, destination="project:999")
            self.response(200, receipt)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}", state
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class PublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, text in {
            "tuist": "echo test-token",
            "apksigner": "echo 'Signer #1 certificate SHA-256 digest: "
            + "ab" * 32
            + "'",
            "apkanalyzer": "cat <<'XML'\n"
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
            'package="dev.example.preview" android:versionCode="27" android:versionName="2.7">'
            "<application/></manifest>\nXML",
        }.items():
            tool = self.bin / name
            tool.write_text("#!/bin/sh\n" + text + "\n")
            tool.chmod(0o755)
        (self.root / "app.apk").write_bytes(b"APK payload -- not a native build")
        self.config = self.root / "config.json"
        self.config.write_text(
            json.dumps({"ecosystem": "android", "target": "//app:app"})
        )

    def run_publisher(self, url, *args):
        return subprocess.run(
            [
                sys.executable,
                str(PRIVATE / "publish.py"),
                "--config",
                str(self.config),
                "--payload",
                str(self.root / "app.apk"),
                "--apkanalyzer",
                str(self.bin / "apkanalyzer"),
                "--apksigner",
                str(self.bin / "apksigner"),
                "--url",
                url,
                *args,
            ],
            check=False,
            env=dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"]),
            capture_output=True,
            text=True,
        )

    def test_publication_and_replay_verify_receipt_without_reuploading(self):
        with receiver() as (url, state):
            first = self.run_publisher(
                url,
                "--publish",
                "--project",
                "acme/app",
                "--track",
                "review",
                "--revision",
                "abcdef",
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertIn("Published sha256:", first.stdout)
            before = len([r for r in state["requests"] if r[0] == "POST"])
            replay = self.run_publisher(
                url,
                "--publish",
                "--project",
                "acme/app",
                "--track",
                "review",
                "--revision",
                "abcdef",
            )
            self.assertEqual(replay.returncode, 0, replay.stderr)
            self.assertIn("Already published", replay.stdout)
            self.assertEqual(len(state["receipts"]), 1)
            self.assertEqual(
                len([r for r in state["requests"] if r[0] == "POST"]), before
            )
            metadata = [
                json.loads(b) for b in state["uploads"].values() if b.startswith(b"{")
            ]
            android = next(
                m for m in metadata if m["schema"] == "once.android_application.v1"
            )
            self.assertEqual(
                (
                    android["application_id"],
                    android["version_code"],
                    android["version_name"],
                ),
                ("dev.example.preview", "27", "2.7"),
            )
            self.assertEqual(len(state["uploads"]), 4)

    def test_disabled_and_missing_consent_never_connect_or_resolve_credentials(self):
        (self.bin / "tuist").unlink()
        self.config.unlink()
        with receiver() as (url, state):
            for args in [(), ("--publish", "--no-publish"), ("--project", "acme/app")]:
                result = self.run_publisher(url, *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Publication disabled", result.stdout)
            self.assertNotEqual(self.run_publisher(url, "--publish").returncode, 0)
            self.assertEqual(state["requests"], [])

    def test_failures_are_not_success_and_retry_recovers_lost_commit_ack(self):
        for failure in ["upload", "receipt", "redirect", "lost-ack", "empty-lookup"]:
            with self.subTest(failure=failure), receiver() as (url, state):
                state["fail"] = failure
                result = self.run_publisher(url, "--publish", "--project", "acme/app")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("Published", result.stdout)
                self.assertNotIn("test-token", result.stdout + result.stderr)
                self.assertFalse(
                    any(path == "/must-not-follow" for _, path in state["requests"])
                )
                if failure == "empty-lookup":
                    self.assertEqual(state["uploads"], {})
                if failure == "lost-ack":
                    before = len([r for r in state["requests"] if r[0] == "POST"])
                    state["fail"] = None
                    retry = self.run_publisher(
                        url, "--publish", "--project", "acme/app"
                    )
                    self.assertEqual(retry.returncode, 0, retry.stderr)
                    self.assertEqual(
                        len([r for r in state["requests"] if r[0] == "POST"]), before
                    )

    def test_unsigned_and_instrumentation_apks_never_reach_service(self):
        with receiver() as (url, state):
            (self.bin / "apksigner").write_text("#!/bin/sh\nexit 1\n")
            unsigned = self.run_publisher(url, "--publish", "--project", "acme/app")
            self.assertNotEqual(unsigned.returncode, 0)
            (self.bin / "apksigner").write_text(
                "#!/bin/sh\necho 'Signer #1 certificate SHA-256 digest: "
                + "ab" * 32
                + "'\n"
            )
            tool = self.bin / "apkanalyzer"
            tool.write_text(
                tool.read_text().replace(
                    "<application/>",
                    '<application/><instrumentation android:name="dev.example.Test"/>',
                )
            )
            instrumentation = self.run_publisher(
                url, "--publish", "--project", "acme/app"
            )
            self.assertNotEqual(instrumentation.returncode, 0)
            self.assertEqual(state["requests"], [])


class NativeAndroidTests(unittest.TestCase):
    """Real SDK manifest/signature checks; only auth and the receiver are doubles."""

    @classmethod
    def setUpClass(cls):
        sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
        if not sdk or not shutil.which("keytool"):
            raise unittest.SkipTest(
                "Native Android checks require ANDROID_HOME and a JDK"
            )
        cls.sdk = Path(sdk)
        cls.tools = cls.sdk / "build-tools/35.0.0"
        cls.platform = cls.sdk / "platforms/android-35/android.jar"
        if not cls.platform.exists() or not (cls.tools / "apksigner").exists():
            raise unittest.SkipTest("Native Android checks require SDK/build-tools 35")

    def test_real_signed_manifests_preserve_versions_and_reject_instrumentation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            key = root / "debug.keystore"
            subprocess.run(
                [
                    "keytool",
                    "-genkeypair",
                    "-keystore",
                    str(key),
                    "-storepass",
                    "android",
                    "-keypass",
                    "android",
                    "-alias",
                    "debug",
                    "-dname",
                    "CN=Test",
                    "-keyalg",
                    "RSA",
                    "-validity",
                    "1",
                ],
                check=True,
                capture_output=True,
            )
            auth = root / "tuist"
            auth.write_text("#!/bin/sh\necho test-token\n")
            auth.chmod(0o755)
            config = root / "config.json"
            config.write_text(
                json.dumps({"ecosystem": "android", "target": "//app:app"})
            )
            for version, instrumentation in [
                ("2.7", False),
                ("1.0' name='dev.example.wrong", False),
                ("2.7", True),
            ]:
                with self.subTest(version=version, instrumentation=instrumentation):
                    manifest = ET.Element(
                        "manifest",
                        {
                            "xmlns:android": "http://schemas.android.com/apk/res/android",
                            "package": "dev.example.real",
                            "android:versionCode": "27",
                            "android:versionName": version,
                        },
                    )
                    ET.SubElement(manifest, "uses-sdk", {"android:minSdkVersion": "23"})
                    ET.SubElement(manifest, "application", {"android:hasCode": "false"})
                    if instrumentation:
                        ET.SubElement(
                            manifest,
                            "instrumentation",
                            {
                                "android:name": "android.test.InstrumentationTestRunner",
                                "android:targetPackage": "dev.example.real",
                            },
                        )
                    ET.ElementTree(manifest).write(
                        root / "AndroidManifest.xml", encoding="utf-8"
                    )
                    apk = root / "app.apk"
                    subprocess.run(
                        [
                            str(self.tools / "aapt2"),
                            "link",
                            "-I",
                            str(self.platform),
                            "--manifest",
                            str(root / "AndroidManifest.xml"),
                            "-o",
                            str(apk),
                        ],
                        check=True,
                        capture_output=True,
                    )
                    subprocess.run(
                        [
                            str(self.tools / "apksigner"),
                            "sign",
                            "--ks",
                            str(key),
                            "--ks-pass",
                            "pass:android",
                            str(apk),
                        ],
                        check=True,
                        capture_output=True,
                    )
                    with receiver() as (url, state):
                        result = subprocess.run(
                            [
                                sys.executable,
                                str(PRIVATE / "publish.py"),
                                "--config",
                                str(config),
                                "--payload",
                                str(apk),
                                "--url",
                                url,
                                "--publish",
                                "--project",
                                "acme/app",
                            ],
                            check=False,
                            env=dict(
                                os.environ,
                                PATH=str(root) + os.pathsep + os.environ["PATH"],
                            ),
                            capture_output=True,
                            text=True,
                        )
                        if instrumentation:
                            self.assertNotEqual(result.returncode, 0, result.stdout)
                            self.assertIn("Instrumentation", result.stderr)
                            self.assertEqual(state["requests"], [])
                        else:
                            self.assertEqual(result.returncode, 0, result.stderr)
                            metadata = next(
                                json.loads(value)
                                for value in state["uploads"].values()
                                if b'"once.android_application.v1"' in value
                            )
                            self.assertEqual(
                                metadata["application_id"], "dev.example.real"
                            )
                            self.assertEqual(metadata["version_name"], version)
                            self.assertEqual(metadata["version_code"], "27")


class ApplePackagingTests(unittest.TestCase):
    def test_simulator_archive_is_normalized_deterministically_preserving_bundle_links_and_modes(
        self,
    ):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            info = plistlib.dumps(
                {
                    "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
                    "CFBundlePackageType": "APPL",
                    "CFBundleIdentifier": "dev.example.apple",
                    "CFBundleName": "Example",
                    "CFBundleShortVersionString": "3.2",
                    "CFBundleVersion": "32",
                }
            )
            source = root / "source.zip"
            with zipfile.ZipFile(source, "w") as archive:
                for name, mode, data in [
                    ("Example", 0o100755, b"mock Mach-O"),
                    ("Info.plist", 0o100644, info),
                    ("Link", 0o120777, b"./Example"),
                    ("Resources/", 0o40550, b""),
                    ("Resources/text", 0o100640, b"resource"),
                ]:
                    entry = zipfile.ZipInfo("Payload/Example.app/" + name)
                    entry.external_attr = mode << 16
                    archive.writestr(entry, data)
            signature = subprocess.CompletedProcess(
                [], 0, stdout="", stderr="Signature=adhoc\n"
            )
            outputs = []
            for name, mask in [("first", 0o022), ("second", 0o077)]:
                out = root / name
                out.mkdir()
                previous = os.umask(mask)
                try:
                    with (
                        patch.object(apple.sys, "platform", "darwin"),
                        patch.object(apple.subprocess, "run", return_value=signature),
                    ):
                        path, media, interface, metadata = apple.prepare(
                            source, out, None
                        )
                finally:
                    os.umask(previous)
                outputs.append(path.read_bytes())
                self.assertEqual(
                    (media, interface, metadata["platform"], metadata["sdk_variant"]),
                    (
                        "application/zip",
                        "dev.once.apple-install.v2",
                        "ios",
                        "simulator",
                    ),
                )
                with zipfile.ZipFile(path) as archive:
                    self.assertIn("Example.app/Info.plist", archive.namelist())
                    self.assertEqual(
                        archive.getinfo("Example.app/Example").external_attr >> 16
                        & 0o777,
                        0o755,
                    )
                    self.assertTrue(
                        stat.S_ISLNK(
                            archive.getinfo("Example.app/Link").external_attr >> 16
                        )
                    )
                    self.assertEqual(archive.read("Example.app/Link"), b"./Example")
                    self.assertEqual(
                        archive.getinfo("Example.app/Resources/").external_attr >> 16
                        & 0o777,
                        0o550,
                    )
            self.assertEqual(*outputs)

    def test_device_and_non_adhoc_archives_are_rejected(self):
        for platform, signature in [
            ("iPhoneOS", "Signature=adhoc"),
            ("iPhoneSimulator", "Authority=Apple Development: Example"),
        ]:
            with (
                self.subTest(platform=platform),
                tempfile.TemporaryDirectory() as temporary,
            ):
                root = Path(temporary)
                source = root / "source.zip"
                with zipfile.ZipFile(source, "w") as archive:
                    archive.writestr(
                        "Payload/Example.app/Info.plist",
                        plistlib.dumps(
                            {
                                "CFBundleSupportedPlatforms": [platform],
                                "CFBundlePackageType": "APPL",
                                "CFBundleIdentifier": "dev.example.apple",
                            }
                        ),
                    )
                command = subprocess.CompletedProcess(
                    [], 0, stdout="", stderr=signature
                )
                with (
                    patch.object(apple.sys, "platform", "darwin"),
                    patch.object(apple.subprocess, "run", return_value=command),
                    self.assertRaises(ValueError),
                ):
                    apple.prepare(source, root, None)

    def test_archive_cannot_escape_via_paths_or_symlinks(self):
        for entries in [
            [("../escape", b"x", 0o100644)],
            [("link", b"../outside", 0o120777)],
            [("link", b"inside", 0o120777), ("link/../../escape", b"x", 0o100644)],
        ]:
            with (
                self.subTest(entries=entries),
                tempfile.TemporaryDirectory() as temporary,
            ):
                root = Path(temporary)
                source = root / "source.zip"
                with zipfile.ZipFile(source, "w") as archive:
                    for name, data, mode in entries:
                        entry = zipfile.ZipInfo(name)
                        entry.external_attr = mode << 16
                        archive.writestr(entry, data)
                with self.assertRaises(ValueError):
                    apple.extract(source, root / "unpacked")


if __name__ == "__main__":
    unittest.main()
