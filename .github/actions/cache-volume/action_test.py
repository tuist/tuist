import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ACTION = Path(__file__).resolve().parent


class CacheVolumeActionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / "standalone action"
        subprocess.run(
            ["/bin/bash", str(ACTION / "scripts/package.sh"), str(self.package)],
            check=True,
        )
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.output = self.root / "github-output"
        self.args = self.root / "client-args"
        self.env = {
            **os.environ,
            "PATH": str(self.bin),
            "GITHUB_OUTPUT": str(self.output),
            "TUIST_VOLUME_KEY": "gradle-caches",
            "TUIST_VOLUME_PATH": "~/.gradle/caches",
            "CAPTURE_ARGS": str(self.args),
        }

    def client(self, hit="true", exit_code=0):
        binary = self.bin / "tuist-cache-volume"
        binary.write_text(
            '#!/bin/bash\n'
            'printf "%s\\n" "$@" > "$CAPTURE_ARGS"\n'
            f'printf "cache-hit={hit}\\n" >> "$GITHUB_OUTPUT"\n'
            f'exit {exit_code}\n'
        )
        binary.chmod(0o755)

    def attach(self):
        return subprocess.run(
            ["/bin/bash", str(self.package / "attach.sh")],
            env=self.env,
            cwd=self.root,
            text=True,
            capture_output=True,
        )

    def test_package_is_self_contained(self):
        self.assertEqual(
            {p.name for p in self.package.iterdir()},
            {"action.yml", "attach.sh", "README.md", "LICENSE.md", "SOURCE_COMMIT"},
        )
        self.assertRegex((self.package / "SOURCE_COMMIT").read_text().strip(), r"^[a-f0-9]{40}$")
        self.client()
        result = self.attach()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(), "cache-hit=true\n")

    def test_miss_is_forwarded(self):
        self.client(hit="false")
        self.assertEqual(self.attach().returncode, 0)
        self.assertEqual(self.output.read_text(), "cache-hit=false\n")

    def test_inputs_are_literal_arguments(self):
        self.client()
        path = "cache directory/$(touch injected);*"
        self.env["TUIST_VOLUME_PATH"] = path
        self.assertEqual(self.attach().returncode, 0)
        self.assertEqual(self.args.read_text().splitlines(), ["--key", "gradle-caches", "--path", path])
        self.assertFalse((self.root / "injected").exists())

    def test_client_errors_fail_the_step(self):
        self.client(exit_code=42)
        self.assertEqual(self.attach().returncode, 42)

    @unittest.skipIf(Path("/__e/tuist-cache-volume").exists(), "container client is installed")
    def test_missing_client_explains_supported_runner(self):
        result = self.attach()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires a Tuist Linux runner", result.stdout)

    def test_package_does_not_overwrite_existing_directory(self):
        marker = self.package / "keep"
        marker.write_text("existing files")
        result = subprocess.run(
            ["/bin/bash", str(ACTION / "scripts/package.sh"), str(self.package)],
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), "existing files")


if __name__ == "__main__":
    unittest.main()
