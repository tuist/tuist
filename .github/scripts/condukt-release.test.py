#!/usr/bin/env python3
"""Offline release regressions. Requires Python 3.11+, Bash 4+, git-cliff and jq."""

import importlib.util
import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / ".github/scripts"
spec = importlib.util.spec_from_file_location("artifacts", SCRIPTS / "condukt-artifacts.py")
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)
VERSION = "1.15.0"
SHA = "a" * 40

# All external commands in publication tests are local stubs. No credentials,
# GitHub, Hex or registry writes are possible from these tests.
STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps([name] + args) + "\n")
def output_path():
    return pathlib.Path(args[args.index("--output") + 1])
if name == "git":
    if args[:1] == ["rev-parse"]:
        print(os.environ.get("TAG_SHA", os.environ["SOURCE_SHA"]) if args[1].startswith("FETCH_HEAD") else os.environ["SOURCE_SHA"])
    elif args[:1] == ["ls-remote"]:
        if os.environ.get("GIT_ERROR"): sys.exit(1)
        if os.environ.get("TAG_SHA"): print(os.environ["TAG_SHA"] + "\trefs/tags/condukt@1.15.0")
elif name == "gh":
    if args[:1] == ["api"]:
        status = os.environ.get("RELEASE_STATUS", "404")
        print("HTTP/2.0 " + status)
        sys.exit(0 if status == "200" else 1)
    elif args[:2] == ["release", "download"]:
        dest = pathlib.Path(args[args.index("--dir") + 1])
        for p in pathlib.Path("nif-artifacts").rglob("*.tar.gz"):
            shutil.copy(p, dest / p.name)
        shutil.copy("condukt-1.15.0.tar", dest / "condukt-1.15.0.tar")
        if os.environ.get("EXISTING_MISMATCH"):
            (dest / "condukt-1.15.0.tar").write_bytes(b"different")
elif name == "curl":
    if "--write-out" in args:
        output_path().write_bytes(b"different" if os.environ.get("HEX_MISMATCH") else b"package")
        print(os.environ.get("HEX_STATUS", "404"), end="")
    else:
        if os.environ.get("DOWNLOAD_ERROR"): sys.exit(22)
        output_path().write_bytes(b"wrong" if os.environ.get("DOWNLOAD_MISMATCH") else b"native")
