#!/usr/bin/env python3
"""Render or run an isolated, bounded staging gateway comparison."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import random
import subprocess
import threading
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def command(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Command failed: {args}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["render", "run"])
    parser.add_argument("--context", required=True)
    parser.add_argument("--node-a", required=True)
    parser.add_argument("--node-b", required=True)
    parser.add_argument("--client-node", required=True)
    parser.add_argument("--image", required=True, help="Pinned staging Kura image")
    parser.add_argument("--output", required=True)
    parser.add_argument("--binary", required=True, help="Linux amd64 benchmark client")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--backend", choices=["a", "b"], default="a", help="Swap to b for the reciprocal comparison")
    parser.add_argument("--profile", choices=["burst", "sustained"], default="burst")
    args = parser.parse_args()
    if "staging" not in args.context or len({args.node_a, args.node_b, args.client_node}) != 3:
        parser.error("requires an explicit staging context and three distinct nodes")
    if not 1 <= args.rounds <= 5:
        parser.error("rounds must be between one and five")
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    run_id_file = out / "run-id.txt"
    if run_id_file.exists():
        run_id = run_id_file.read_text().strip()
    else:
        run_id = "kura-hop-" + time.strftime("%Y%m%d%H%M%S", time.gmtime())
        run_id_file.write_text(run_id)
    if not re.fullmatch(r"kura-hop-[0-9]{14}", run_id):
        parser.error("invalid run ID")
    labels = {"tuist.dev/gateway-benchmark": run_id}
    selector = f"tuist.dev/gateway-benchmark={run_id}"
    kubectl = ["kubectl", "--context", args.context, "--request-timeout=30s", "-n", "kura"]

    def k(*items, **kwargs):
        return command(kubectl + list(items), **kwargs)

    def meta(suffix):
        return {"name": f"{run_id}-{suffix}", "namespace": "kura", "labels": labels}

    if not (out / "tls.crt").exists():
        command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
                 "-keyout", str(out / "tls.key"), "-out", str(out / "tls.crt"),
                 "-subj", "/CN=*.benchmark.test", "-addext", "subjectAltName=DNS:*.benchmark.test"])
        os.chmod(out / "tls.key", 0o600)

    def resource(kind, suffix, **fields):
        return {"apiVersion": "v1", "kind": kind, "metadata": meta(suffix), **fields}

    resources = [resource("Secret", "tls", type="kubernetes.io/tls", data={
        "tls.crt": base64.b64encode((out / "tls.crt").read_bytes()).decode(),
        "tls.key": base64.b64encode((out / "tls.key").read_bytes()).decode()})]
    # Read the window settings from the same production chart used by the
    # existing flow-control benchmark rather than testing nginx defaults.
    chart = (ROOT / "infra/helm/platform/values.yaml").read_text()
    windows = {}
    for key in ("client-body-buffer-size", "http2-max-concurrent-streams"):
        match = re.search(rf'^\s+{key}:\s*["\']?([0-9]+[kKmMgG]?)', chart, re.M)
        if not match:
            raise ValueError(f"missing chart setting {key}")
        windows[key.replace("-", "_")] = match.group(1)
    preread = re.search(r"http2_body_preread_size\s+([0-9]+[kKmMgG]?);", chart)
    if not preread:
        raise ValueError("missing chart HTTP/2 preread setting")
    windows["http2_body_preread_size"] = preread.group(1)
    config = "worker_processes 2;\nevents { worker_connections 4096; }\nhttp {\naccess_log off;\n"
    if args.profile == "sustained":
        # Keep each bounded case on a warmed connection. Connection recycling
        # is a separate reliability experiment, not the node-hop comparison.
        config += "keepalive_requests 10000;\n"
    config += "error_log /dev/stderr warn;\n" + "\n".join(f"{key} {value};" for key, value in windows.items())
    config += "\nserver { listen 8443 ssl default_server; ssl_reject_handshake on; }\n"
    for name in ("a", "b"):
        upstream = f"{run_id}-backend-{name}.kura.svc.cluster.local:4000"
        config += f"""
