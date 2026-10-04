#!/usr/bin/env python3
"""Regression checks for production metrics and pull-through cache configuration.

Run with python3 infra/helm/test-production-errors.py (requires Helm and PyYAML).
"""

import pathlib
import subprocess
import tempfile
import unittest

import yaml

CHART = pathlib.Path(__file__).resolve().parent / "tuist"


def render(*settings, values=()):
    command = ["helm", "template", "tuist", str(CHART), "--set", "server.enabled=false"]
    for value in values:
        command.extend(["--values", str(CHART / value)])
    for setting in settings:
        command.extend(["--set", setting])
    return list(yaml.safe_load_all(subprocess.check_output(command, text=True)))


def resource(resources, kind, suffix):
    return next(r for r in resources if r and r["kind"] == kind and r["metadata"]["name"].endswith(suffix))


class ProductionErrorsTest(unittest.TestCase):
    def test_query_stats_extension_is_reconciled_in_the_exporters_database(self):
        resources = render("postgresql.cnpg.enabled=true", "postgresql.cnpg.queryStats.enabled=true")
        database = resource(resources, "Database", "-pg-query-stats")
        cluster = resource(resources, "Cluster", "-pg")
        queries = yaml.safe_load(resource(resources, "ConfigMap", "-pg-monitoring-queries")["data"]["queries"])
        self.assertEqual(database["spec"]["name"], cluster["spec"]["bootstrap"]["initdb"]["database"])
        self.assertEqual(database["spec"]["owner"], cluster["spec"]["bootstrap"]["initdb"]["owner"])
        self.assertEqual(database["spec"]["cluster"]["name"], cluster["metadata"]["name"])
        self.assertEqual(database["spec"]["databaseReclaimPolicy"], "retain")
        self.assertEqual(
            database["spec"]["extensions"],
            [{"name": "pg_stat_statements", "ensure": "present", "schema": "public"}],
        )
        self.assertEqual(queries["tuist_query_stats"]["target_databases"], [database["spec"]["name"]])
        self.assertIn("FROM public.pg_stat_statements", queries["tuist_query_stats"]["query"])
        self.assertEqual(
            cluster["spec"]["bootstrap"]["initdb"]["postInitApplicationSQL"],
            ["CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;"],
        )
        self.assertNotIn("ensure", database["spec"])
        self.assertEqual(cluster["spec"]["postgresql"]["parameters"]["pg_stat_statements.track"], "top")

    def test_query_stats_preserves_explicit_tracking_parameters(self):
        resources = render(
            "postgresql.cnpg.enabled=true",
            "postgresql.cnpg.queryStats.enabled=true",
            r"postgresql.cnpg.parameters.pg_stat_statements\.track=all",
        )
        cluster = resource(resources, "Cluster", "-pg")
        self.assertEqual(cluster["spec"]["postgresql"]["parameters"]["pg_stat_statements.track"], "all")

    def test_query_stats_enables_tracking_without_other_postgresql_settings(self):
        resources = render(
            "postgresql.cnpg.enabled=true",
            "postgresql.cnpg.queryStats.enabled=true",
            "postgresql.cnpg.instances=1",
            "postgresql.cnpg.parameters=null",
        )
        cluster = resource(resources, "Cluster", "-pg")
        self.assertEqual(cluster["spec"]["postgresql"]["parameters"], {"pg_stat_statements.track": "top"})

    def test_query_stats_respects_custom_database_and_owner_in_cnpg_mode(self):
        resources = render(
            "postgresql.mode=cnpg",
            "postgresql.cnpg.queryStats.enabled=true",
            "postgresql.cnpg.database=custom-db",
            "postgresql.cnpg.owner=custom_owner",
        )
        database = resource(resources, "Database", "-pg-query-stats")
        self.assertEqual(database["spec"]["name"], "custom-db")
        self.assertEqual(database["spec"]["owner"], "custom_owner")
        queries = yaml.safe_load(resource(resources, "ConfigMap", "-pg-monitoring-queries")["data"]["queries"])
        self.assertEqual(queries["tuist_query_stats"]["target_databases"], ["custom-db"])

    def test_query_stats_database_is_absent_when_disabled_or_not_using_cnpg(self):
        for settings in [
            ("postgresql.cnpg.enabled=true", "postgresql.cnpg.queryStats.enabled=false"),
            ("postgresql.cnpg.queryStats.enabled=true",),
        ]:
            resources = render(*settings)
            self.assertFalse(any(r and r["kind"] == "Database" for r in resources))
            if settings[0] == "postgresql.cnpg.enabled=true":
                cluster = resource(resources, "Cluster", "-pg")
                self.assertNotIn("pg_stat_statements.track", cluster["spec"]["postgresql"]["parameters"])

    def test_staging_rack_agent_can_repair_not_ready_nodes_without_targeting_unreachable_hosts(self):
        fleet = yaml.safe_load((CHART / "values-managed-staging.yaml").read_text())["rackLinuxFleet"]
        with tempfile.TemporaryDirectory() as directory:
            values = pathlib.Path(directory) / "rack-fleet.yaml"
            values.write_text(yaml.safe_dump({"rackLinuxFleet": fleet}))
            resources = render(values=(values,))
        tolerations = resource(resources, "DaemonSet", "-rack-linux-node-agent")["spec"]["template"]["spec"]["tolerations"]
        for key, expected in [("node.kubernetes.io/unreachable", False), ("node.kubernetes.io/not-ready", True)]:
            with self.subTest(key=key):
                tolerated = any(
                    t.get("effect", "NoSchedule") == "NoSchedule"
                    and (t.get("key", "") == key or (not t.get("key") and t.get("operator") == "Exists"))
                    for t in tolerations
                )
                self.assertEqual(tolerated, expected)
        self.assertIn({"key": "tuist.dev/rack-edge", "operator": "Exists", "effect": "NoSchedule"}, tolerations)

    def test_rack_agent_default_tolerations_are_unchanged(self):
        resources = render("rackLinuxFleet.enabled=true")
        agent = resource(resources, "DaemonSet", "-rack-linux-node-agent")
        self.assertEqual(agent["spec"]["template"]["spec"]["tolerations"], [{"operator": "Exists"}])

    def test_pull_through_cache_can_expire_cached_manifests(self):
        resources = render("registryCache.enabled=true")
        deployment = resource(resources, "Deployment", "-registry-cache")
        env = deployment["spec"]["template"]["spec"]["containers"][0]["env"]
        self.assertIn({"name": "REGISTRY_STORAGE_DELETE_ENABLED", "value": "true"}, env)
        self.assertIn({"name": "REGISTRY_STORAGE_S3_ROOTDIRECTORY", "value": "docker-mirror"}, env)
        self.assertEqual(deployment["spec"]["replicas"], 1)


if __name__ == "__main__":
    unittest.main()
