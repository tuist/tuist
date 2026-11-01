"""Exercise public companion targets with no host Python, SDK, credentials or service."""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_previews import receiver


class RuntimeTests(unittest.TestCase):
    def test_companion_targets_supply_python_and_do_not_publish_without_consent(self):
        bazel = shutil.which("bazel") or shutil.which("bazelisk")
        self.assertIsNotNone(
            bazel, "Install Bazel/Bazelisk to exercise the public rules"
        )
        with tempfile.TemporaryDirectory() as directory:
            for tool in ("python", "python3", "tuist"):
                path = Path(directory) / tool
                path.write_text("#!/bin/sh\necho UNEXPECTED_HOST_TOOL >&2\nexit 91\n")
                path.chmod(0o755)
            environment = dict(
                os.environ, PATH=directory + os.pathsep + os.environ["PATH"]
            )
            for manifest in (False, True):
                login = subprocess.run(
                    [
                        bazel,
                        "run",
                        "@rules_tuist//:login",
                        "--enable_runfiles=" + ("false" if manifest else "true"),
                        "--",
                        "--help",
                    ],
                    env=environment,
                    cwd=Path(__file__).resolve().parent,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(login.returncode, 0, login.stdout + login.stderr)
                self.assertIn("Sign in to Tuist from Bazel", login.stdout)
                self.assertNotIn("UNEXPECTED_HOST_TOOL", login.stderr)
                for target in (
                    "preview_android",
                    "preview_apple",
                    "preview_executable",
                ):
                    for args in (
                        [],
                        ["--no-publish"],
                        ["--publish", "--no-publish"],
                        ["--help"],
                    ):
                        with self.subTest(manifest=manifest, target=target, args=args):
                            result = subprocess.run(
                                [
                                    bazel,
                                    "run",
                                    "//:" + target,
                                    "--enable_runfiles="
                                    + ("false" if manifest else "true"),
                                    "--",
                                    "--url",
                                    "http://127.0.0.1:1",
                                    *args,
                                ],
                                env=environment,
                                cwd=Path(__file__).resolve().parent,
                                capture_output=True,
                                text=True,
                                check=False,
                            )
                            self.assertEqual(
                                result.returncode, 0, result.stdout + result.stderr
                            )
                            self.assertNotIn("UNEXPECTED_HOST_TOOL", result.stderr)
                            self.assertIn(
                                "--publish"
                                if args == ["--help"]
                                else "Publication disabled",
                                result.stdout,
                            )

    def test_native_executable_publication_is_relocatable_and_reuses_receipts(self):
        bazel = shutil.which("bazel") or shutil.which("bazelisk")
        self.assertIsNotNone(bazel)
        with receiver() as (url, state), tempfile.TemporaryDirectory() as directory:
            environment = dict(os.environ, TUIST_TOKEN="test-token")
            build = subprocess.run(
                [bazel, "build", "//:preview_executable", "--jobs=2"],
                cwd=Path(__file__).resolve().parent,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(state["requests"], [])
            for manifest in (False, True):
                command = [
                    bazel,
                    "run",
                    "//:preview_executable",
                    "--jobs=2",
                    "--enable_runfiles=" + str(not manifest).lower(),
                    "--",
                    "--publish",
                    "--project",
                    "acme/app",
                    "--url",
                    url,
                ]
                result = subprocess.run(
                    command,
                    cwd=Path(__file__).resolve().parent,
                    env=environment,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(
                    "Already published" if manifest else "Published sha256:",
                    result.stdout,
                )
                if manifest:
                    self.assertTrue(
                        all(method == "GET" for method, _ in state["requests"])
                    )
                state["requests"].clear()
            self.assertEqual(len(state["receipts"]), 1)
            metadata = next(
                json.loads(value)
                for value in state["uploads"].values()
                if b'"tuist.executable.v1"' in value
            )
            self.assertEqual(metadata["display_name"], "tool")
            self.assertEqual(
                metadata["platform"], "macos" if sys.platform == "darwin" else "linux"
            )
            with zipfile.ZipFile(
                io.BytesIO(
                    next(
                        value
                        for value in state["uploads"].values()
                        if value.startswith(b"PK")
                    )
                )
            ) as archive:
                manifest = json.loads(archive.read("tuist-preview.json"))
                archive.extractall(directory)
                for entry in archive.infolist():
                    (Path(directory) / entry.filename).chmod(
                        entry.external_attr >> 16 & 0o777
                    )
            executable = Path(directory) / manifest["executable"]
            output = subprocess.check_output([executable], cwd=directory, text=True)
            self.assertEqual(output.strip(), "Hello from a packaged shared library")
            state["fail"] = "upload"
            failure = subprocess.run(
                command + ["--track", "upload-error"],
                cwd=Path(__file__).resolve().parent,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(failure.returncode, 0)
            self.assertEqual(
                sum(method == "POST" for method, _ in state["requests"]), 1
            )


if __name__ == "__main__":
    unittest.main()
