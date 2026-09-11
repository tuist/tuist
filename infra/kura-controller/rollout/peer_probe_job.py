"""Run peer-network checks in the target cluster, outside runner egress policy."""

import inspect
import ipaddress
import threading
import json
import os
import subprocess
import time
import uuid


IMAGE = "python:3.13-slim@sha256:9d2e5553305c7c7b0097999bb17187c69b921ccd6bc9d40e4bb5ebe652c00285"


def command(args, payload=None, timeout=30):
    cmd = ["kubectl", f"--request-timeout={timeout}s"]
    if os.environ.get("KURA_ROLLOUT_CONTEXT"):
        cmd += ["--context", os.environ["KURA_ROLLOUT_CONTEXT"]]
    result = subprocess.run(cmd + args, input=payload, capture_output=True, text=True, timeout=timeout + 5)
    if result.returncode:
        raise RuntimeError("peer validation job command failed: " + (result.stderr or result.stdout).strip())
    return result.stdout


class PeerProbeJob:
    def __init__(self, namespace, lifetime=900, node_name=None):
        self.namespace = namespace
        self.lifetime = lifetime
        self.node_name = node_name
        self.name = "kura-regional-probe-" + uuid.uuid4().hex[:12]
        self.pod = None

    def manifest(self):
        manifest = {
            "apiVersion": "batch/v1", "kind": "Job",
            "metadata": {"name": self.name, "namespace": self.namespace},
            "spec": {
                "backoffLimit": 0, "activeDeadlineSeconds": self.lifetime, "ttlSecondsAfterFinished": 300,
                "template": {
                    "metadata": {"labels": {"app.kubernetes.io/name": "kura-regional-probe"}},
                    "spec": {
                        "restartPolicy": "Never", "automountServiceAccountToken": False,
                        "terminationGracePeriodSeconds": 1,
                        "nodeSelector": {"kubernetes.io/os": "linux"},
                        "securityContext": {"runAsNonRoot": True, "runAsUser": 65532, "fsGroup": 65532,
                                            "seccompProfile": {"type": "RuntimeDefault"}},
                        "containers": [{
                            "name": "probe", "image": IMAGE,
                            "command": ["python3", "-c", f"import time; time.sleep({self.lifetime})"],
                            "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True,
                                                "capabilities": {"drop": ["ALL"]}},
                            "resources": {"requests": {"cpu": "25m", "memory": "64Mi"},
                                          "limits": {"cpu": "1", "memory": "256Mi"}},
                            "volumeMounts": [{"name": "temporary", "mountPath": "/tmp"}],
                        }],
                        "volumes": [{"name": "temporary", "emptyDir": {"medium": "Memory", "sizeLimit": "32Mi"}}],
                    },
                },
            },
        }

        if self.node_name:
            # IPv4-only Pod networks cannot test public IPv6. Use the selected
            # IPv6 ingress node's network without privileged/root capabilities.
            spec = manifest["spec"]["template"]["spec"]
            spec.update(nodeName=self.node_name, hostNetwork=True, dnsPolicy="ClusterFirstWithHostNet",
                        tolerations=[{"operator": "Exists"}])
        return manifest

    def __enter__(self):
        command(["-n", self.namespace, "create", "-f", "-"], json.dumps(self.manifest()))
        try:
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                pods = json.loads(command(["-n", self.namespace, "get", "pods", "-l", "job-name=" + self.name, "-o", "json"]))
                for pod in pods["items"]:
                    if any(c["type"] == "Ready" and c["status"] == "True" for c in pod.get("status", {}).get("conditions", [])):
                        self.pod = pod["metadata"]["name"]
                        return self
                time.sleep(3)
            raise RuntimeError("peer validation job did not become Ready")
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def probe(self, function, host, addresses, secret):
        # Credentials travel over exec stdin, never as arguments, Pod/Job fields
        # or logs. The invoked function uses private files on the memory volume.
        source = "import base64, http.client, json, os, socket, ssl, sys, tempfile\nfrom pathlib import Path\n"
        source += inspect.getsource(function)
        source += "\npayload = json.load(sys.stdin)\n"
        source += "try:\n    peer_probe(payload['host'], payload['addresses'], payload['secret'])\n"
        source += "except Exception as error:\n    print(str(error), file=sys.stderr)\n    sys.exit(1)\n"
        payload = {"host": host, "addresses": sorted(addresses), "secret": {"data": {
            key: secret["data"][key] for key in ("ca.pem", "tls.crt", "tls.key")}}}
        command(["-n", self.namespace, "exec", "-i", self.pod, "--", "python3", "-c", source],
                json.dumps(payload), timeout=30 + 15 * len(addresses))

    def public_probe(self, function, host, address):
        source = "import http.client, json, socket, ssl, sys\n" + inspect.getsource(function)
        source += "\npayload = json.load(sys.stdin)\nhttps_probe(payload['host'], payload['address'])\n"
        command(["-n", self.namespace, "exec", "-i", self.pod, "--", "python3", "-c", source],
                json.dumps({"host": host, "address": address}))

    def __exit__(self, exc_type, exc_value, traceback):
        try:
            command(["-n", self.namespace, "delete", "job", self.name, "--ignore-not-found", "--wait=false"])
        except (RuntimeError, subprocess.TimeoutExpired):
            # The Job deadline and TTL also clean up after runner loss.
            print("Peer validation job cleanup deferred to its deadline/TTL", flush=True)



class IPv6ProbeJobs:
    """Bounded, lazy host-network probes; never assume the CI runner has IPv6."""

    def __init__(self, namespace, kube, lifetime):
        self.namespace, self.kube, self.lifetime = namespace, kube, lifetime
        self.jobs = {}
        self.lock = threading.Lock()

    def __enter__(self):
        return self

    def job_for_address(self, address):
        with self.lock:
            if address not in self.jobs:
                nodes = self.kube(self.namespace, "nodes")["items"]
                node_name = next((node["metadata"]["name"] for node in nodes
                                  if any(a["type"] in ("ExternalIP", "InternalIP") and
                                         ipaddress.ip_address(a["address"]) == ipaddress.ip_address(address) for a in node.get("status", {}).get("addresses", []))), None)
                if not node_name:
                    raise RuntimeError(f"no ingress node owns IPv6 target {address}")
                job = PeerProbeJob(self.namespace, lifetime=self.lifetime, node_name=node_name)
                job.__enter__()
                self.jobs[address] = job
            job = self.jobs[address]
        return job

    def probe(self, function, host, address):
        self.job_for_address(address).public_probe(function, host, address)

    def peer_probe(self, function, host, address, secret):
        self.job_for_address(address).probe(function, host, {address}, secret)

    def __exit__(self, exc_type, exc_value, traceback):
        for job in self.jobs.values():
            job.__exit__(exc_type, exc_value, traceback)
