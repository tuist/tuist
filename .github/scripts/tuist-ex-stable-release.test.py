#!/usr/bin/env python3
"""Exercise the stable release guard against real, disposable Git histories."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("tuist-ex-stable-release.py")


class StableReleaseTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.repo = Path(self.scratch.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Release test")
        self.git("config", "user.email", "release@example.invalid")
        self.base = self.commit("tuist_ex/lib/client.ex", "stable")
        self.git("tag", "tuist-ex@0.10.9")
        self.source = self.commit("tuist_ex/lib/client.ex", "TLS patch")
        self.branch = "refs/remotes/origin/releases/tuist-ex-0.10.x"
        self.git("update-ref", self.branch, self.source)
        self.output = self.repo / "output"
        self.env = {
            **os.environ,
            "GITHUB_REPOSITORY": "tuist/tuist",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_OUTPUT": str(self.output),
        }

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True).strip()

    def commit(self, path, contents):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents)
        self.git("add", path)
        self.git("commit", "-qm", "fix(tuist-ex): test patch")
        return self.git("rev-parse", "HEAD")

    def run_guard(self, source=None, base="tuist-ex@0.10.9", version="0.10.10", env=None):
        self.output.write_text("")
        return subprocess.run(
            [sys.executable, str(SCRIPT), self.source if source is None else source, base, version],
            cwd=self.repo, env={**self.env, **(env or {})}, capture_output=True, text=True,
        )

    def reject(self, **kwargs):
        result = self.run_guard(**kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.output.read_text(), "")

    def test_accepts_only_next_patch_and_emits_pinned_source(self):
        self.git("tag", "tuist-ex@0.99.0-canary.1")
        self.git("tag", "tuist-ex@0.9.99")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text().splitlines(), [
            "tuist-ex-should-release=true",
            "tuist-ex-next-version=tuist-ex@0.10.10",
            "tuist-ex-next-version-number=0.10.10",
            f"source-sha={self.source}",
            "base-tag=tuist-ex@0.10.9",
            f"base-sha={self.base}",
        ])

    def test_rejects_missing_mutable_and_injected_inputs(self):
        for source in ["", "main", self.source[:12], "a" * 39, "a" * 40 + "\noutput=bad", "--help"]:
            with self.subTest(source=source):
                self.reject(source=source)
        for base in ["", "0.10.9", "tuist-ex@0.10.09", "tuist-ex@0.10.9-rc.1", "tuist-ex@0.10.9\n"]:
            with self.subTest(base=base):
                self.reject(base=base)
        for version in ["", "0.10.9", "0.10.11", "0.11.0", "1.0.0", "0.10.10-rc.1", "0.10.10\n"]:
            with self.subTest(version=version):
                self.reject(version=version)

    def test_requires_main_dispatch_in_upstream_repository(self):
        for key, value in [("GITHUB_EVENT_NAME", "push"), ("GITHUB_EVENT_NAME", "pull_request"),
                           ("GITHUB_REF", "refs/heads/releases/tuist-ex-0.10.x"),
                           ("GITHUB_REPOSITORY", "fork/tuist")]:
            with self.subTest(key=key, value=value):
                self.reject(env={key: value})

    def test_rejects_unmerged_pr_and_stale_release_tip(self):
        newer = self.commit("tuist_ex/lib/client.ex", "another patch")
        self.reject(source=newer)
        self.git("update-ref", self.branch, newer)
        self.reject()

    def test_rejects_missing_branch_and_wrong_line(self):
        self.git("update-ref", "-d", self.branch)
        self.git("update-ref", "refs/remotes/origin/releases/tuist-ex-0.11.x", self.source)
        self.reject()

    def test_rejects_unchanged_or_non_descendant_source(self):
        self.git("update-ref", self.branch, self.base)
        self.reject(source=self.base)
        self.git("checkout", "--orphan", "unrelated")
        unrelated = self.commit("tuist_ex/lib/client.ex", "unrelated tree")
        self.git("update-ref", self.branch, unrelated)
        self.reject(source=unrelated)

    def test_rejects_stale_base_and_existing_target_tag(self):
        self.git("tag", "tuist-ex@0.11.0")
        self.reject()
        self.git("tag", "-d", "tuist-ex@0.11.0")
        self.git("tag", "tuist-ex@0.10.10", self.base)
        self.reject()

    def test_recheck_rejects_replaced_base_even_when_new_base_is_a_source_ancestor(self):
        source = self.commit("tuist_ex/lib/client.ex", "second patch")
        self.git("update-ref", self.branch, source)
        self.assertEqual(self.run_guard(source=source).returncode, 0)
        approved = {"APPROVED_BASE_SHA": self.base}
        self.assertEqual(self.run_guard(source=source, env=approved).returncode, 0)
        self.reject(source=source, env={"APPROVED_BASE_SHA": ""})
        self.git("tag", "--force", "tuist-ex@0.10.9", self.source)
        # The name, latest-version, ancestry and SDK-only checks still pass.
        self.assertEqual(self.run_guard(source=source).returncode, 0)
        self.reject(source=source, env=approved)

    def test_rejects_other_product_or_automation_changes(self):
        for path in ["server/lib/app.ex", "mise/tasks/release/components.json",
                     ".github/workflows/tuist-ex-release.yml"]:
            with self.subTest(path=path):
                source = self.commit(path, "unrelated change")
                self.git("update-ref", self.branch, source)
                self.reject(source=source)
                self.git("reset", "--hard", self.source)

    def test_allows_sdk_validation_backport_but_not_validation_only_release(self):
        source = self.commit(".github/workflows/tuist-ex.yml", "minimum OTP TLS coverage")
        self.git("update-ref", self.branch, source)
        self.assertEqual(self.run_guard(source=source).returncode, 0)
        self.git("reset", "--hard", self.base)
        source = self.commit(".github/workflows/tuist-ex.yml", "validation only")
        self.git("update-ref", self.branch, source)
        self.reject(source=source)


if __name__ == "__main__":
    unittest.main()
