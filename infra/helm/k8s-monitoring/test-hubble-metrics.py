#!/usr/bin/env python3
"""Exercise rendered per-node Hubble discovery and retention with real Alloy."""

import http.server
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent
DOCKER = os.environ.get("DOCKER", "docker")
IMAGE = os.environ.get("ALLOY_IMAGE", "grafana/alloy:v1.15.0")
PROMETHEUS = shutil.which("prometheus")
assert PROMETHEUS, "prometheus must be available on PATH"


def block(text, prefix):
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.lstrip().startswith(prefix))
    indentation = lines[start][:len(lines[start]) - len(lines[start].lstrip())]
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == indentation + "}")
    return "\n".join(lines[start:end + 1])


def query(port, expression):
    url = f"http://127.0.0.1:{port}/api/v1/query?" + urllib.parse.urlencode({"query": expression})
    with urllib.request.urlopen(url, timeout=2) as response:
        result = json.load(response)["data"]["result"]
    return float(result[0]["value"][1]) if result else 0


class Fixture(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        path = urllib.parse.urlparse(self.path)
        if path.path.startswith("/api/"):
            kind = path.path.rsplit("/", 1)[-1]
            if kind not in ("pods", "services"):
                self.send_error(404)
                return
            items = self.server.resources[kind]
            namespace = re.search(r"/namespaces/([^/]+)/", path.path)
            if namespace:
                items = [item for item in items if item["metadata"]["namespace"] == namespace[1]]
            selector = urllib.parse.parse_qs(path.query).get("labelSelector", [""])[0]
            for requirement in filter(None, selector.split(",")):
                key, value = requirement.split("=", 1)
                items = [item for item in items if item["metadata"].get("labels", {}).get(key) == value]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            if urllib.parse.parse_qs(path.query).get("watch") == ["true"]:
                if urllib.parse.parse_qs(path.query).get("sendInitialEvents") == ["true"]:
                    for item in items:
                        self.wfile.write(json.dumps({"type": "ADDED", "object": item}).encode() + b"\n")
                    self.wfile.write(json.dumps({"type": "BOOKMARK", "object": {
                        "apiVersion": "v1", "kind": {"pods": "Pod", "services": "Service"}[kind],
                        "metadata": {"resourceVersion": "1", "annotations": {"k8s.io/initial-events-end": "true"}},
                    }}).encode() + b"\n")
                    self.wfile.flush()
                self.server.stopped.wait(50)
                return
            self.wfile.write(json.dumps({
                "apiVersion": "v1", "kind": {"pods": "PodList", "services": "ServiceList"}[kind],
                "metadata": {"resourceVersion": "1"}, "items": items,
            }).encode())
        elif self.server.failed:
            self.send_error(503)
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers()
            self.wfile.write(self.server.metrics.encode())


def server(metrics=""):
    instance = http.server.ThreadingHTTPServer(("0.0.0.0", 0), Fixture)
    instance.metrics = metrics
    instance.failed = False
    instance.stopped = threading.Event()
    threading.Thread(target=instance.serve_forever, daemon=True).start()
    return instance


def run():
    rendered = subprocess.check_output([
        "helm", "template", "k8s-monitoring", str(DIRECTORY), "-n", "observability",
        "-f", str(DIRECTORY / "values-production.yaml"),
    ], text=True)
    manifests = json.loads(subprocess.check_output(
        ["yq", "ea", "-o=json", "[.]", "-"], input=rendered, text=True))
    config = next(item["data"]["config.alloy"] for item in manifests
                  if item.get("kind") == "ConfigMap"
                  and item["metadata"]["name"].endswith("-alloy-metrics"))
    parts = [block(config, prefix) for prefix in [
        'discovery.kubernetes "tuist_hubble"',
        'discovery.relabel "tuist_hubble"',
        'prometheus.scrape "tuist_hubble"',
        'prometheus.relabel "tuist_hubble"',
        'discovery.kubernetes "services"',
        'discovery.relabel "annotation_autodiscovery_services"',
    ]]
    assert 'enabled = true' in block(parts[2], 'clustering {')
    assert 'role = "pod"' in parts[0] and '"kube-system"' in parts[0]

    if subprocess.run([DOCKER, "image", "inspect", IMAGE],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False).returncode:
        subprocess.run([DOCKER, "pull", IMAGE], check=True)
    # Use a real address reachable from Docker on both Linux and Docker Desktop.
    host = subprocess.check_output([
        DOCKER, "run", "--rm", "--add-host", "host.docker.internal:host-gateway",
        "--entrypoint", "/bin/sh", IMAGE, "-c", "getent ahostsv4 host.docker.internal | head -1",
    ], text=True).split()[0]
    fixtures = []
    for value in [7, 19]:
        fixtures.append(server(
            '# TYPE hubble_drop_total counter\n'
            f'hubble_drop_total{{protocol="TCP",reason="POLICY_DENIED",source="192.0.2.1",destination="example/cache"}} {value}\n'
            'hubble_flows_processed_total 101\nhubble_tcp_flags_total 102\n'
            'hubble_dns_queries_total 103\nhubble_http_requests_total 104\n'))
    control = server('fixture_control_total 1\n')
    api = server()
    fixtures += [control, api]
    ports = [fixture.server_port for fixture in fixtures]
    pods = []
    for name, node, port, phase, ready, namespace, app in [
        ("agent-a", "node-a", ports[0], "Running", "True", "kube-system", "cilium"),
        ("agent-b", "node-b", ports[1], "Running", "False", "kube-system", "cilium"),
        ("pending", "node-c", ports[2], "Pending", "False", "kube-system", "cilium"),
        ("other", "node-d", ports[2], "Running", "True", "kube-system", "other"),
        ("elsewhere", "node-e", ports[2], "Running", "True", "example", "cilium"),
    ]:
        pods.append({
            "apiVersion": "v1", "kind": "Pod",
            "metadata": {"name": name, "namespace": namespace, "uid": name,
                         "resourceVersion": "1", "labels": {"k8s-app": app}},
            "spec": {"nodeName": node, "containers": [{
                "name": "cilium-agent", "ports": [
                    {"name": "prometheus", "containerPort": ports[2], "protocol": "TCP"},
                    {"name": "hubble-metrics", "containerPort": port, "protocol": "TCP"},
                ],
            }]},
            "status": {"phase": phase, "podIP": host,
                       "conditions": [{"type": "Ready", "status": ready}]},
        })
    services = [{
        "apiVersion": "v1", "kind": "Service",
        "metadata": {"name": "hubble-metrics", "namespace": namespace,
                     "uid": namespace, "resourceVersion": "1",
                     "annotations": {"prometheus.io/scrape": "true", "prometheus.io/port": str(ports[2])},
                     "labels": {"app.kubernetes.io/name": job}},
        "spec": {"type": "ClusterIP", "clusterIP": "None",
                 "ports": [{"name": "metrics", "port": ports[2], "protocol": "TCP"}]},
    } for namespace, job in [("kube-system", "hubble"), ("example", "control")]]
    api.resources = {"pods": pods, "services": services}

    with tempfile.TemporaryDirectory(prefix="hubble-metrics-") as temporary:
        temporary = Path(temporary)
        (temporary / "prometheus.yml").write_text("scrape_configs: []\n")
        receiver = server()
        port = receiver.server_port
        receiver.shutdown()
        receiver.server_close()
        writer = block(config, 'prometheus.remote_write "grafana_cloud_metrics"')
        for prefix in ["headers = {", "basic_auth {", "tls_config {"]:
            if prefix in writer:
                writer = writer.replace(block(writer, prefix), "")
        writer = re.sub(r'url = "[^"]+"',
                        f'url = "http://host.docker.internal:{port}/api/v1/write"', writer)
        for index in [0, 4]:
            parts[index] = parts[index].replace(
                'role = ', f'api_server = "http://host.docker.internal:{api.server_port}"\n    role = ', 1)
        # Accelerate only scrape timing, including the annotation defaults.
        for index in [2, 5]:
            parts[index] = parts[index].replace('"60s"', '"1s"').replace('"10s"', '"1s"')
        pipeline = writer + "\n" + "\n".join(parts) + '''
prometheus.scrape "service_control" {
  targets = discovery.relabel.annotation_autodiscovery_services.output
  scrape_interval = "1s"
  scrape_timeout = "1s"
  forward_to = [prometheus.remote_write.grafana_cloud_metrics.receiver]
}
'''
        assert "remote.kubernetes" not in pipeline and 'url = "https://' not in pipeline
        (temporary / "config.alloy").write_text(pipeline)
        name = f"hubble-metrics-{os.getpid()}"
        with (temporary / "prometheus.log").open("w") as prom_log, \
                (temporary / "alloy.log").open("w") as alloy_log:
            prometheus = subprocess.Popen([
                PROMETHEUS, f"--config.file={temporary}/prometheus.yml",
                f"--storage.tsdb.path={temporary}/tsdb", f"--web.listen-address=0.0.0.0:{port}",
                "--web.enable-remote-write-receiver",
            ], stdout=prom_log, stderr=subprocess.STDOUT)
            alloy = subprocess.Popen([
                DOCKER, "run", "--rm", "--name", name,
                "--add-host", "host.docker.internal:host-gateway",
                "--add-host", "hubble-metrics.kube-system.svc:host-gateway",
                "--add-host", "hubble-metrics.example.svc:host-gateway",
                "-v", f"{temporary}/config.alloy:/config.alloy:ro", IMAGE,
                "run", "--disable-reporting", "--cluster.enabled",
                "--storage.path=/tmp/alloy", "/config.alloy",
            ], stdout=alloy_log, stderr=subprocess.STDOUT)
            try:
                checks = {
                    'count(up{job="hubble"})': 2,
                    'sum(up{job="hubble",node="node-a",instance="node-a",namespace="kube-system",pod="agent-a"})': 1,
                    'sum(up{job="hubble",node="node-b",instance="node-b",namespace="kube-system",pod="agent-b"})': 1,
                    'count(hubble_drop_total{job="hubble"})': 2,
                    'sum(hubble_drop_total{node="node-a",protocol="TCP",reason="POLICY_DENIED",source="192.0.2.1",destination="example/cache"})': 7,
                    'sum(hubble_drop_total{node="node-b",protocol="TCP"})': 19,
                    'count(scrape_samples_scraped{job="hubble"})': 2,
                    'sum(scrape_samples_scraped{job="hubble",node="node-a",instance="node-a",namespace="kube-system",pod="agent-a"})': 5,
                    'sum(scrape_samples_scraped{job="hubble",node="node-b",instance="node-b",namespace="kube-system",pod="agent-b"})': 5,
                    'count({job="hubble",__name__!~"hubble_drop_total|up|scrape_samples_scraped"})': 0,
                    'count(up{job="control"})': 1,
                    'sum(up{job="control"})': 1,
                }
                for failed in [False, True]:
                    fixtures[1].failed = failed
                    checks['sum(up{job="hubble",node="node-b",instance="node-b",namespace="kube-system",pod="agent-b"})'] = 0 if failed else 1
                    checks['count(hubble_drop_total{job="hubble"})'] = 1 if failed else 2
                    checks['sum(hubble_drop_total{node="node-b",protocol="TCP"})'] = 0 if failed else 19
                    checks['sum(scrape_samples_scraped{job="hubble",node="node-b",instance="node-b",namespace="kube-system",pod="agent-b"})'] = 0 if failed else 5
                    deadline = time.monotonic() + 45
                    stable_since = None
                    while True:
                        try:
                            actual = {expression: query(port, expression) for expression in checks}
                        except (OSError, ValueError):
                            actual = {}
                        if actual == checks:
                            if stable_since is None:
                                stable_since = time.monotonic()
                            if time.monotonic() - stable_since >= 6:
                                break
                        else:
                            stable_since = None
                        if alloy.poll() is not None or time.monotonic() >= deadline:
                            raise AssertionError((failed, checks, actual))
                        time.sleep(0.5)
                    print(f"Hubble per-node discovery, attribution, health and retention pass: failed={failed}")
            except Exception:
                print((temporary / "alloy.log").read_text())
                print((temporary / "prometheus.log").read_text())
                raise
            finally:
                subprocess.run([DOCKER, "rm", "-f", name], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, check=False)
                alloy.wait(timeout=15)
                prometheus.terminate()
                prometheus.wait(timeout=15)
                for fixture in fixtures:
                    fixture.stopped.set()
                    fixture.shutdown()
                    fixture.server_close()


if __name__ == "__main__":
    run()
