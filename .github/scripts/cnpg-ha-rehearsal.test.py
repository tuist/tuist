#!/usr/bin/env python3
"""Credential-free checks for the staging rehearsal's mutation boundaries."""

import json
import os
import pathlib
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github/scripts/cnpg-ha-rehearsal.py"
Rehearsal = runpy.run_path(str(SCRIPT))["Rehearsal"]


class StagingRehearsalTest(unittest.TestCase):
    def test_rejects_other_environments_and_unscoped_names_before_kubectl(self):
        with tempfile.TemporaryDirectory() as output:
            for environment, run in [("production", "123-1"), ("canary", "123-1"),
                                     ("staging", "tuist-tuist-pg"), ("staging", "123-1/../../")]:
                with self.subTest(environment=environment, run=run):
                    result = subprocess.run(
                        ["python3", str(SCRIPT), "cleanup", "--run", run, "--output", output],
                        env={**os.environ, "ENVIRONMENT": environment}, capture_output=True,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(b"staging environment and numeric run-attempt", result.stderr)
            self.assertEqual(list(pathlib.Path(output).iterdir()), [])

    def test_workflow_rejects_wrong_target_before_credentials(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/cnpg-restore-drill.yml").read_text())
        job = workflow["jobs"]["staging-ha-rehearsal"]
        self.assertEqual(job["environment"], "server-k8s-staging")
        for environment, cleanup, expected in [("staging", "", 0), ("canary", "", 1), ("production", "", 1),
                                                ("", "", 1), ("staging", "123-2", 0), ("staging", "tuist-tuist-pg", 1),
                                                ("staging", "123-2/../../", 1)]:
            with self.subTest(environment=environment, cleanup=cleanup):
                result = subprocess.run(["bash", "-euc", job["steps"][0]["run"]],
                                        env={**os.environ, "REQUESTED_ENVIRONMENT": environment, "REQUESTED_CLEANUP_RUN": cleanup})
                self.assertEqual(result.returncode, expected)

    def test_cleanup_refuses_foreign_resources_and_verifies_volume_deletion(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            kubectl = directory / "kubectl"
            kubectl.write_text('''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps(a) + "\\n")
a = a[3:]
mode = os.environ["MODE"]
if a[0] == "get":
    kind = a[1]
    if kind == "clusters.postgresql.cnpg.io":
        print(json.dumps({"metadata": {"name": a[2], "namespace": "tuist-staging",
              "labels": {"tuist.dev/ha-rehearsal": "foreign" if mode == "foreign" else "123-1"}}}))
    elif kind == "pvc":
        print(json.dumps({"items": [{"metadata": {"name": "fixture-pvc"},
              "spec": {"storageClassName": "ha-rehearsal-123-1", "volumeName": "fixture-pv"}}]} if not os.path.exists(os.environ["REMOVED"]) else {"items": []}))
    elif kind == "pv":
        print(json.dumps({"metadata": {"name": "fixture-pv"}, "spec": {
              "claimRef": {"namespace": "tuist-staging", "name": "fixture-pvc"},
              "persistentVolumeReclaimPolicy": "Retain" if mode == "retain" else "Delete"}}))
    elif kind == "pods":
        print(json.dumps({"items": []}))
elif a[0] == "delete" and a[1] == "clusters.postgresql.cnpg.io":
    open(os.environ["REMOVED"], "w").close()
elif a[0] == "wait" and "pv/fixture-pv" in a and mode == "volume-stuck":
    sys.exit(42)
elif a[0] == "wait" and a[2].startswith("deployment/") and mode == "pooler-stuck":
    sys.exit(42)
''')
            kubectl.chmod(0o755)
            for mode in ["foreign", "retain", "success", "volume-stuck", "pooler-stuck"]:
                with self.subTest(mode=mode):
                    calls = directory / "calls"
                    removed = directory / "removed"
                    calls.write_text("")
                    removed.unlink(missing_ok=True)
                    result = subprocess.run(
                        ["python3", str(SCRIPT), "cleanup", "--run", "123-1", "--output", str(directory / "evidence")],
                        env={**os.environ, "ENVIRONMENT": "staging", "MODE": mode,
                             "PATH": str(directory) + os.pathsep + os.environ["PATH"],
                             "CALLS": str(calls), "REMOVED": str(removed)}, capture_output=True,
                    )
                    arguments = [json.loads(line)[3:] for line in calls.read_text().splitlines()]
                    deletions = [a for a in arguments if a[0] == "delete"]
                    if mode in ("foreign", "retain"):
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(deletions, [])
                    elif mode == "success":
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertTrue(all(a[2].startswith("ha-rehearsal-123-1") for a in deletions))
                        self.assertIn(["wait", "--for=delete", "pv/fixture-pv", "--timeout=3m"], arguments)
                    elif mode == "pooler-stuck":
                        self.assertNotEqual(result.returncode, 0)
                        self.assertFalse(any(a[1] == "clusters.postgresql.cnpg.io" for a in deletions))
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(["wait", "--for=delete", "pv/fixture-pv", "--timeout=3m"], arguments)
                        self.assertFalse(any(a[1] == "storageclass" for a in deletions))

    def test_real_chart_keeps_baseline_singleton_and_ha_pair_separate(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, ENVIRONMENT="staging"):
            rehearsal = Rehearsal("123-1", directory)
            baseline = rehearsal.render()
            ha = rehearsal.render(ha=True)
            old = next(o for o in baseline if o["kind"] == "Pooler")
            new = next(o for o in ha if o["kind"] == "Pooler")
            self.assertEqual(old["spec"]["instances"], 1)
            self.assertEqual(new["spec"]["instances"], 2)
            self.assertEqual(old["spec"]["pgbouncer"], new["spec"]["pgbouncer"])
            self.assertEqual(new["spec"]["deploymentStrategy"]["rollingUpdate"], {"maxSurge": 0, "maxUnavailable": 1})
            term = new["spec"]["template"]["spec"]["affinity"]["podAntiAffinity"]["requiredDuringSchedulingIgnoredDuringExecution"][0]
            self.assertEqual(term["topologyKey"], "kubernetes.io/hostname")
            self.assertEqual(term["labelSelector"]["matchLabels"], {"cnpg.io/poolerName": rehearsal.pooler})
            budget = next(o for o in ha if o["kind"] == "PodDisruptionBudget")
            self.assertEqual(budget["spec"]["maxUnavailable"], 1)
            self.assertEqual(budget["spec"]["selector"], term["labelSelector"])


if __name__ == "__main__":
    unittest.main()