'''


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cwd = self.root / "condukt"
        self.cwd.mkdir()
        helper = self.root / ".github/scripts"
        helper.mkdir(parents=True)
        shutil.copy(SCRIPTS / "condukt-artifacts.py", helper)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("git", "gh", "curl", "mix"):
            path = self.bin / name
            path.write_text(STUB)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        RELEASE_VERSION=VERSION, RELEASE_TAG=f"condukt@{VERSION}",
                        SOURCE_SHA=SHA, GITHUB_REPOSITORY="tuist/tuist",
                        RUNNER_TEMP=str(self.root), LOG=str(self.root / "log"))
        for name in artifacts.expected_artifacts(VERSION):
            path = self.cwd / "nif-artifacts" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"native")
        (self.cwd / f"condukt-{VERSION}.tar").write_bytes(b"package")

    def run_script(self, script, success=True, **env):
        result = subprocess.run(["bash", str(SCRIPTS / script)], cwd=self.cwd,
                                env=dict(self.env, **env), capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        log = self.root / "log"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def test_create_before_all_sixteen_downloads(self):
        calls = self.run_script("condukt-publish.sh")
        create = next(i for i, call in enumerate(calls) if call[:3] == ["gh", "release", "create"])
        downloads = [i for i, call in enumerate(calls) if call[0] == "curl"]
        self.assertEqual(len(downloads), 16)
        self.assertLess(create, min(downloads))
        self.assertIn(SHA, calls[create])
        self.assertTrue(all("tuist/tuist/releases/download/condukt@1.15.0/" in " ".join(calls[i]) for i in downloads))

    def test_partial_matrix_never_publishes(self):
        next((self.cwd / "nif-artifacts").rglob("*.tar.gz")).unlink()
        calls = self.run_script("condukt-publish.sh", False)
        self.assertFalse(any(call[0] in ("gh", "curl", "mix") for call in calls))

    def test_existing_tag_wrong_source(self):
        calls = self.run_script("condukt-publish.sh", False, TAG_SHA="b" * 40)
        self.assertFalse(any(call[0] == "gh" for call in calls))

    def test_existing_release_is_verified_not_replaced(self):
        calls = self.run_script("condukt-publish.sh", RELEASE_STATUS="200", TAG_SHA=SHA)
        self.assertFalse(any(call[:3] == ["gh", "release", "create"] for call in calls))

    def test_fail_closed(self):
        for env in ({"RELEASE_STATUS": "403"}, {"RELEASE_STATUS": "500"},
                    {"GIT_ERROR": "1"}, {"DOWNLOAD_ERROR": "1"},
                    {"DOWNLOAD_MISMATCH": "1"},
                    {"RELEASE_STATUS": "200"},
                    {"RELEASE_STATUS": "200", "TAG_SHA": SHA, "EXISTING_MISMATCH": "1"}):
            with self.subTest(env=env):
                self.run_script("condukt-publish.sh", False, **env)

    def test_hex_missing_publishes(self):
        calls = self.run_script("condukt-hex.sh")
        self.assertIn(["mix", "hex.publish", "package", "--yes"], calls)

    def test_hex_existing_identical_is_not_republished(self):
        calls = self.run_script("condukt-hex.sh", HEX_STATUS="200")
        self.assertFalse(any(call[0] == "mix" for call in calls))

    def test_hex_mismatch_and_api_errors_fail(self):
        for env in ({"HEX_STATUS": "200", "HEX_MISMATCH": "1"}, {"HEX_STATUS": "503"}):
            with self.subTest(env=env):
                calls = self.run_script("condukt-hex.sh", False, **env)
                self.assertFalse(any(call[0] == "mix" for call in calls))


class ContractTests(unittest.TestCase):
    def test_migration_paths_and_local_consumers(self):
        def paths(workflow, event):
            # Read only the workflow's small, explicit event/path declarations,
            # not job-level paths. actionlint independently validates YAML.
            header = (ROOT / ".github/workflows" / workflow).read_text().split("\npermissions:")[0]
            block = re.search(rf"^  {event}:\n(.*?)(?=^  [a-z_]+:|\Z)", header, re.M | re.S)
            self.assertIsNotNone(block, workflow)
            path_block = re.search(r"^    paths: ?(.*?)(?=^    [a-z_]+:|\Z)", block[1], re.M | re.S)
            self.assertIsNotNone(path_block, workflow)
            return re.findall(r'"([^"]+)"', path_block[1]) if "[" in path_block[1] else [
                line.strip().removeprefix("- ").strip('"') for line in path_block[1].splitlines() if line.strip().startswith("- ")
            ]

        for workflow, path in (("condukt.yml", "condukt/lib/condukt.ex"),
                               ("condukt-egress.yml", "condukt/native/condukt_egress/src/main.rs")):
            for event in ("pull_request", "push"):
                globs = paths(workflow, event)
                self.assertTrue(any(fnmatch.fnmatchcase(path, glob) for glob in globs), (workflow, event))
                self.assertFalse(any(fnmatch.fnmatchcase("cli/Sources/main.swift", glob) for glob in globs))
        for workflow in ("server.yml", "atlas.yml", "server-release.yml", "atlas-release.yml"):
            for event in (("pull_request", "push") if "-release" not in workflow else ("push",)):
                self.assertTrue(any(fnmatch.fnmatchcase("condukt/lib/condukt.ex", glob) for glob in paths(workflow, event)))
        for consumer in ("server", "atlas"):
            manifest = (ROOT / consumer / "mix.exs").read_text()
            self.assertRegex(manifest, r'\{:condukt, path: "\.\./condukt", override: true\}')
            self.assertNotRegex((ROOT / consumer / "mix.lock").read_text(), r'"condukt"\s*:')

    def test_native_metadata_matches_matrix_and_version_namespace(self):
        actual = set()
        for crate, module in (("condukt_bashkit", "bashkit"), ("condukt_microsandbox", "microsandbox")):
            source = (ROOT / f"condukt/lib/condukt/{module}/nif.ex").read_text()
            self.assertIn('base_url: "https://github.com/tuist/tuist/releases/download/condukt@#{Mix.Project.config()[:version]}"', source)
            targets = re.search(r"targets: ~w\((.*?)\)", source, re.S)[1].split()
            nifs = re.search(r"nif_versions: ~w\((.*?)\)", source, re.S)[1].split()
            for target in targets:
                prefix, suffix = ("", "dll") if "windows" in target else ("lib", "so")
                for nif in nifs:
                    actual.add(f"{crate}/{prefix}{crate}-v{VERSION}-nif-{nif}-{target}.{suffix}.tar.gz")
        self.assertEqual(actual, artifacts.expected_artifacts(VERSION))
        manifest = (ROOT / "condukt/mix.exs").read_text()
        current = re.search(r'@version "([0-9.]+)"', manifest)[1]
        self.assertGreaterEqual(tuple(map(int, current.split("."))), (1, 15, 0))
        self.assertIn('source_ref: "condukt@#{@version}"', manifest)
        self.assertIn('/blob/condukt@#{@version}/condukt/%{path}', manifest)

    def test_matrix_and_workflow_gates(self):
        workflow = (ROOT / ".github/workflows/condukt-release.yml").read_text()
        rows = re.findall(r"crate: (\w+), nif: \"([^\"]+)\", target: ([\w-]+), os: ([\w-]+)", workflow)
        expected = set()
        for crate, nif, target, _ in rows:
            prefix, suffix = ("", "dll") if "windows" in target else ("lib", "so")
            expected.add(f"{crate}/{prefix}{crate}-v{VERSION}-nif-{nif}-{target}.{suffix}.tar.gz")
        self.assertEqual(len(rows), 16)
        self.assertEqual(expected, artifacts.expected_artifacts(VERSION))
        self.assertIn("needs: [plan, validate, validate-egress]", workflow)
        self.assertIn("needs: [plan, build-nifs]", workflow)
        self.assertLess(workflow.index("condukt-publish.sh"), workflow.index("condukt-hex.sh"))
        self.assertIn("MIX_ENV: prod", workflow)
        self.assertNotIn("pull_request:", workflow)
        self.assertNotIn("git push", workflow)
        components = json.loads((ROOT / "mise/tasks/release/components.json").read_text())["components"]
        config = next(c for c in components if c["name"] == "condukt")
        self.assertEqual(config["initial_version"], VERSION)
        for name in ("server", "atlas"):
            self.assertIn("condukt/**/*", next(c for c in components if c["name"] == name)["include_paths"])

    def test_scoped_registry_with_real_git_cliff(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "mise/tasks/release").mkdir(parents=True)
            (root / "condukt").mkdir()
            for name in ("components.json", "check.sh"):
                shutil.copy(ROOT / "mise/tasks/release" / name, root / "mise/tasks/release")
            shutil.copy(ROOT / "condukt/cliff.toml", root / "condukt")
            env = dict(os.environ, GIT_AUTHOR_NAME="Test", GIT_COMMITTER_NAME="Test",
                       GIT_AUTHOR_EMAIL="test@example.com", GIT_COMMITTER_EMAIL="test@example.com")

            def git(*args):
                return subprocess.run(["git", *args], cwd=root, env=env, check=True, capture_output=True, text=True)

            def check(expected, release):
                output = root / "output"
                output.write_text("")
                subprocess.run(["bash", "mise/tasks/release/check.sh", "condukt"], cwd=root,
                               env=dict(env, GITHUB_OUTPUT=str(output)), check=True, capture_output=True, text=True)
                self.assertIn(f"condukt-next-version-number={expected}\n", output.read_text())
                self.assertIn(f"condukt-should-release={str(release).lower()}\n", output.read_text())

            def commit(message):
                (root / "condukt/source").write_text(message)
                git("add", ".")
                git("commit", "-m", message)

            git("init", "-q")
            commit("feat(condukt): import")
            git("tag", "1.99.0")  # Other components' tags cannot set our version.
            check(VERSION, True)
            git("tag", "condukt@1.15.0")
            commit("fix(server): unrelated scope")
            check(VERSION, False)
            commit("chore(condukt): internal cleanup")
            check(VERSION, False)
            commit("fix(condukt): correct behavior")
            check("1.15.1", True)
            commit("feat(condukt,server): new behavior")
            check("1.16.0", True)
            commit("feat(condukt)!: breaking behavior")
            check("2.0.0", True)


if __name__ == "__main__":
    unittest.main()
