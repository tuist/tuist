import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent


class IntegrationsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dir = Path(self.temp.name)
        self.log = self.dir / "calls"
        client = self.dir / "tuist-cache-volume"
        client.write_text("#!/usr/bin/env python3\nimport os,sys,json\nwith open(os.environ['CALL_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\nsys.exit(int(os.getenv('CLIENT_EXIT','0')))\n")
        client.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.dir) + os.pathsep + os.environ["PATH"], CALL_LOG=str(self.log))

    def plugin(self, config):
        return subprocess.run(["bash", str(ROOT / "buildkite/hooks/pre-command")],
                              env=dict(self.env, BUILDKITE_PLUGIN_CONFIGURATION=json.dumps(config)),
                              capture_output=True, text=True)

    def test_buildkite_multiple_volumes_preserve_literal_arguments(self):
        key = 'gradle;$(touch should-not-exist)'
        result = self.plugin({"volumes": [{"key": key, "path": "cache directory"}, {"key": "npm", "path": ".npm"}]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([json.loads(line) for line in self.log.read_text().splitlines()],
                         [["--key", key, "--path", "cache directory"], ["--key", "npm", "--path", ".npm"]])

    def test_buildkite_validates_all_entries_before_attachment(self):
        for config in [{}, {"volumes": []}, {"volumes": [{"key": "ok", "path": ".ok"}, {"key": "bad"}]},
                       {"volumes": [{"key": "x", "path": "a\nb"}]}, {"volumes": [{"key": "x", "path": "p"}] * 9}]:
            with self.subTest(config=config):
                self.assertNotEqual(self.plugin(config).returncode, 0)
                self.assertFalse(self.log.exists())

    def test_buildkite_client_failure_stops_later_mounts(self):
        self.env["CLIENT_EXIT"] = "7"
        result = self.plugin({"volumes": [{"key": "one", "path": ".one"}, {"key": "two", "path": ".two"}]})
        self.assertEqual(result.returncode, 7)
        self.assertEqual(len(self.log.read_text().splitlines()), 1)

    def test_buildkite_package_is_standalone_and_preserves_executable_hook(self):
        package = self.dir / "package"
        result = subprocess.run(["bash", str(ROOT / "buildkite/package.sh"), str(package)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.access(package / "hooks/pre-command", os.X_OK))
        self.assertTrue((package / "SOURCE_COMMIT").read_text().strip())
        result = subprocess.run(["bash", str(package / "hooks/pre-command")],
                                env=dict(self.env, BUILDKITE_PLUGIN_CONFIGURATION=json.dumps({"volumes": [{"key": "test", "path": ".test"}]})),
                                cwd=self.dir, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.log.exists())

    def test_gitlab_template_executes_quoted_variables(self):
        # Exercise the literal shell block distributed by the template.
        template = (ROOT / "gitlab/cache-volume.yml").read_text()
        script = "\n".join(line[6:] for line in template.splitlines() if line.startswith("      "))
        result = subprocess.run(["bash", "-ec", script], env=dict(self.env, TUIST_VOLUME_KEY="cache", TUIST_VOLUME_PATH="cache $(literal)"),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.log.read_text()), ["--key", "cache", "--path", "cache $(literal)"])

    def test_gitlab_missing_inputs_fail_before_client(self):
        template = (ROOT / "gitlab/cache-volume.yml").read_text()
        script = "\n".join(line[6:] for line in template.splitlines() if line.startswith("      "))
        result = subprocess.run(["bash", "-ec", script], env=dict(self.env, TUIST_VOLUME_KEY="", TUIST_VOLUME_PATH="cache"),
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
