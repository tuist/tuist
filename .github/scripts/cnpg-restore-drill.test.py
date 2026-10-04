#!/usr/bin/env python3
"""Test restore-drill namespace resolution without cluster credentials."""

import os
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
        for exit_code in [0, 42]:
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as directory:
                directory = pathlib.Path(directory)
                command = directory / "kubectl"
                command.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$LOG"\nexit ' + str(exit_code) + '\n')
                command.chmod(0o755)
                log = directory / "arguments"
                result = subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", step["run"]],
                    env={**os.environ, "PATH": str(directory) + os.pathsep + os.environ["PATH"],
                         "NS": "tuist", "RECOVERY": "pg-restore-drill-test", "LOG": str(log)},
                    capture_output=True,
                )
                self.assertEqual(result.returncode, exit_code)
                arguments = log.read_text().splitlines()
                self.assertEqual(arguments[:5], ["-n", "tuist", "delete", "clusters.postgresql.cnpg.io", "pg-restore-drill-test"])
                self.assertIn("--wait=true", arguments)
                self.assertIn("--ignore-not-found", arguments)
                self.assertIn("--timeout=5m", arguments)

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
