#!/usr/bin/env python3
"""Test restore-drill namespace resolution without cluster credentials."""

import copy
import os
import runpy
import pathlib
import subprocess
import tempfile
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/cnpg-restore-drill.yml"


class RestoreDrillNamespaceTest(unittest.TestCase):
    def test_namespace_matches_the_deployment_environment(self):
        workflow = yaml.safe_load(WORKFLOW.read_text())
        step = next(
            s for s in workflow["jobs"]["restore-drill"]["steps"]
            if s.get("name") == "Resolve namespace"
        )
        for environment, expected in [("staging", "tuist-staging"), ("canary", "tuist-canary"), ("production", "tuist")]:
            with self.subTest(environment=environment), tempfile.TemporaryDirectory() as directory:
                output = pathlib.Path(directory) / "github-env"
                subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", step["run"]],
                    env={**os.environ, "ENVIRONMENT": environment, "GITHUB_ENV": str(output)},
                    check=True,
                )
                self.assertEqual(output.read_text(), f"NS={expected}\n")

    def test_cleanup_targets_only_the_drill_and_propagates_failure(self):
        workflow = yaml.safe_load(WORKFLOW.read_text())
        step = next(
            s for s in workflow["jobs"]["restore-drill"]["steps"]
            if s.get("name") == "Tear down recovery cluster"
        )
        for mode, expected in [("success", 0), ("delete-fails", 42), ("pvc-remains", 1), ("pv-remains", 43)]:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                directory = pathlib.Path(directory)
                command = directory / "kubectl"
                command.write_text('''#!/bin/sh
printf "%s\\n" "$@" >> "$LOG"
printf -- "--CALL--\\n" >> "$LOG"
case "$*" in
  *"delete clusters.postgresql.cnpg.io"*) [ "$MODE" != delete-fails ] || exit 42 ;;
  *"get pvc"*"jsonpath"*) printf "pv-drill " ;;
  *"get pvc"*"-o name"*) [ "$MODE" != pvc-remains ] || printf "pvc/drill\\n" ;;
  *"wait --for=delete pv/"*) [ "$MODE" != pv-remains ] || exit 43 ;;
esac
exit 0
''')
                command.chmod(0o755)
                log = directory / "arguments"
                result = subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", step["run"]],
                    env={**os.environ, "PATH": str(directory) + os.pathsep + os.environ["PATH"],
                         "NS": "tuist", "RECOVERY": "pg-restore-drill-test", "LOG": str(log), "MODE": mode},
                    capture_output=True,
                )
                self.assertEqual(result.returncode, expected)
                calls = [call.splitlines() for call in log.read_text().split("--CALL--\n") if call]
                deletion = next(call for call in calls if call[:4] == ["-n", "tuist", "delete", "clusters.postgresql.cnpg.io"])
                self.assertEqual(deletion[:5], ["-n", "tuist", "delete", "clusters.postgresql.cnpg.io", "pg-restore-drill-test"])
                for flag in ["--wait=true", "--ignore-not-found", "--cascade=foreground", "--timeout=5m"]:
                    self.assertIn(flag, deletion)
                if mode == "success":
                    self.assertIn(["wait", "--for=delete", "pv/pv-drill", "--timeout=5m"], calls)
                    self.assertEqual(calls[-1][:3], ["delete", "storageclass", "pg-restore-drill-test"])

    def test_recovery_storage_is_disposable_without_changing_source(self):
        workflow = yaml.safe_load(WORKFLOW.read_text())
        launch = next(s for s in workflow["jobs"]["restore-drill"]["steps"] if s.get("name") == "Launch recovery cluster")
        self.assertIn("storageClass: $RECOVERY", launch["run"])
        builder = runpy.run_path(str(ROOT / ".github/scripts/cnpg-restore-storage.py"))["recovery_storage_class"]
        source = {
            "metadata": {"name": "source", "annotations": {"storageclass.kubernetes.io/is-default-class": "true"}},
            "provisioner": "csi.hetzner.cloud", "reclaimPolicy": "Retain",
            "parameters": {"csi.storage.k8s.io/fstype": "xfs"},
            "mountOptions": ["noatime"], "volumeBindingMode": "WaitForFirstConsumer",
        }
        original = copy.deepcopy(source)
        result = builder(source, "pg-restore-drill-test")
        self.assertEqual(result["reclaimPolicy"], "Delete")
        self.assertEqual(result["metadata"]["name"], "pg-restore-drill-test")
        self.assertNotIn("annotations", result["metadata"])
        for key in ["provisioner", "parameters", "mountOptions", "volumeBindingMode"]:
            self.assertEqual(result[key], source[key])
        result["parameters"]["csi.storage.k8s.io/fstype"] = "ext4"
        self.assertEqual(source, original)
        with self.assertRaises(ValueError):
            builder(source, "tuist-tuist-pg")
        with self.assertRaises(ValueError):
            builder({**source, "metadata": {"name": "pg-restore-drill-test"}}, "pg-restore-drill-test")

    def test_unknown_environment_is_rejected(self):
        workflow = yaml.safe_load(WORKFLOW.read_text())
        step = next(
            s for s in workflow["jobs"]["restore-drill"]["steps"]
            if s.get("name") == "Resolve namespace"
        )
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "github-env"
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", step["run"]],
                env={**os.environ, "ENVIRONMENT": "unsupported", "GITHUB_ENV": str(output)},
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
