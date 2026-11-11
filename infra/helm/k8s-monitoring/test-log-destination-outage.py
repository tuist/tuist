#!/usr/bin/env python3
"""Keep Faro and Cloud delivery live while the rendered Pulse log sink is down."""

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
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return "\n".join(lines[start:end + 1])


class Backend(http.server.BaseHTTPRequestHandler):
    available = False
    failures = 0

    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        if self.path == "/pulse" and not type(self).available:
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
    pulse = block(config, 'loki.write "pulse_logs"')
    # Retain the shipped writer, WAL, retry policy and labels; replace only the
    # network/credential boundary with a disposable unauthenticated backend.
    pulse = re.sub(r"(?m)^\s*tenant_id = .*\n", "\n", pulse)
    pulse = re.sub(r"(?ms)^\s*basic_auth \{.*?^\s*\}", "", pulse)
    pulse = re.sub(r"(?ms)^\s*tls_config \{.*?^\s*\}", "", pulse)
    backend = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Backend)
    threading.Thread(target=backend.serve_forever, daemon=True).start()
    pulse = pulse.replace(
        "http://pulse.observability.svc.cluster.local:4000/loki/api/v1/push",
        f"http://127.0.0.1:{backend.server_port}/pulse")
    ingest, admin = unused_port(), unused_port()
    faro = block(config, 'faro.receiver "tuist_web"').replace('"0.0.0.0"', '"127.0.0.1"')
    faro = faro.replace("12347", str(ingest))
    (temporary / "config.alloy").write_text(faro + "\n" + pulse + f'''
loki.write "grafana_cloud_logs" {{
  endpoint {{
    url = "http://127.0.0.1:{backend.server_port}/cloud"
    batch_wait = "100ms"
  }}
}}
''')
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
                assert time.monotonic() < deadline, "Cloud stalled behind Pulse"
                time.sleep(.1)
            assert delivered("pulse_logs") == 0
            print("Pulse unavailable: 30/30 Faro POSTs accepted; all 1800 logs delivered to Cloud")

            Backend.available = True
            deadline = time.monotonic() + 30
            while delivered("pulse_logs") != 1800:
                assert time.monotonic() < deadline, "Pulse did not recover buffered logs"
                time.sleep(.1)
            print("Pulse recovered: all 1800 buffered logs delivered")
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
