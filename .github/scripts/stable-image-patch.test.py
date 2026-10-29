#!/usr/bin/env python3
"""Exercise the patch planner/publication gate against disposable Git remotes."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("stable-image-patch.py")


class ServerPatchTests(unittest.TestCase):
    component = "server"
    stable = "1.355.2"
    patch = "1.355.3"

    def git(self, *args, cwd=None):
        return subprocess.check_output(
            ["git", *args], cwd=cwd or self.work, text=True, stderr=subprocess.PIPE
        ).strip()

    def commit(self, path, content):
        target = self.work / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        self.git("add", ".")
        self.git("commit", "-m", "fixture change")
        return self.git("rev-parse", "HEAD")

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.work = self.root / "work"
        self.work.mkdir()
        self.git("init", "--initial-branch=main")
        for key, value in (
            ("user.name", "Fixture"),
            ("user.email", "fixture@example.invalid"),
            ("commit.gpgsign", "false"),
            ("core.hooksPath", "/dev/null"),
        ):
            self.git("config", key, value)
        self.seed = self.commit(f"{self.component}/code", "initial\n")
        self.base = self.commit(f"{self.component}/code", "stable\n")
        self.tag = f"{self.component}@{self.stable}"
        self.git("tag", self.tag)
        major, minor, _ = self.stable.split(".")
        self.branch = f"releases/{self.component}-{major}.{minor}.x"
        self.git("switch", "-c", self.branch)
        self.source = self.commit(f"{self.component}/code", "patched\n")
        self.remote = self.root / "remote.git"
        self.git("init", "--bare", str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "origin", self.branch, "--tags")
        self.controls = self.root / "controls"
        self.git("clone", "--branch", self.branch, str(self.remote), str(self.controls))
        self.output = self.root / "outputs"

    def invoke(self, source=None, env=None, command=None):
        self.output.unlink(missing_ok=True)
        environment = {
            **os.environ,
            "GITHUB_REPOSITORY": "tuist/tuist",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_OUTPUT": str(self.output),
        }
        environment.pop("APPROVED_BASE_SHA", None)
        environment.pop("EXPECTED_VERSION", None)
        environment.update(env or {})
        return subprocess.run(
            command
            or [
                sys.executable,
                str(SCRIPT),
                self.component,
                source or self.source,
                self.tag,
            ],
            cwd=self.controls,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def reject(self, **kwargs):
        result = self.invoke(**kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(
            self.output.exists(), "A rejected release emitted publication outputs"
        )
        return result.stderr

    def test_derives_next_patch_and_pins_exact_source_and_base(self):
        result = self.invoke(
            env={"APPROVED_BASE_SHA": self.base, "EXPECTED_VERSION": self.patch}
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            dict(line.split("=", 1) for line in self.output.read_text().splitlines()),
            {
                "version": self.patch,
                "sha": self.source,
                "base_tag": self.tag,
                "base_sha": self.base,
                "branch": self.branch,
            },
        )

    def test_rejects_other_repository_ref_and_event(self):
        for environment in (
            {"GITHUB_REPOSITORY": "fork/tuist"},
            {"GITHUB_REF": "refs/heads/topic"},
            {"GITHUB_EVENT_NAME": "pull_request"},
        ):
            with self.subTest(environment=environment):
                self.assertIn("dispatched from", self.reject(env=environment))

    def test_rejects_unmerged_source(self):
        source = self.commit(f"{self.component}/code", "unmerged\n")
        self.assertIn("merged stable branch tip", self.reject(source=source))

    def test_refetches_replaced_branch_instead_of_accepting_stale_local_tip(self):
        self.commit(f"{self.component}/code", "replacement\n")
        self.git("push", "origin", self.branch)
        self.assertIn("merged stable branch tip", self.reject())

    def test_rejects_deleted_branch_even_with_stale_local_ref(self):
        self.git("push", "origin", "--delete", self.branch)
        self.reject()

    def test_rejects_replaced_base_even_when_replacement_is_still_an_ancestor(self):
        self.git("tag", "--force", self.tag, self.seed)
        self.git("push", "--force", "origin", f"refs/tags/{self.tag}")
        self.assertIn("base changed", self.reject(env={"APPROVED_BASE_SHA": self.base}))

    def test_rejects_missing_approved_base_and_wrong_planned_version(self):
        for environment in ({"APPROVED_BASE_SHA": ""}, {"EXPECTED_VERSION": "99.1.8"}):
            with self.subTest(environment=environment):
                self.reject(env=environment)

    def test_allows_maintained_line_after_newer_minor_and_major_releases(self):
        major, minor, _ = map(int, self.stable.split("."))
        self.git("switch", "main")
        self.commit(f"{self.component}/code", "newer line\n")
        self.git("tag", f"{self.component}@{major}.{minor + 1}.0")
        self.git("tag", f"{self.component}@{major + 1}.0.0")
        self.git("push", "origin", "--tags")
        for environment in (
            {},
            {"APPROVED_BASE_SHA": self.base, "EXPECTED_VERSION": self.patch},
        ):
            with self.subTest(environment=environment):
                result = self.invoke(env=environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    dict(
                        line.split("=", 1)
                        for line in self.output.read_text().splitlines()
                    ),
                    {
                        "version": self.patch,
                        "sha": self.source,
                        "base_tag": self.tag,
                        "base_sha": self.base,
                        "branch": self.branch,
                    },
                )

    def test_rejects_newly_published_patch_without_relying_on_local_tags(self):
        major, minor, _ = map(int, self.stable.split("."))
        self.git("tag", f"{self.component}@{major}.{minor + 1}.0")
        self.git("tag", f"{self.component}@{self.patch}")
        self.git("push", "origin", "--tags")
        self.assertIn("latest published stable", self.reject())

    def test_rejects_no_change_and_unrelated_component_changes(self):
        self.git("push", "--force", "origin", f"{self.base}:refs/heads/{self.branch}")
        self.assertIn("contain a patch", self.reject(source=self.base))
        source = self.commit("app/unrelated", "not part of this patch\n")
        self.git("push", "--force", "origin", self.branch)
        self.assertIn("outside its component", self.reject(source=source))

    def test_rejects_source_on_a_different_history(self):
        self.git("switch", "--orphan", "unrelated")
        source = self.commit(f"{self.component}/code", "different history\n")
        self.git("push", "--force", "origin", f"HEAD:refs/heads/{self.branch}")
        self.assertIn("must be an ancestor", self.reject(source=source))

    def test_allows_shared_trust_inputs_but_not_the_other_products_dependencies(self):
        source = self.commit("infra/certificate-trust/policy.json", "fixture policy\n")
        source = self.commit("infra/certificate-trust/pem-store.sh", "fixture store\n")
        self.git("push", "origin", self.branch)
        result = self.invoke(source=source)
        self.assertEqual(result.returncode, 0, result.stderr)
        source = self.commit("tuist_common/mix.exs", "shared Elixir dependency\n")
        self.git("push", "origin", self.branch)
        result = self.invoke(source=source)
        self.assertEqual(
            result.returncode == 0, self.component == "server", result.stderr
        )

    def test_allows_component_validation_but_rejects_unrelated_trust_tooling(self):
        source = self.commit(f".github/workflows/{self.component}.yml", "validation\n")
        self.git("push", "origin", self.branch)
        result = self.invoke(source=source)
        self.assertEqual(result.returncode, 0, result.stderr)
        source = self.commit(
            "infra/certificate-trust/deploy.sh", "not a source input\n"
        )
        self.git("push", "origin", self.branch)
        self.assertIn("outside its component", self.reject(source=source))


class KuraPatchTests(ServerPatchTests):
    component = "kura"
    stable = "0.59.4"
    patch = "0.59.5"


if __name__ == "__main__":
    unittest.main()
