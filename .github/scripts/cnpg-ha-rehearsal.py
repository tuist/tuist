#!/usr/bin/env python3
"""Exercise chart-generated pooler HA using disposable, synthetic staging data.

This is not a node drain, production load test, Tailscale or Pomerium test.
Only run-scoped resources are writable. The application's database is a
read-only control. Cleanup runs separately so CI also attempts it on failure.
"""

import argparse
import copy
import datetime
import json
import os
import pathlib
import re
import signal
import subprocess
import threading
import time

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
NS = "tuist-staging"
MARKERS = "7:before-roll,19:asymmetric-control"
SYNC = {"method": "any", "number": 1, "dataDurability": "required"}


def command(*args, stdin=None, timeout=30):
    return subprocess.run(args, input=stdin, text=True, capture_output=True,
                          check=True, timeout=timeout).stdout.strip()


class Rehearsal:
    def __init__(self, run, output):
        if os.environ.get("ENVIRONMENT") != "staging" or not re.fullmatch(r"[0-9]+-[0-9]+", run):
            raise ValueError("A staging environment and numeric run-attempt identity are required")
        self.name = f"ha-rehearsal-{run}"
        self.cluster = self.name + "-pg"
        self.pooler = self.cluster + "-pooler-rw"
        self.client = self.name + "-client"
        self.labels = {"tuist.dev/ha-rehearsal": run}
        self.output = pathlib.Path(output)
        self.output.mkdir(parents=True, exist_ok=True)
        self.baseline = None
        self.last_control = 0
        self.peak_memory = 0
        self.phase = "baseline"
        self.probes = []
        self.stop = threading.Event()

    def kubectl(self, *args, stdin=None, timeout=30):
        return command("kubectl", "--request-timeout=20s", "-n", NS, *args,
                       stdin=stdin, timeout=timeout)

    def get(self, kind, name=None, selector=None):
        args = ["get", kind]
        if name:
            args += [name, "--ignore-not-found"]
        if selector:
            args += ["-l", selector]
        raw = self.kubectl(*args, "-o", "json")
        return json.loads(raw) if raw else None

    def save(self, name, value):
        (self.output / (name + ".json")).write_text(json.dumps(value, indent=2) + "\n")

    def owned(self, obj):
        metadata = obj["metadata"]
        if (not metadata["name"].startswith(self.name)
                or any(metadata.get("labels", {}).get(k) != v for k, v in self.labels.items())
                or metadata.get("namespace", NS) != NS):
            raise ValueError("Refusing mutation outside this staging rehearsal")

    def apply(self, obj):
        metadata = obj["metadata"]
        metadata.setdefault("labels", {}).update(self.labels)
        if obj["kind"] != "StorageClass":
            metadata["namespace"] = NS
        self.owned(obj)
        kind = {"Cluster": "clusters.postgresql.cnpg.io", "Pooler": "poolers.postgresql.cnpg.io"}.get(obj["kind"], obj["kind"])
        existing = self.get(kind, metadata["name"])
        if existing:
            self.owned(existing)
            assert not existing["metadata"].get("deletionTimestamp"), "Fixture cleanup has started"
        print(f"Applying {obj['kind']}/{metadata['name']}", flush=True)
        self.kubectl("apply", "-f", "-", stdin=json.dumps(obj))

    def patch(self, kind, name, patch, status=False):
        existing = self.get(kind, name)
        self.owned(existing)
        assert not existing["metadata"].get("deletionTimestamp"), "Fixture cleanup has started"
        args = ["patch", kind, name, "--type=merge", "-p", json.dumps(patch)]
        if status:
            args += ["--subresource=status"]
        self.kubectl(*args)

    def sql(self, pod, query, fixture=False, hostaddr=None):
        if fixture:
            args = ["exec", self.client, "--", "env"]
            if hostaddr:
                args += [f"PGHOSTADDR={hostaddr}"]
            args += ["timeout", "8s", "psql", "-XAt", "-v", "ON_ERROR_STOP=1", "-c", query]
        else:
            args = ["exec", pod, "-c", "postgres", "--", "psql", "-XAt",
                    "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres", "-c", query]
        return self.kubectl(*args, timeout=15)

    def control(self):
        source = self.get("clusters.postgresql.cnpg.io", "tuist-tuist-pg")
        web = self.get("deployment", "tuist-tuist-server")
        identity = [source["metadata"]["uid"], source["metadata"]["generation"],
                    source["status"]["currentPrimary"], web["metadata"]["generation"]]
        assert source["status"]["readyInstances"] == source["spec"]["instances"] == 2
        assert web["status"].get("availableReplicas", 0) >= web["spec"]["replicas"]
        assert self.sql(source["status"]["currentPrimary"], "SELECT 1") == "1"
        if self.baseline is None:
            self.baseline = identity
        assert identity == self.baseline, "Live control changed: stop for concurrent maintenance"
        nodes = self.get("nodes", selector="node.cluster.x-k8s.io/pool=general")["items"]
        assert len(nodes) >= 2 and all(n["metadata"]["name"].startswith("tuist-staging-") for n in nodes)
        for node in nodes:
            assert not node["spec"].get("unschedulable")
            assert any(c["type"] == "Ready" and c["status"] == "True" for c in node["status"]["conditions"])
        metrics = json.loads(self.kubectl("get", "--raw", "/apis/metrics.k8s.io/v1beta1/nodes"))
        usage = {n["metadata"]["name"]: quantity(n["usage"]["memory"]) for n in metrics["items"]}
        for node in nodes:
            capacity = quantity(node["status"]["allocatable"]["memory"])
            used = usage[node["metadata"]["name"]]
            self.peak_memory = max(self.peak_memory, used / capacity)
            assert used / capacity < 0.90, "Stop: general-worker memory reached 90%"
            if self.phase == "baseline":
                assert capacity - used >= 1024 ** 3, "Need at least 1 GiB spare on each fixture host"
        self.last_control = time.monotonic()
        return source

    def wait(self, description, predicate, seconds=600):
        print(description, flush=True)
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if time.monotonic() - self.last_control > 15:
                self.control()
            self.check_probe_bounds()
            if predicate():
                return
            time.sleep(3)
        raise TimeoutError(description)

    def pooler_pods(self):
        return [p for p in self.get("pods", selector=f"cnpg.io/poolerName={self.pooler}")["items"]
                if not p["metadata"].get("deletionTimestamp")]

    def pooler_ready(self, count):
        pods = self.pooler_pods()
        return len(pods) == count and all(any(c["type"] == "Ready" and c["status"] == "True"
                                             for c in p["status"].get("conditions", [])) for p in pods)

    def database_ready(self):
        obj = self.get("clusters.postgresql.cnpg.io", self.cluster)
        return obj and obj.get("status", {}).get("readyInstances") == 2 and obj["status"].get("phase") == "Cluster in healthy state"

    def ceiling_ready(self):
        if not self.database_ready():
            return False
        pods = self.get("pods", selector=f"cnpg.io/cluster={self.cluster},cnpg.io/podRole=instance")["items"]
        if len(pods) != 2:
            return False
        try:
            return all(self.sql(p["metadata"]["name"], "SHOW max_connections") == "450" for p in pods)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            # Ready status can briefly lag the managed database restart.
            return False

    def render(self, ha=False):
        chart = ROOT / "infra/helm/tuist"
        args = ["helm", "template", self.name, str(chart), "--namespace", NS,
                "-f", str(chart / "values-ci.yaml"), "-f", str(chart / "values-self-hosted-ci.yaml"),
                "--set", f"fullnameOverride={self.name}", "--set", "postgresql.mode=cnpg",
                "--set", "postgresql.cnpg.pooler.enabled=true",
                "--set-string", "postgresql.cnpg.pooler.parameters.max_client_conn=200",
                "--set-string", "postgresql.cnpg.pooler.parameters.client_idle_timeout=300",
                "--show-only", "templates/postgresql-cnpg.yaml",
                "--show-only", "templates/postgresql-cnpg-pooler.yaml"]
        if ha:
            args += ["-f", str(chart / "values-maintenance-ha.yaml")]
        objects = [o for o in yaml.safe_load_all(command(*args)) if o and o["kind"] in ("Cluster", "Pooler", "PodDisruptionBudget")]
        for obj in objects:
            if obj["kind"] == "Pooler":
                spec = obj["spec"].setdefault("template", {}).setdefault("spec", {})
                spec["nodeSelector"] = {"node.cluster.x-k8s.io/pool": "general"}
                spec["containers"] = [{"name": "pgbouncer", "resources": {
                    "requests": {"cpu": "25m", "memory": "32Mi"},
                    "limits": {"cpu": "250m", "memory": "128Mi"}}}]
        return objects

    def provision(self):
        source = self.control()
        self.save("cases", {"scope": "staging synthetic database/pooler only",
                  "cases": ["baseline", "database_restart", "ha_activation", "pooler_eviction",
                            "pooler_rollout", "database_switchover", "recovery"],
                  "bounds": {"query_seconds": 8, "recovery_seconds": 60,
                             "worker_memory_fraction": 0.9, "acknowledged_writes_lost": 0},
                  "not_qualified": ["production load", "node loss", "Tailscale", "Pomerium", "kernel rollout"]})
        for kind, name in [("clusters.postgresql.cnpg.io", self.cluster), ("poolers.postgresql.cnpg.io", self.pooler),
                           ("pods", self.client), ("storageclass", self.name)]:
            assert self.get(kind, name) is None, f"Fixture already exists: {name}"
        pvcs = self.get("pvc", selector="cnpg.io/cluster=tuist-tuist-pg,cnpg.io/pvcRole=PG_DATA")["items"]
        source_class = self.get("storageclass", pvcs[0]["spec"]["storageClassName"])
        storage = {k: copy.deepcopy(source_class[k]) for k in
                   ("provisioner", "parameters", "mountOptions", "allowVolumeExpansion", "volumeBindingMode", "allowedTopologies") if k in source_class}
        storage.update(apiVersion="storage.k8s.io/v1", kind="StorageClass",
                       metadata={"name": self.name}, reclaimPolicy="Delete")
        self.apply(storage)
        baseline = self.render()
        cluster = next(o for o in baseline if o["kind"] == "Cluster")
        spec = cluster["spec"]
        for key in ("backup", "plugins", "managed", "monitoring"):
            spec.pop(key, None)
        spec.update(imageName=source["spec"]["imageName"], instances=2, enableSuperuserAccess=False,
                    storage={"size": "10Gi", "storageClass": self.name},
                    resources={"requests": {"cpu": "100m", "memory": "192Mi"},
                               "limits": {"cpu": "500m", "memory": "512Mi"}})
        # The operator's default server certificate covers database Services,
        # not the separately named Pooler Service verified by the test client.
        spec["certificates"] = {"serverAltDNSNames": [self.pooler + f".{NS}.svc"]}
        spec["affinity"]["nodeSelector"] = {"node.cluster.x-k8s.io/pool": "general"}
        spec["postgresql"] = {"parameters": {"max_connections": "100", "shared_buffers": "32MB", "work_mem": "1MB"}, "synchronous": SYNC}
        spec["bootstrap"] = {"initdb": {"database": "rehearsal", "owner": "rehearsal", "postInitApplicationSQL": [
            "CREATE TABLE markers(id integer PRIMARY KEY, payload text NOT NULL)",
            "INSERT INTO markers VALUES (7,'before-roll'),(19,'asymmetric-control')",
            "CREATE TABLE probes(id integer PRIMARY KEY, payload text NOT NULL)",
            "GRANT SELECT ON markers TO rehearsal", "GRANT SELECT, INSERT ON probes TO rehearsal"]}}
        self.save("fixture-cluster", cluster)
        self.apply(cluster)
        self.wait("Waiting for two synchronous fixture database instances", self.database_ready)
        pooler = next(o for o in baseline if o["kind"] == "Pooler")
        self.apply(pooler)
        self.wait("Waiting for baseline singleton pooler", lambda: self.pooler_ready(1))
        client = {"apiVersion": "v1", "kind": "Pod", "metadata": {"name": self.client}, "spec": {
            "automountServiceAccountToken": False, "restartPolicy": "Never",
            "activeDeadlineSeconds": 1800, "nodeSelector": {"node.cluster.x-k8s.io/pool": "general"},
            "containers": [{"name": "client", "image": spec["imageName"], "command": ["sleep", "1800"],
                "resources": {"requests": {"cpu": "25m", "memory": "32Mi"}, "limits": {"cpu": "250m", "memory": "128Mi"}},
                "env": [{"name": "PGHOST", "value": self.pooler + f".{NS}.svc"},
                        {"name": "PGDATABASE", "value": "rehearsal"},
                        {"name": "PGUSER", "value": "rehearsal"},
                        {"name": "PGPASSWORD", "valueFrom": {"secretKeyRef": {"name": self.cluster + "-app", "key": "password"}}},
                        {"name": "PGSSLMODE", "value": "verify-full"},
                        {"name": "PGSSLROOTCERT", "value": "/ca/ca.crt"},
                        {"name": "PGCONNECT_TIMEOUT", "value": "3"}],
                "volumeMounts": [{"name": "ca", "mountPath": "/ca", "readOnly": True}]}],
            "volumes": [{"name": "ca", "secret": {"secretName": self.cluster + "-ca", "items": [{"key": "ca.crt", "path": "ca.crt"}]}}]}}
        self.apply(client)
        self.kubectl("wait", "--for=condition=Ready", "pod/" + self.client, "--timeout=120s", timeout=130)

    def probe_loop(self):
        index = 0
        with (self.output / "probes.jsonl").open("w") as log:
            while not self.stop.is_set():
                index += 1
                event = {"id": index, "phase": self.phase, "time": time.time()}
                started = time.monotonic()
                try:
                    result = self.sql(None, f"WITH inserted AS (INSERT INTO probes VALUES ({index},'probe-{index}') RETURNING id) "
                                      f"SELECT (SELECT string_agg(id::text||':'||payload,',' ORDER BY id) FROM markers),id,inet_server_addr() FROM inserted", fixture=True)
                    fields = result.split("|")
                    event.update(ok=fields[:2] == [MARKERS, str(index)], result=result)
                except (subprocess.SubprocessError, OSError) as error:
                    event.update(ok=False, error=str(error), stderr=getattr(error, "stderr", None))
                event["duration"] = time.monotonic() - started
                self.probes.append(event)
                log.write(json.dumps(event) + "\n")
                log.flush()
                self.stop.wait(1)

    def check_probe_bounds(self):
        failed_at = None
        longest = 0
        for event in list(self.probes):
            assert event["ok"] or "result" not in event, "SQL returned incorrect marker/probe data"
            if not event["ok"] and failed_at is None:
                failed_at = event["time"]
            if event["ok"] and failed_at is not None:
                longest = max(longest, event["time"] + event["duration"] - failed_at)
                failed_at = None
        if failed_at is not None:
            longest = max(longest, time.time() - failed_at)
        assert longest <= 60, "Fixture SQL has not recovered within 60 seconds"
        return longest

    def exercise(self):
        self.provision()
        worker = threading.Thread(target=self.probe_loop)
        worker.start()
        try:
            self.wait("Collecting baseline writes", lambda: len(self.probes) >= 4, seconds=90)
            assert all(e["ok"] for e in self.probes), "Baseline SQL failed"
            self.phase = "database_restart"
            self.patch("clusters.postgresql.cnpg.io", self.cluster, {"spec": {"postgresql": {"parameters": {"max_connections": "450"}}}})
            self.wait("Qualifying effective connection ceiling on both fixture instances", self.ceiling_ready)
            self.phase = "ha_activation"
            for obj in self.render(ha=True):
                if obj["kind"] in ("Pooler", "PodDisruptionBudget"):
                    self.save("ha-" + obj["kind"].lower(), obj)
                    self.apply(obj)
            self.wait("Waiting for two chart-generated HA poolers", lambda: self.pooler_ready(2))
            self.wait("Waiting for the pooler eviction budget", lambda: self.get("poddisruptionbudget", self.pooler).get("status", {}).get("disruptionsAllowed") == 1)
            pods = self.pooler_pods()
            self.save("separate-pooler-hosts", [{"name": p["metadata"]["name"], "uid": p["metadata"]["uid"], "node": p["spec"]["nodeName"]} for p in pods])
            assert len({p["spec"]["nodeName"] for p in pods}) == 2
            for pod in pods:
                assert self.sql(None, "SELECT string_agg(id::text||':'||payload,',' ORDER BY id) FROM markers", fixture=True,
                                hostaddr=pod["status"]["podIP"]) == MARKERS
            self.phase = "pooler_eviction"
            def eviction(pod, dry_run=False):
                name = pod["metadata"]["name"]
                assert name.startswith(self.pooler + "-")
                options = {"preconditions": {"uid": pod["metadata"]["uid"]}}
                if dry_run:
                    options["dryRun"] = ["All"]
                body = {"apiVersion": "policy/v1", "kind": "Eviction", "metadata": {"name": name, "namespace": NS}, "deleteOptions": options}
                return self.kubectl("create", "--raw", f"/api/v1/namespaces/{NS}/pods/{name}/eviction", "-f", "-", stdin=json.dumps(body))
            eviction(pods[0])
            try:
                eviction(pods[1], dry_run=True)
            except subprocess.CalledProcessError as error:
                assert "disruption budget" in error.stderr.lower(), error.stderr
                self.save("second-eviction", {"denied": True, "reason": error.stderr})
            else:
                raise AssertionError("Second eviction was not denied; do not count a raced recovery as proof")
            self.wait("Recovering after one voluntary eviction", lambda: self.pooler_ready(2))
            self.phase = "pooler_rollout"
            old = {p["metadata"]["uid"] for p in self.pooler_pods()}
            self.patch("poolers.postgresql.cnpg.io", self.pooler, {"spec": {"template": {"metadata": {"annotations": {"tuist.dev/ha-rehearsal-roll": self.name}}}}})
            self.wait("Replacing both poolers without changing their capacity", lambda: self.pooler_ready(2) and not old.intersection(p["metadata"]["uid"] for p in self.pooler_pods()))
            self.phase = "database_switchover"
            before = self.get("clusters.postgresql.cnpg.io", self.cluster)["status"]["currentPrimary"]
            target = next(p["metadata"]["name"] for p in self.get("pods", selector=f"cnpg.io/cluster={self.cluster},cnpg.io/podRole=instance")["items"] if p["metadata"]["name"] != before)
            self.patch("clusters.postgresql.cnpg.io", self.cluster, {"status": {"targetPrimary": target,
                "targetPrimaryTimestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "phase": "Switchover in progress", "phaseReason": f"Switching over to {target}"}}, status=True)
            self.wait("Qualifying controlled synchronous database handoff", lambda: self.database_ready() and self.get("clusters.postgresql.cnpg.io", self.cluster)["status"]["currentPrimary"] == target)
            self.phase = "recovery"
            start = len(self.probes)
            self.wait("Collecting final recovered writes", lambda: len(self.probes) >= start + 10, seconds=90)
            assert all(e["ok"] for e in self.probes[start:]), "Recovered SQL is not stable"
        finally:
            self.stop.set()
            worker.join(timeout=20)
        self.check_probe_bounds()
        rows = self.sql(None, "SELECT id,payload FROM probes ORDER BY id", fixture=True)
        committed = {int(line.split("|")[0]): line.split("|")[1] for line in rows.splitlines()}
        acknowledged = {e["id"] for e in self.probes if e["ok"]}
        assert acknowledged and all(committed.get(i) == f"probe-{i}" for i in acknowledged), "An acknowledged write was lost or changed"
        assert set(committed).issubset({e["id"] for e in self.probes}), "Unexpected fixture writes"
        assert self.get("clusters.postgresql.cnpg.io", self.cluster)["spec"]["postgresql"]["synchronous"] == SYNC
        self.control()
        summary = {"passed": True, "queries": len(self.probes), "failures": sum(not e["ok"] for e in self.probes),
                   "acknowledged_writes": len(acknowledged), "committed_writes": len(committed),
                   "longest_observed_recovery_seconds": self.check_probe_bounds(),
                   "ambiguous_commits_not_retried": sorted(set(committed) - acknowledged),
                   "primary_before": before, "primary_after": target, "peak_general_worker_memory_fraction": self.peak_memory,
                   "scope": "synthetic staging CNPG/PgBouncer; no node, application-database, Tailscale or Pomerium changes"}
        self.save("result", summary)
        print(json.dumps(summary), flush=True)

    def cleanup(self):
        # Stop clients and remove the database before its Pooler: CNPG 1.29.1
        # otherwise recreates children while foreground Pooler deletion waits.
        resources = [("pod", self.client), ("clusters.postgresql.cnpg.io", self.cluster),
                     ("poolers.postgresql.cnpg.io", self.pooler), ("poddisruptionbudget", self.pooler), ("storageclass", self.name)]
        # Check every existing object before deleting any. A collision must
        # never turn an unsuccessful provision into someone else's teardown.
        for kind, name in resources:
            obj = self.get(kind, name)
            if obj:
                self.owned(obj)
        claims = self.get("pvc", selector=f"cnpg.io/cluster={self.cluster}")["items"]
        volumes = []
        for claim in claims:
            assert claim["spec"]["storageClassName"] == self.name
            if claim["spec"].get("volumeName"):
                volume = self.get("pv", claim["spec"]["volumeName"])
                assert volume["spec"]["claimRef"]["namespace"] == NS
                assert volume["spec"]["claimRef"]["name"] == claim["metadata"]["name"]
                assert volume["spec"]["persistentVolumeReclaimPolicy"] == "Delete"
                volumes.append(volume["metadata"]["name"])
        for kind, name in resources[:-1]:
            self.kubectl("delete", kind, name, "--ignore-not-found", "--cascade=foreground", "--wait=true", "--timeout=3m", timeout=190)
        assert not self.get("pvc", selector=f"cnpg.io/cluster={self.cluster}")["items"], "Fixture PVCs remain"
        for volume in volumes:
            self.kubectl("wait", "--for=delete", "pv/" + volume, "--timeout=3m", timeout=190)
        self.kubectl("delete", "storageclass", self.name, "--ignore-not-found", "--wait=true", "--timeout=1m", timeout=70)
        self.save("cleanup", {"passed": True, "volumes_deleted": volumes})


def quantity(value):
    match = re.fullmatch(r"([0-9.]+)(Ki|Mi|Gi|Ti)?", value)
    if not match:
        raise ValueError(f"Unsupported memory quantity: {value}")
    return float(match[1]) * {None: 1, "Ki": 1024, "Mi": 1024 ** 2, "Gi": 1024 ** 3, "Ti": 1024 ** 4}[match[2]]


if __name__ == "__main__":
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["run", "cleanup"])
    parser.add_argument("--run", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    rehearsal = Rehearsal(args.run, args.output)
    try:
        rehearsal.exercise() if args.action == "run" else rehearsal.cleanup()
    except Exception as error:
        rehearsal.save(args.action + "-failure", {"type": type(error).__name__, "error": str(error),
                                                "stderr": getattr(error, "stderr", None)})
        raise
