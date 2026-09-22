import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from publish import git

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("git-cliff") and shutil.which("jq"), "git-cliff and jq required")
class ReleaseCheckTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        git(self.repo, "init", "--initial-branch=main")
        git(self.repo, "config", "user.name", "test")
        git(self.repo, "config", "user.email", "test@example.com")
        for path in ("mise/tasks/release/check.sh", "mise/tasks/release/components.json", "ci/cache-volume/cliff.toml"):
            target = self.repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, target)
        self.commit("feat(server): add cache volumes", "ci/cache-volume/gitlab/cache-volume.yml")
        self.output = self.repo / ".git/outputs"

    def commit(self, message, path):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(message)
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-m", message)

    def check(self):
        self.output.write_text("")
        subprocess.run(["bash", "mise/tasks/release/check.sh", "cache-volume"], cwd=self.repo,
                       env=dict(os.environ, GITHUB_OUTPUT=str(self.output)), check=True, capture_output=True)
        return dict(line.split("=", 1) for line in self.output.read_text().splitlines())

    def test_initial_release_is_v1_and_no_changes_do_not_release(self):
        self.assertEqual(self.check()["cache-volume-next-version"], "cache-volume@1.0.0")
        git(self.repo, "tag", "cache-volume@1.0.0")
        self.assertEqual(self.check()["cache-volume-should-release"], "false")

    def test_unrelated_changes_do_not_release(self):
        git(self.repo, "tag", "cache-volume@1.0.0")
        self.commit("feat(cli): unrelated change", "cli/unrelated.swift")
        self.assertEqual(self.check()["cache-volume-should-release"], "false")

    def test_each_provider_triggers_patch_release(self):
        git(self.repo, "tag", "cache-volume@1.0.0")
        for index, path in enumerate((".github/actions/cache-volume/action.yml", "ci/cache-volume/buildkite/plugin.yml", "ci/cache-volume/gitlab/cache-volume.yml"), start=1):
            self.commit("fix(server): update integration", path)
            self.assertEqual(self.check()["cache-volume-next-version"], f"cache-volume@1.0.{index}")
            git(self.repo, "tag", f"cache-volume@1.0.{index}")

    def test_features_and_breaking_changes_bump_minor_and_major(self):
        git(self.repo, "tag", "cache-volume@1.0.0")
        self.commit("feat(server): new integration capability", "ci/cache-volume/gitlab/cache-volume.yml")
        self.assertEqual(self.check()["cache-volume-next-version"], "cache-volume@1.1.0")
        git(self.repo, "tag", "cache-volume@1.1.0")
        self.commit("feat(server)!: change integration contract", "ci/cache-volume/gitlab/cache-volume.yml")
        self.assertEqual(self.check()["cache-volume-next-version"], "cache-volume@2.0.0")

    def test_release_workflow_changes_trigger_release(self):
        git(self.repo, "tag", "cache-volume@1.0.0")
        self.commit("ci(server): fix publishing", ".github/workflows/cache-volume-action.yml")
        self.assertEqual(self.check()["cache-volume-next-version"], "cache-volume@1.0.1")
