#!/usr/bin/env python3
"""Exercise rendered write relabeling with real Alloy and Prometheus engines."""

import functools
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import urllib.parse
import urllib.request

DIRECTORY = Path(__file__).resolve().parent
DOCKER = os.environ.get("DOCKER", "docker")
ALLOY_IMAGE = os.environ.get("ALLOY_IMAGE", "grafana/alloy:v1.15.0")
PROMETHEUS = shutil.which("prometheus")
assert PROMETHEUS, "prometheus must be available on PATH"


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


def query(port, expression):
    url = f"http://127.0.0.1:{port}/api/v1/query?" + urllib.parse.urlencode({"query": expression})
    with urllib.request.urlopen(url, timeout=2) as response:
        result = json.load(response)["data"]["result"]
    return float(result[0]["value"][1]) if result else 0


def fixture():
    lines = []
    for pod, routes, marker in [
        ("new", ["Read", "SplitBlob", "SpliceBlob"], ',latency_aggregate="true"'),
        ("old", ["Read", "SplitBlob"], ""),
    ]:
        for route in routes:
            labels = f'pod="{pod}",transport="grpc",route="/service/{route}"{marker}'
            for le, value in [("0.001", 1), ("0.002", 2), ("0.004", 3), ("4.096", 4), ("+Inf", 4)]:
                lines.append(f'kura_public_request_latency_seconds_bucket{{{labels},le="{le}"}} {value}')
            lines += [f'kura_public_request_latency_seconds_count{{{labels}}} 4',
                      f'kura_public_request_latency_seconds_sum{{{labels}}} 0.005']
    for transport in ["http", "grpc"]:
        labels = f'pod="new",transport="{transport}"'
        for le, value in [("0.001", 1), ("0.002", 2), ("0.004", 3), ("32.768", 4), ("+Inf", 4)]:
            lines.append(f'kura_public_request_latency_by_transport_seconds_bucket{{{labels},le="{le}"}} {value}')
        lines += [f'kura_public_request_latency_by_transport_seconds_count{{{labels}}} 4',
                  f'kura_public_request_latency_by_transport_seconds_sum{{{labels}}} 0.005']
    lines += ['kura_http_request_duration_seconds_bucket{pod="new",le="4.096"} 1',
              'kura_file_operation_duration_seconds_count{pod="new",operation="read"} 1',
              'kura_file_operations_total_total{pod="new",operation="read",result="ok"} 1']
    return "\n".join(lines) + "\n"


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def run(enabled):
    with tempfile.TemporaryDirectory(prefix="metric-cost-controls-") as temporary:
        temporary = Path(temporary)
        (temporary / "metrics").write_text(fixture())
        (temporary / "prometheus.yml").write_text("scrape_configs: []\n")
        port = unused_port()
        source = http.server.ThreadingHTTPServer(
            ("0.0.0.0", 0), functools.partial(QuietHandler, directory=str(temporary)))
        threading.Thread(target=source.serve_forever, daemon=True).start()
        source_port = source.server_address[1]
        rendered = subprocess.check_output([
            "helm", "template", "k8s-monitoring", str(DIRECTORY), "-n", "observability",
            "-f", str(DIRECTORY / "values-production.yaml"), "--set-string",
            "k8s-monitoring.destinations.grafana-cloud-metrics.extraLabels."
            f"kura_latency_aggregate_enabled={str(enabled).lower()}",
        ], text=True)
        manifests = json.loads(subprocess.check_output(
            ["yq", "ea", "-o=json", "[.]", "-"], input=rendered, text=True))
        config = next(item["data"]["config.alloy"] for item in manifests
                      if item.get("kind") == "ConfigMap"
                      and item["metadata"]["name"].endswith("-alloy-metrics"))
        writer = block(config, 'prometheus.remote_write "grafana_cloud_metrics"')
        for prefix in ["headers = {", "basic_auth {", "tls_config {"]:
            if prefix in writer:
                writer = writer.replace(block(writer, prefix), "")
        writer = re.sub(r'url = "[^"]+"',
                        f'url = "http://host.docker.internal:{port}/api/v1/write"', writer)
        assert "remote.kubernetes" not in writer and 'url = "https://' not in writer
        scrape = f'''
prometheus.scrape "fixture" {{
  targets = [{{"__address__" = "host.docker.internal:{source_port}"}}]
  scrape_interval = "1s"
  scrape_timeout = "1s"
  forward_to = [prometheus.remote_write.grafana_cloud_metrics.receiver]
}}
'''
        (temporary / "config.alloy").write_text(writer + scrape)
        with (temporary / "prometheus.log").open("w") as prom_log, \
                (temporary / "alloy.log").open("w") as alloy_log:
            prometheus = subprocess.Popen([
                PROMETHEUS, f"--config.file={temporary}/prometheus.yml",
                f"--storage.tsdb.path={temporary}/tsdb", f"--web.listen-address=0.0.0.0:{port}",
                "--web.enable-remote-write-receiver",
            ], stdout=prom_log, stderr=subprocess.STDOUT)
            name = f"metric-cost-controls-{os.getpid()}-{int(enabled)}"
            alloy = subprocess.Popen([
                DOCKER, "run", "--rm", "--name", name,
                "--add-host", "host.docker.internal:host-gateway",
                "-v", f"{temporary}/config.alloy:/config.alloy:ro", ALLOY_IMAGE,
                "run", "--disable-reporting", "--storage.path=/tmp/alloy", "/config.alloy",
            ], stdout=alloy_log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 35
                while True:
                    try:
                        if query(port, 'count(kura_file_operations_total_total)') == 1:
                            break
                    except (OSError, ValueError):
                        pass
                    if alloy.poll() is not None or time.monotonic() >= deadline:
                        raise AssertionError("fixture never reached remote-write receiver")
                    time.sleep(0.5)
                checks = {
                    'count(kura_public_request_latency_seconds_bucket{pod="old"})': 6,
                    'count(kura_public_request_latency_seconds_bucket{pod="new"})': 6 if enabled else 9,
                    'count(kura_public_request_latency_by_transport_seconds_bucket)': 6 if enabled else 0,
                    'count({__name__=~"kura_.*",kura_latency_aggregate_enabled=~".+"})': 0,
                    'count(kura_public_request_latency_by_transport_seconds_count)': 0,
                    'count(kura_public_request_latency_by_transport_seconds_sum)': 0,
                    'count(kura_file_operation_duration_seconds_count)': 0 if enabled else 1,
                    'count({__name__=~"kura_.*",le="0.002"})': 0,
                    'count({__name__=~"kura_public_request_latency.*",le=~"4.096|32.768"})': 0,
                    'count(kura_http_request_duration_seconds_bucket{le="4.096"})': 1,
                    'count({__name__=~"kura_.*",latency_aggregate=~".+"})': 6 if enabled else 0,
                    'count(kura_public_request_latency_seconds_bucket{latency_aggregate="true",route!~".*/(SplitBlob|SpliceBlob)"})': 0,
                    'count(kura_public_request_latency_seconds_count)': 5,
                    'count(kura_public_request_latency_seconds_sum)': 5,
                }
                stable_since = None
                while True:
                    actual = {expression: query(port, expression) for expression in checks}
                    if actual == checks:
                        if stable_since is None:
                            stable_since = time.monotonic()
                        # Observe across another batch deadline so zero-count
                        # checks cannot pass just because a later batch is pending.
                        if time.monotonic() - stable_since >= 6:
                            break
                    else:
                        stable_since = None
                    if time.monotonic() >= deadline:
                        raise AssertionError((enabled, checks, actual))
                    time.sleep(0.5)
                print(f"Rendered metric cost rules pass with migration enabled={enabled}")
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
                source.shutdown()


if __name__ == "__main__":
    if subprocess.run([DOCKER, "image", "inspect", ALLOY_IMAGE],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        subprocess.run([DOCKER, "pull", ALLOY_IMAGE], check=True)
    run(False)
    run(True)
