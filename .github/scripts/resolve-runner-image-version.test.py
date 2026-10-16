#!/usr/bin/env python3
"""Exercise runner release selection against isolated, real Git histories."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("resolve-runner-image-version.sh").resolve()


class ResolveRunnerImageVersionTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.environment = {
            **os.environ,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
        }
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        self.profiles = self.root / "infra/runner-image/profiles.json"
        self.profiles.parent.mkdir(parents=True)

    def git(self, *arguments):
        return subprocess.check_output(
            ["git", *arguments], cwd=self.root, env=self.environment, text=True
        ).strip()

    def commit(self, profiles, tag=None):
        self.profiles.write_text(json.dumps(profiles))
        self.git("add", ".")
        branch = self.git("branch", "--show-current")
        self.git("commit", "-qm", f"profiles on {branch}", "--allow-empty")
        if tag:
            self.git("tag", tag)
        return self.git("rev-parse", "HEAD")

    def resolve(self, sha="HEAD"):
        return subprocess.run(
            ["bash", str(SCRIPT), sha],
            cwd=self.root,
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_new_profile_waits_for_a_release_that_contains_it(self):
        self.commit(["27.1-rc", "26.6"], "runner-image@0.34.1")
        self.commit(["27.1", "26.6"])
        result = self.resolve()
        self.assertEqual(result.returncode, 1)
        self.assertIn("No reachable runner-image release", result.stderr)
        self.git("tag", "runner-image@0.35.0")
        result = self.resolve()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "0.35.0")

    def test_newest_compatible_semver_is_selected_numerically(self):
        self.commit(["27.1", "26.6"], "runner-image@0.9.0")
        self.commit(["27.1", "26.6"], "runner-image@0.10.0")
        self.assertEqual(self.resolve().stdout.strip(), "0.10.0")

    def test_retired_profiles_do_not_prevent_reusing_a_release(self):
        self.commit(["27.1", "27.1-rc", "26.6"], "runner-image@0.35.0")
        self.commit(["27.1", "26.6"])
        self.assertEqual(self.resolve().stdout.strip(), "0.35.0")

    def test_unreachable_release_is_not_selected(self):
        original = self.commit(["27.1-rc", "26.6"], "runner-image@0.34.1")
        self.git("checkout", "-qb", "other")
        self.commit(["27.1", "26.6"], "runner-image@0.35.0")
        self.git("checkout", "-q", "main")
        self.commit(["27.1", "26.6"])
        self.assertEqual(self.resolve().returncode, 1)
        self.assertEqual(self.resolve(original).returncode, 1)

    def test_rollback_uses_the_profile_list_in_the_checked_out_commit(self):
        original = self.commit(["27.1-rc", "26.6"], "runner-image@0.34.1")
        self.commit(["27.1", "26.6"], "runner-image@0.35.0")
        self.git("checkout", "-q", original)
        self.assertEqual(self.resolve(original).stdout.strip(), "0.34.1")

    def test_newest_incompatible_release_is_skipped(self):
        self.commit(["27.1", "26.6"], "runner-image@0.35.0")
        self.commit(["27.1-rc", "26.6"], "runner-image@0.36.0")
        self.commit(["27.1", "26.6"])
        self.assertEqual(self.resolve().stdout.strip(), "0.35.0")

    def test_missing_profile_file_in_old_release_is_skipped(self):
        self.git("commit", "-qm", "before profiles", "--allow-empty")
        self.git("tag", "runner-image@0.1.0")
        self.commit(["27.1"])
        self.assertEqual(self.resolve().returncode, 1)

    def test_prerelease_and_other_component_tags_are_ignored(self):
        self.commit(["27.1"], "runner-image@0.35.0-rc.1")
        self.git("tag", "linux-runner-image@9.0.0")
        self.assertEqual(self.resolve().returncode, 1)

    def test_invalid_active_profile_file_fails_closed(self):
        self.commit(["27.1"], "runner-image@0.35.0")
        for invalid in [[], {}, [42]]:
            with self.subTest(invalid=invalid):
                self.profiles.write_text(json.dumps(invalid))
                self.assertNotEqual(self.resolve().returncode, 0)


if __name__ == "__main__":
    unittest.main()
