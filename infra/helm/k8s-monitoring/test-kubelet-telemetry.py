#!/usr/bin/env python3
"""Pass node and leader Leases through rendered Alloy to a local Prometheus."""

import functools
import http.server
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import threading
import time
import urllib.parse
import urllib.request

DIRECTORY = Path(__file__).resolve().parent


def block(text, prefix):
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.lstrip().startswith(prefix))
    indentation = lines[start][:len(lines[start]) - len(lines[start].lstrip())]
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == indentation + "}")
    return "\n".join(lines[start:end + 1])


def unused_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


with tempfile.TemporaryDirectory(prefix="kubelet-telemetry-") as temporary:
    temporary = Path(temporary)
    (temporary / "metrics").write_text('''
kube_node_labels{node="runner",label_node_cluster_x_k8s_io_pool="runners-linux"} 1
kube_lease_renew_time{namespace="kube-node-lease",lease="runner"} 123
kube_lease_renew_time{namespace="kube-system",lease="runner"} 456
kube_lease_owner{namespace="kube-node-lease",lease="runner"} 1
kube_secret_metadata_resource_version{namespace="default",secret="ignored"} 1
'''.lstrip())
    source = http.server.ThreadingHTTPServer(
        ("0.0.0.0", 0), functools.partial(QuietHandler, directory=str(temporary)))
    threading.Thread(target=source.serve_forever, daemon=True).start()
    try:
        for environment in ["staging", "canary", "production"]:
            rendered = subprocess.check_output([
                "helm", "template", "k8s-monitoring", str(DIRECTORY), "-n", "observability",
                "-f", str(DIRECTORY / f"values-{environment}.yaml"),
            ], text=True)
            manifests = json.loads(subprocess.check_output(
                ["yq", "ea", "-o=json", "[.]", "-"], input=rendered, text=True))
            deployment = next(item for item in manifests if item.get("kind") == "Deployment"
                              and item["metadata"]["name"].endswith("-kube-state-metrics"))
            args = deployment["spec"]["template"]["spec"]["containers"][0]["args"]
            assert any(arg.startswith("--resources=") and "leases" in arg.split("=", 1)[1].split(",")
                       for arg in args), "KSM must watch Leases"
            assert any(item.get("kind") == "ClusterRole" and any(
                "coordination.k8s.io" in rule.get("apiGroups", [])
                and "leases" in rule.get("resources", [])
                and {"list", "watch"} <= set(rule["verbs"])
                for rule in item.get("rules", [])) for item in manifests)
            config = next(item["data"]["config.alloy"] for item in manifests
                          if item.get("kind") == "ConfigMap"
                          and item["metadata"]["name"].endswith("-alloy-metrics"))
            for destination in ["grafana_cloud_metrics", "pulse_metrics"]:
                port = unused_port()
                writer = block(config, f'prometheus.remote_write "{destination}"')
                for prefix in ["headers = {", "basic_auth {", "tls_config {"]:
                    if prefix in writer:
                        writer = writer.replace(block(writer, prefix), "")
                native = os.environ.get("ALLOY_BINARY")
                host = "127.0.0.1" if native else "host.docker.internal"
                writer = re.sub(r'url = "[^"]+"', f'url = "http://{host}:{port}/api/v1/write"', writer)
                relabel = block(config, 'prometheus.relabel "kube_state_metrics"')
                relabel = relabel.replace("argument.metrics_destinations.value",
                                          f"[prometheus.remote_write.{destination}.receiver]")
                fixture = f'''
prometheus.scrape "fixture" {{
  targets = [{{"__address__" = "{host}:{source.server_address[1]}"}}]
  scrape_interval = "1s"
  scrape_timeout = "1s"
  forward_to = [prometheus.relabel.kube_state_metrics.receiver]
}}
'''
                local_config = "\n".join([writer, relabel, fixture])
                assert "remote.kubernetes" not in local_config and 'url = "https://' not in local_config
                (temporary / "config.alloy").write_text(local_config)
                (temporary / "prometheus.yml").write_text("scrape_configs: []\n")
                with (temporary / "prometheus.log").open("w") as prom_log, \
                        (temporary / "alloy.log").open("w") as alloy_log:
                    prometheus = subprocess.Popen([
                        os.environ.get("PROMETHEUS", "prometheus"),
                        f"--config.file={temporary}/prometheus.yml",
                        f"--storage.tsdb.path={temporary}/tsdb-{environment}-{destination}",
                        f"--web.listen-address=0.0.0.0:{port}", "--web.enable-remote-write-receiver",
                    ], stdout=prom_log, stderr=subprocess.STDOUT)
                    name = f"kubelet-telemetry-{os.getpid()}"
                    command = ([native] if native else [os.environ.get("DOCKER", "docker"),
                        "run", "--rm", "--name", name, "--add-host", "host.docker.internal:host-gateway",
                        "-v", f"{temporary}/config.alloy:/config.alloy:ro",
                        os.environ.get("ALLOY_IMAGE", "grafana/alloy:v1.15.0")])
                    alloy = None
                    try:
                        alloy = subprocess.Popen(command + ["run", "--disable-reporting",
                            f"--storage.path={temporary}/alloy-{environment}-{destination}" if native else "--storage.path=/tmp/alloy",
                            str(temporary / "config.alloy") if native else "/config.alloy",
                        ], stdout=alloy_log, stderr=subprocess.STDOUT)
                        expression = '{__name__=~"kube_.*"}'
                        url = f"http://127.0.0.1:{port}/api/v1/query?" + urllib.parse.urlencode({"query": expression})
                        deadline = time.monotonic() + 35
                        while True:
                            try:
                                with urllib.request.urlopen(url, timeout=2) as response:
                                    result = json.load(response)["data"]["result"]
                                if result:
                                    break
                            except OSError:
                                pass
                            assert alloy.poll() is None and time.monotonic() < deadline, "fixture never arrived"
                            time.sleep(0.5)
                        assert sorted(item["metric"]["__name__"] for item in result) == [
                            "kube_lease_renew_time", "kube_node_labels"], result
                        renewal = next(item for item in result if item["metric"]["__name__"] == "kube_lease_renew_time")
                        assert renewal["metric"]["namespace"] == "kube-node-lease" and renewal["metric"]["lease"] == "runner"
                        assert renewal["value"][1] == "123", renewal
                        assert all(item["metric"]["cluster"] == f"tuist-{environment}" for item in result)
                        assert all(not key.startswith("__tmp") for item in result for key in item["metric"])
                        print(f"PASS: {environment}/{destination} retains node inventory and node Lease only")
                    finally:
                        if alloy is not None:
                            if not native:
                                subprocess.run([os.environ.get("DOCKER", "docker"), "rm", "-f", name],
                                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            alloy.terminate()
                            alloy.wait(timeout=10)
                        prometheus.terminate()
                        prometheus.wait(timeout=10)
                        if alloy is None or alloy.returncode not in [0, -15, 143]:
                            print((temporary / "alloy.log").read_text())
    finally:
        source.shutdown()
        source.server_close()
