#!/usr/bin/env python3
"""Real Git/CLI regressions. All pushes target disposable local repositories."""

import hashlib
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "bazel/release/release.py"
ROOT = SCRIPT.parents[2]
WORKFLOW = ROOT / ".github/workflows/bazel-release.yml"


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", HOME=str(self.root))
        self.git("init", "-b", "main")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Release fixture")
        self.write("LICENSE.md", "fixture license\n")
        self.write(
            "bazel/MODULE.bazel",
            'module(\n    name = "rules_tuist",\n    version = "0.1.0",\n)\nbazel_dep(name = "other", version = "9.0.0")\n',
        )
        self.write("bazel/private/publish.py", 'print("original")\n')
        self.write("bazel/release/control.py", "must not ship\n")
        self.write("unrelated/secret", "must not ship\n")
        self.commit()
        self.initial = self.git("rev-parse", "HEAD").strip()
        self.remote = self.root / "remote.git"
        self.git("init", "--bare", str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-u", "origin", "main")
        self.assets = self.root / "assets"
        self.calls = self.root / "gh-calls.jsonl"
        # Stub only GitHub's HTTP-side CLI, not Git or the release control code.
        binary = self.root / "bin/gh"
        binary.parent.mkdir()
        binary.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            'with open(os.environ["GH_CALLS"], "a") as f:\n'
            '    f.write(json.dumps(sys.argv[1:]) + "\\n")\n'
        )
        binary.chmod(0o755)
        self.env.update(
            PATH=f"{binary.parent}:{self.env['PATH']}", GH_CALLS=str(self.calls)
        )

    def write(self, path, data):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(data)

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args],
            cwd=self.repo,
            env=self.env,
            text=True,
            stderr=subprocess.DEVNULL,
        )

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-m", "fixture")

    def cli(self, *args, success=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=self.repo,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def plan(self, channel, branch=""):
        return json.loads(self.cli("plan", channel, "--branch", branch).stdout)

    def package(self, item):
        self.cli("package", item["sha"], item["version"], str(self.assets))
        return self.assets / f"rules_tuist-{item['version']}.tar.gz"

    def publish(self, plans):
        for item in plans:
            self.package(item)
        self.cli("publish", json.dumps(plans), str(self.assets))

    def cut_rc(self):
        item = self.plan("rc-new")[0]
        self.publish([item])
        return item

    def workflow_plan(
        self,
        event="workflow_dispatch",
        channel="rc-new",
        branch="",
        success=True,
    ):
        # Execute the actual workflow planner shell with real Git and trusted code.
        # No YAML dependency is needed to extract this literal run block.
        self.write("bazel/release/release.py", SCRIPT.read_text())
        block = WORKFLOW.read_text().split("        run: |\n", 1)[1]
        shell = "\n".join(line[10:] for line in block.split("\n\n", 1)[0].splitlines())
        output = self.root / "outputs"
        output.write_text("")
        result = subprocess.run(
            ["bash", "-c", shell],
            cwd=self.repo,
            env=dict(
                self.env,
                EVENT=event,
                CHANNEL=channel,
                BRANCH=branch,
                SOURCE_SHA=self.initial,
                GITHUB_OUTPUT=str(output),
            ),
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return dict(line.split("=", 1) for line in output.read_text().splitlines())

    def test_workflow_plans_source_releases(self):
        for event, channel, expected in [
            ("push", "", "0.1.0-canary.1"),
            ("workflow_dispatch", "rc-new", "0.1.0-rc.1"),
            ("schedule", "", "0.1.0-rc.1"),
        ]:
            outputs = self.workflow_plan(event=event, channel=channel)
            self.assertEqual(json.loads(outputs["plans"])[0]["version"], expected)
            self.assertEqual(outputs["control_sha"], self.initial)
        rc = self.cut_rc()
        outputs = self.workflow_plan(channel="promote", branch=rc["branch"])
        self.assertEqual(json.loads(outputs["plans"])[0]["version"], "0.1.0")
        outputs = self.workflow_plan(event="schedule")
        self.assertEqual(
            [p["version"] for p in json.loads(outputs["plans"])],
            ["0.1.0", "0.2.0-rc.1"],
        )
        self.workflow_plan(channel="unknown", success=False)

    def test_first_release_without_synthetic_tags(self):
        self.assertEqual(self.plan("promote"), [])
        self.assertEqual(self.plan("canary")[0]["version"], "0.1.0-canary.1")
        weekly = self.plan("weekly")
        self.assertEqual([p["version"] for p in weekly], ["0.1.0-rc.1"])
        self.publish(weekly)
        self.assertEqual(
            self.git("ls-remote", "--heads", "origin", weekly[0]["branch"]).split()[0],
            self.initial,
        )

    def test_canary_counter_does_not_advance_minor(self):
        first = self.plan("canary")[0]
        self.publish([first])
        self.assertEqual(self.plan("canary"), [])
        self.write("bazel/new.bzl", "# next commit\n")
        self.commit()
        self.git("push", "origin", "main")
        self.assertEqual(self.plan("canary")[0]["version"], "0.1.0-canary.2")

    def test_rc_advances_canary_and_can_iterate(self):
        rc = self.cut_rc()
        self.assertEqual(self.plan("canary")[0]["version"], "0.2.0-canary.1")
        self.git("checkout", "-b", rc["branch"])
        self.write("bazel/fix.bzl", "# release fix\n")
        self.commit()
        self.git("push", "origin", rc["branch"])
        self.cli("plan", "promote", "--branch", rc["branch"], success=False)
        iteration = self.plan("rc", rc["branch"])[0]
        self.assertEqual(iteration["version"], "0.1.0-rc.2")
        self.assertEqual(iteration["sha"], self.git("rev-parse", "HEAD").strip())
        self.publish([iteration])
        stable = self.plan("promote", rc["branch"])[0]
        self.assertEqual(stable["sha"], iteration["sha"])
        self.publish([stable])
        self.cli("plan", "rc", "--branch", rc["branch"], success=False)

    def test_weekly_promotes_exact_rc_then_cuts_next_minor(self):
        rc = self.cut_rc()
        self.write("bazel/private/publish.py", 'print("main moved")\n')
        self.commit()
        self.git("push", "origin", "main")
        weekly = self.plan("weekly")
        self.assertEqual([p["version"] for p in weekly], ["0.1.0", "0.2.0-rc.1"])
        self.assertEqual(weekly[0]["sha"], rc["sha"])
        self.assertNotEqual(weekly[1]["sha"], rc["sha"])
        self.publish(weekly)
        with tarfile.open(self.assets / "rules_tuist-0.1.0.tar.gz") as archive:
            self.assertIn(
                b'version = "0.1.0"',
                archive.extractfile("rules_tuist-0.1.0/MODULE.bazel").read(),
            )
            self.assertEqual(
                archive.extractfile("rules_tuist-0.1.0/private/publish.py").read(),
                b'print("original")\n',
            )

    def test_promotion_rechecks_branch_after_validation(self):
        rc = self.cut_rc()
        stable = self.plan("promote", rc["branch"])[0]
        self.package(stable)
        self.git("checkout", "-b", rc["branch"])
        self.write("bazel/fix.bzl", "# not soaked\n")
        self.commit()
        self.git("push", "origin", rc["branch"])
        result = self.cli(
            "publish", json.dumps([stable]), str(self.assets), success=False
        )
        self.assertIn("moved beyond latest RC", result.stderr)
        self.assertEqual(
            self.git("ls-remote", "--tags", "origin", "rules_tuist@0.1.0"), ""
        )

    def test_invalid_dispatch_namespace_never_executes_source(self):
        for branch in [
            "main",
            "feature/evil",
            "--help",
            "releases/0.1.x",
            "releases/rules-tuist-0.1.x;echo hacked",
        ]:
            result = self.cli("plan", "rc", f"--branch={branch}", success=False)
            self.assertIn("namespace", result.stderr)

    def test_archive_is_stamped_reproducible_and_has_no_junk(self):
        item = self.plan("canary")[0]
        self.write("bazel/private/publish.py", "dirty working copy must not ship\n")
        self.write("bazel/untracked.txt", "must not ship\n")
        self.write("bazel/__pycache__/junk.pyc", "must not ship\n")
        self.write("bazel/bazel-out/junk", "must not ship\n")
        archive_path = self.package(item)
        first = archive_path.read_bytes()
        self.package(item)
        self.assertEqual(archive_path.read_bytes(), first)
        with tarfile.open(archive_path) as archive:
            prefix = "rules_tuist-0.1.0-canary.1/"
            self.assertEqual(
                set(archive.getnames()),
                {
                    prefix + p
                    for p in ["MODULE.bazel", "private/publish.py", "LICENSE.md"]
                },
            )
            module = archive.extractfile(prefix + "MODULE.bazel").read().decode()
            self.assertIn('version = "0.1.0-canary.1"', module)
            self.assertIn('version = "9.0.0"', module)
            self.assertEqual(
                archive.extractfile(prefix + "LICENSE.md").read(), b"fixture license\n"
            )
            self.assertEqual(
                archive.extractfile(prefix + "private/publish.py").read(),
                b'print("original")\n',
            )
        self.assertEqual(
            archive_path.with_suffix(".gz.sha256").read_text(),
            f"{hashlib.sha256(first).hexdigest()}  {archive_path.name}\n",
        )

    def test_prerelease_and_latest_flags(self):
        self.publish(self.plan("canary"))
        rc = self.cut_rc()
        self.publish(self.plan("promote", rc["branch"]))
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        for call in calls[:2]:
            self.assertIn("--prerelease", call)
            self.assertIn("--latest=false", call)
        self.assertNotIn("--prerelease", calls[2])
        self.assertIn("--latest=true", calls[2])
        self.assertTrue(all("--verify-tag" in call for call in calls))

    def test_tampered_archive_is_not_published(self):
        item = self.plan("rc-new")[0]
        self.package(item).write_bytes(b"tampered")
        self.cli("publish", json.dumps([item]), str(self.assets), success=False)
        self.assertEqual(self.git("ls-remote", "--tags", "origin"), "")
        self.assertFalse(self.calls.exists())

    def test_main_source_must_be_in_main_history(self):
        self.git("checkout", "--orphan", "untrusted")
        self.write("bazel/private/publish.py", "untrusted\n")
        self.commit()
        self.cli(
            "plan",
            "canary",
            "--sha",
            self.git("rev-parse", "HEAD").strip(),
            success=False,
        )

    def test_other_component_tags_do_not_anchor_version(self):
        self.git("tag", "kura@99.99.0")
        self.git("tag", "99.99.0")
        self.assertEqual(self.plan("rc-new")[0]["version"], "0.1.0-rc.1")

    def test_existing_branch_requires_iteration(self):
        self.git("push", "origin", "HEAD:refs/heads/releases/rules-tuist-0.1.x")
        self.cli("plan", "rc-new", success=False)

    def test_runtime_sources_ship_but_untracked_lock_does_not(self):
        names = [
            "MODULE.bazel",
            "BUILD.bazel",
            "apps.bzl",
            "runtime_test.py",
            "tool.cc",
            "greeting.cc",
        ]
        for name in names:
            self.write(f"bazel/tests/runtime/{name}", f"# fixture {name}\n")
        self.commit()
        self.write("bazel/tests/runtime/MODULE.bazel.lock", "generated and untracked\n")
        item = {"sha": self.git("rev-parse", "HEAD").strip(), "version": "0.1.0-rc.1"}
        with tarfile.open(self.package(item)) as archive:
            prefix = "rules_tuist-0.1.0-rc.1/tests/runtime/"
            self.assertTrue(
                {prefix + name for name in names} <= set(archive.getnames())
            )
            self.assertNotIn(prefix + "MODULE.bazel.lock", archive.getnames())

    def test_old_abandoned_rc_is_not_automatically_promoted(self):
        self.git("tag", "rules_tuist@0.1.0-rc.1")
        self.git("tag", "rules_tuist@0.2.0")
        self.assertEqual(self.plan("promote"), [])
        self.assertEqual(self.plan("rc-new")[0]["version"], "0.3.0-rc.1")

    def test_packager_rejects_wrong_module_and_tracked_junk(self):
        self.write("bazel/MODULE.bazel", 'module(name = "wrong", version = "0.1.0")\n')
        self.commit()
        self.cli("package", "HEAD", "0.1.0", str(self.assets), success=False)
        self.write(
            "bazel/MODULE.bazel", 'module(name = "rules_tuist", version = "0.1.0")\n'
        )
        self.write("bazel/__pycache__/tracked.pyc", "junk\n")
        self.commit()
        self.cli("package", "HEAD", "0.1.0", str(self.assets), success=False)


if __name__ == "__main__":
    unittest.main()