upstream backend_http_{name} {{
    server {upstream};
    keepalive 16;
    keepalive_requests 10000;
    keepalive_timeout 10s;
}}
upstream backend_grpc_{name} {{
    server {upstream};
    keepalive 16;
    keepalive_requests 10000;
    keepalive_timeout 10s;
}}
server {{
    listen 8443 ssl;
    http2 on;
    server_name {name}.benchmark.test;
    ssl_certificate /tls/tls.crt;
    ssl_certificate_key /tls/tls.key;
    client_max_body_size 0;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_max_temp_file_size 0;
    location ~ ^/(google\\.bytestream\\.|build\\.bazel\\.) {{
        grpc_pass grpc://backend_grpc_{name};
        grpc_read_timeout 60s;
        grpc_send_timeout 60s;
    }}
    location / {{
        proxy_pass http://backend_http_{name};
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_read_timeout 60s;
    }}
}}
"""
    config += "}\n"
    resources.append(resource("ConfigMap", "nginx", data={"nginx.conf": config}))

    def pod(suffix, node, containers, volumes):
        pod_labels = dict(labels, **{"benchmark-role": suffix})
        item = resource("Pod", suffix, spec={
            "nodeSelector": {"kubernetes.io/hostname": node},
            "tolerations": [{"key": "tuist.dev/kura-cache", "operator": "Exists", "effect": "NoSchedule"}]
                + ([{"key": "tuist.dev/stateful", "value": "clickhouse", "effect": "NoSchedule"}] if suffix == "client" else []),
            "automountServiceAccountToken": False,
            "activeDeadlineSeconds": 3600, "restartPolicy": "Never", "terminationGracePeriodSeconds": 10,
            "containers": containers, "volumes": volumes})
        item["metadata"]["labels"] = pod_labels
        resources.append(item)

    for name, node in (("a", args.node_a), ("b", args.node_b)):
        suffix = f"backend-{name}"
        resources.append(resource("Service", suffix, spec={
            "selector": dict(labels, **{"benchmark-role": suffix}),
            "ports": [{"name": "http", "port": 4000, "targetPort": 4000}]}))
        env = {"KURA_PORT": "4000", "KURA_INTERNAL_PORT": "7443", "KURA_TENANT_ID": f"benchmark-{name}",
               "KURA_REGION": "staging-benchmark", "KURA_TMP_DIR": "/data/tmp", "KURA_DATA_DIR": "/data",
               "KURA_NODE_URL": f"http://{run_id}-{suffix}:7443", "KURA_OTEL_SERVICE_NAME": "kura-benchmark",
               "KURA_OTEL_DEPLOYMENT_ENVIRONMENT": "benchmark", "KURA_AUTH_ENABLED": "false", "RUST_LOG": "warn"}
        pod(suffix, node, [{"name": "kura", "image": args.image,
            "env": [{"name": key, "value": value} for key, value in env.items()],
            "resources": {"requests": {"cpu": "500m", "memory": "512Mi", "ephemeral-storage": "4Gi"},
                          "limits": {"cpu": "2", "memory": "2Gi"}},
            "volumeMounts": [{"name": "data", "mountPath": "/data"}],
            "readinessProbe": {"httpGet": {"path": "/up", "port": 4000}, "periodSeconds": 2}}],
            [{"name": "data", "emptyDir": {"sizeLimit": "4Gi"}}])
        pod(f"gateway-{name}", node, [{"name": "nginx", "image": "nginx:1.27.3-alpine",
            "resources": {"requests": {"cpu": "100m", "memory": "64Mi"}, "limits": {"cpu": "2", "memory": "256Mi"}},
            "volumeMounts": [{"name": "config", "mountPath": "/etc/nginx/nginx.conf", "subPath": "nginx.conf"},
                             {"name": "tls", "mountPath": "/tls", "readOnly": True}],
            "readinessProbe": {"tcpSocket": {"port": 8443}, "periodSeconds": 2}}],
            [{"name": "config", "configMap": {"name": f"{run_id}-nginx"}},
             {"name": "tls", "secret": {"secretName": f"{run_id}-tls"}}])
    pod("client", args.client_node, [{"name": "client", "image": "debian:bookworm-slim",
        "command": ["sleep", "3600"],
        "resources": {"requests": {"cpu": "500m", "memory": "256Mi"}, "limits": {"cpu": "2", "memory": "1Gi"}},
        "volumeMounts": [{"name": "tls", "mountPath": "/tls", "readOnly": True}]}],
        [{"name": "tls", "secret": {"secretName": f"{run_id}-tls", "items": [{"key": "tls.crt", "path": "tls.crt"}]}}])
    resources.insert(0, {"apiVersion": "networking.k8s.io/v1", "kind": "NetworkPolicy", "metadata": meta("isolation"),
        "spec": {"podSelector": {"matchLabels": labels}, "policyTypes": ["Ingress", "Egress"],
                 "ingress": [{"from": [{"podSelector": {"matchLabels": labels}}]}],
                 "egress": [{"to": [{"podSelector": {"matchLabels": labels}}]},
                            {"ports": [{"port": 53, "protocol": "UDP"}, {"port": 53, "protocol": "TCP"}]}]}})
    manifest = out / "resources.json"
    manifest.write_text(json.dumps({"apiVersion": "v1", "kind": "List", "items": resources}, indent=2))
    os.chmod(manifest, 0o600)
    (out / "nginx.conf").write_text(config)
    if args.mode == "render":
        print(f"Rendered {len(resources)} isolated staging resources: {manifest}")
        return
    if json.loads(k("get", "pods", "-l", selector, "-o", "json"))["items"]:
        raise RuntimeError("benchmark resources already exist; inspect and clean up this run before reusing it")
    stop = threading.Event()
    telemetry = []

    def collect():
        while not stop.is_set():
            try:
                metrics = json.loads(k("get", "--raw", "/apis/metrics.k8s.io/v1beta1/namespaces/kura/pods"))
                telemetry.append({"at": time.time(), "items": [p for p in metrics["items"] if p["metadata"]["name"].startswith(run_id)]})
            except RuntimeError as exc:
                telemetry.append({"at": time.time(), "error": str(exc)})
            stop.wait(10)

    monitor = None

    def capture_cgroups(stage):
        snapshots = {}
        for suffix in ("backend-a", "backend-b", "gateway-a", "gateway-b", "client"):
            try:
                snapshots[suffix] = k("exec", f"{run_id}-{suffix}", "--", "cat", "/sys/fs/cgroup/cpu.stat",
                                      "/sys/fs/cgroup/memory.current", "/sys/fs/cgroup/memory.peak")
            except RuntimeError as exc:
                snapshots[suffix] = str(exc)
        (out / f"cgroups-{stage}.json").write_text(json.dumps(snapshots, indent=2))

    def counters(suffix):
        raw = k("exec", f"{run_id}-{suffix}", "--", "cat", "/proc/net/snmp", "/proc/net/netstat", "/sys/fs/cgroup/cpu.stat")
        lines = raw.splitlines()
        values = {"sampled_at": time.time()}
        for index, line in enumerate(lines):
            fields = line.split()
            if len(fields) == 2 and fields[0] in ["usage_usec", "user_usec", "system_usec", "nr_periods", "nr_throttled", "throttled_usec"]:
                values[fields[0]] = int(fields[1])
            if fields and fields[0] in ["Tcp:", "TcpExt:"] and len(fields) > 1 and not fields[1].isdigit():
                numbers = lines[index+1].split()[1:]
                for key, number in zip(fields[1:], numbers):
                    if fields[0] == "Tcp:" or any(word in key for word in ["Retrans", "Timeout", "ZeroWindow", "Drop", "Backlog", "Recovery"]):
                        values[fields[0][:-1]+"."+key] = int(number)
        return values

    def reset_backend():
        suffix = f"backend-{args.backend}"
        replacement = next(r for r in resources if r["kind"] == "Pod" and r["metadata"]["name"] == f"{run_id}-{suffix}")
        k("delete", "pod", f"{run_id}-{suffix}", "--wait=true", "--timeout=60s")
        k("apply", "-f", "-", input=json.dumps(replacement))
        k("wait", "pod", f"{run_id}-{suffix}", "--for=condition=Ready", "--timeout=120s")

    try:
        print(k("apply", "-f", str(manifest)), flush=True)
        print(k("wait", "pod", "-l", selector, "--for=condition=Ready", "--timeout=180s"), flush=True)
        pod_data = json.loads(k("get", "pods", "-l", selector, "-o", "json"))
        (out / "pods.json").write_text(json.dumps(pod_data, indent=2))
        ips = {p["metadata"]["name"].removeprefix(run_id+"-"): p["status"]["podIP"] for p in pod_data["items"]}
        k("cp", args.binary, f"{run_id}-client:/tmp/benchmark")
        capture_cgroups("before")
        routing_result = k("exec", f"{run_id}-client", "--", "/tmp/benchmark",
                           "-address", ips["gateway-a"]+":8443", "-routing-addresses",
                           ips["gateway-a"]+":8443,"+ips["gateway-b"]+":8443")
        (out / "routing-check.json").write_text(routing_result)
        print(routing_result, flush=True)
        monitor = threading.Thread(target=collect); monitor.start()
        cases = [("read", 4096, 200, 1), ("read", 262144, 64, 8), ("write", 262144, 64, 8),
                 ("read", 8388608, 16, 4), ("write", 8388608, 16, 4)]
        if args.profile == "sustained":
            cases = [("read", 4096, 2000, 1), ("read", 262144, 4096, 8),
                     ("write", 262144, 4096, 8), ("read", 8388608, 64, 4)]
        rng = random.Random(20260910 + (args.backend == "b"))
        (out / "parameters.json").write_text(json.dumps(vars(args), indent=2))
        with (out / "results.jsonl").open("w") as result_file:
            for round_no in range(args.rounds):
                for protocol in ("grpc", "http2"):
                    ordered_cases = list(cases)
                    if args.profile == "sustained":
                        rng.shuffle(ordered_cases)
                    for operation, size, count, concurrency in ordered_cases:
                        first_local = (round_no + cases.index((operation, size, count, concurrency)) + (args.backend == "b")) % 2 == 0
                        for path in (["local", "remote"] if first_local else ["remote", "local"]):
                            gateway = args.backend if path == "local" else ("b" if args.backend == "a" else "a")
                            if args.profile == "sustained" and operation == "write":
                                reset_backend()
                            counter_roles = [f"gateway-{gateway}", f"backend-{args.backend}"]
                            before = {role: counters(role) for role in counter_roles} if args.profile == "sustained" else {}
                            began = time.time()
                            extra = ["-warmup-requests", "128", "-stream-fixtures"] if args.profile == "sustained" else []
                            output = k("exec", f"{run_id}-client", "--", "/tmp/benchmark",
                                "-address", ips[f"gateway-{gateway}"]+":8443", "-label", path,
                                "-host", args.backend+".benchmark.test",
                                "-protocol", protocol, "-operation", operation, "-size", str(size),
                                "-count", str(count), "-concurrency", str(concurrency), *extra)
                            ended = time.time()
                            after = {role: counters(role) for role in counter_roles} if args.profile == "sustained" else {}
                            row = dict(json.loads(output), backend=args.backend, profile=args.profile, round=round_no+1, started_at=began, ended_at=ended,
                                       server_counters_before=before, server_counters_after=after)
                            result_file.write(json.dumps(row)+"\n"); result_file.flush()
                            print(json.dumps({key: value for key, value in row.items() if not key.startswith("diagnostics_") and not key.startswith("server_counters_")}), flush=True)
            # Prove the second hostname is served by both gateway placements.
            for gateway in ("a", "b"):
                print(k("exec", f"{run_id}-client", "--", "/tmp/benchmark", "-address", ips[f"gateway-{gateway}"]+":8443",
                        "-host", "b.benchmark.test", "-count", "4", "-label", "account-b-smoke"), flush=True)
    finally:
        stop.set()
        if monitor:
            monitor.join(timeout=40)
        try:
            capture_cgroups("after")
            (out / "metrics.json").write_text(json.dumps(telemetry, indent=2))
            (out / "final-pods.json").write_text(k("get", "pods", "-l", selector, "-o", "json"))
            for suffix in ("backend-a", "backend-b", "gateway-a", "gateway-b"):
                try:
                    (out / f"{suffix}.log").write_text(k("logs", f"{run_id}-{suffix}", "--tail=100"))
                except RuntimeError:
                    pass
        finally:
            print(k("delete", "pods,services,configmaps,secrets,networkpolicies", "-l", selector, "--wait=true", "--timeout=60s"), flush=True)


if __name__ == "__main__":
    main()
