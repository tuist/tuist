#!/usr/bin/env python3
"""Keep Faro and Cloud delivery live while the rendered Greptime log sink is down."""

import concurrent.futures
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
import urllib.request

DIRECTORY = Path(__file__).resolve().parent
DOCKER = os.environ.get("DOCKER", "docker")
IMAGE = os.environ.get("ALLOY_IMAGE", "grafana/alloy:v1.15.0")


def unused_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def block(config, prefix):
    lines = config.splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith(prefix))
    indentation = lines[start][:len(lines[start]) - len(lines[start].lstrip())]
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == indentation + "}")
    return "\n".join(lines[start:end + 1])


class Backend(http.server.BaseHTTPRequestHandler):
    available = False
    failures = 0

    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        if self.path == "/greptimedb" and not type(self).available:
            type(self).failures += 1
            self.send_response(503)
        else:
            self.send_response(204)
        self.end_headers()

    def log_message(self, *_args):
        pass


with tempfile.TemporaryDirectory(prefix="log-destination-outage-") as temporary:
    temporary = Path(temporary)
    rendered = subprocess.check_output([
        "helm", "template", "k8s-monitoring", str(DIRECTORY), "-n", "observability",
        "-f", str(DIRECTORY / "values-production.yaml"),
    ], text=True)
    resources = json.loads(subprocess.check_output(
        ["yq", "ea", "-o=json", "[.]", "-"], input=rendered, text=True))
    config = next(item["data"]["config.alloy"] for item in resources
                  if item and item.get("kind") == "ConfigMap"
                  and item["metadata"]["name"].endswith("alloy-receiver"))
    # Execute the entire receiver graph, including the OTLP-to-Loki adapter.
    # Extracting only Faro and the writers misses invalid destination exports.
    # Replace external credentials and discovery, not the component wiring.
    config = re.sub(r'remote\.kubernetes\.secret "[^"]+" \{\n.*?\n\}', "", config, flags=re.S)
    config = re.sub(
        r'remote\.kubernetes\.secret\.\w+\.data\["([^"]+)"\]',
        lambda match: '""' if match[1] in ["ca", "cert", "key"] else '"fixture"', config)
    config = re.sub(
        r'kubernetes \{\s*service = "[^"]+"\s*\}',
        'static { hostnames = ["127.0.0.1:14317"] }', config)
    # Kubernetes enrichment is an external API boundary; keep its input and
    # outputs in the graph with a local passthrough processor.
    attributes = block(config, '  otelcol.processor.k8sattributes "default"')
    output = attributes[attributes.index("    output {"):]
    config = config.replace(attributes, '  otelcol.processor.batch "k8s_fixture" {\n' + output)
    config = config.replace("otelcol.processor.k8sattributes.default.input",
                            "otelcol.processor.batch.k8s_fixture.input")
    backend = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Backend)
    threading.Thread(target=backend.serve_forever, daemon=True).start()
    config = re.sub(r'url = "[^"]+"', f'url = "http://127.0.0.1:{backend.server_port}/cloud"', config)
    greptimedb = block(config, 'loki.write "pulse_logs"')
    config = config.replace(greptimedb, greptimedb.replace('/cloud"', '/greptimedb"'))
    ingest, admin, otlp = unused_port(), unused_port(), unused_port()
    config = re.sub(
        r'endpoint = "([^"]+)"',
        lambda match: f'endpoint = "http://127.0.0.1:{backend.server_port}"' if "://" in match[1]
        else f'endpoint = "127.0.0.1:{otlp if match[1] == "0.0.0.0:4318" else unused_port()}"',
        config)
    config = config.replace('"0.0.0.0"', '"127.0.0.1"')
    for port in [3100, 9009, 12347]:
        config = config.replace(f"listen_port = {port}", f"listen_port = {ingest if port == 12347 else unused_port()}")
    (temporary / "config.alloy").write_text(config)
    container = f"log-destination-outage-{os.getpid()}"
    binary = os.environ.get("ALLOY_BINARY")
    command = [binary] if binary else [
        DOCKER, "run", "--rm", "--name", container, "--network", "host",
        "--user", f"{os.getuid()}:{os.getgid()}",
        "-v", f"{temporary}:{temporary}", IMAGE,
    ]
    command += ["run", "--disable-reporting", f"--storage.path={temporary}/data",
                f"--server.http.listen-addr=127.0.0.1:{admin}", str(temporary / "config.alloy")]
    with (temporary / "alloy.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 30
            while True:
                try:
                    with socket.create_connection(("127.0.0.1", ingest), timeout=.1):
                        break
                except OSError:
                    assert process.poll() is None and time.monotonic() < deadline
                    time.sleep(.1)

            # Exceed the default 10 MiB endpoint queue, not just a healthy
            # client's in-memory buffer. Each batch contains 60 distinct logs.
            timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

            def send(batch):
                payload = json.dumps({"meta": {"app": {"name": "outage-fixture"}}, "logs": [
                    {"message": f"batch={batch} line={line} " + "x" * 16000,
                     "level": "info", "timestamp": timestamp} for line in range(60)]}).encode()
                request = urllib.request.Request(
                    f"http://127.0.0.1:{ingest}/collect", data=payload,
                    headers={"Content-Type": "application/json", "Origin": "https://tuist.dev"})
                with urllib.request.urlopen(request, timeout=2) as response:
                    assert response.status == 202, response.status

            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(send, range(30)))

            def delivered(destination):
                with urllib.request.urlopen(f"http://127.0.0.1:{admin}/metrics", timeout=2) as response:
                    metrics = response.read().decode()
                return sum(float(value) for labels, value in re.findall(
                    r"^loki_write_sent_entries_total\{([^\n]+)\} (\S+)$", metrics, re.M)
                           if f'component_id="loki.write.{destination}"' in labels)

            deadline = time.monotonic() + 15
            while delivered("grafana_cloud_logs") != 1800 or Backend.failures == 0:
                assert time.monotonic() < deadline, "Cloud stalled behind Greptime"
                time.sleep(.1)
            assert delivered("pulse_logs") == 0
            print("Greptime unavailable: 30/30 Faro POSTs accepted; all 1800 logs delivered to Cloud")

            Backend.available = True
            deadline = time.monotonic() + 30
            while delivered("pulse_logs") != 1800:
                assert time.monotonic() < deadline, "Greptime did not recover buffered logs"
                time.sleep(.1)
            print("Greptime recovered: all 1800 buffered logs delivered")

            payload = {"resourceLogs": [{
                "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "otlp-fixture"}}]},
                "scopeLogs": [{"logRecords": [{
                    "timeUnixNano": str(time.time_ns()),
                    "body": {"stringValue": "OTLP adapter regression"},
                    "severityText": "INFO",
                }]}],
            }]}
            request = urllib.request.Request(
                f"http://127.0.0.1:{otlp}/v1/logs", data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(request, timeout=2) as response:
                assert response.status == 200, response.status
            deadline = time.monotonic() + 30
            while delivered("grafana_cloud_logs") != 1801 or delivered("pulse_logs") != 1801:
                assert time.monotonic() < deadline, "OTLP log did not reach both destinations"
                time.sleep(.1)
            print("Full receiver graph: OTLP log delivered to both Cloud and Greptime")
        except BaseException:
            print((temporary / "alloy.log").read_text())
            raise
        finally:
            Backend.available = True
            if binary:
                process.terminate()
            else:
                subprocess.run([DOCKER, "rm", "-f", container], stdout=subprocess.DEVNULL, check=False)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            backend.shutdown()
