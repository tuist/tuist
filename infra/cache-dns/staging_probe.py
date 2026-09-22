#!/usr/bin/env python3
"""Staging-only HTTPS and REAPI probes. Emit JSONL evidence; never print tokens."""

import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.parse


def record(event, **fields):
    print(json.dumps({"at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      "event": event, **fields}), flush=True)


def request(args, token, method, path, payload=None, ip=None, host=None):
    host = host or args.host
    with tempfile.TemporaryDirectory(prefix="spec95-http-") as directory:
        output = Path(directory) / "response"
        command = [args.curl, "--silent", "--show-error", "--max-time", "20",
                   "--connect-timeout", "5", "--noproxy", "*", "--config", "-",
                   "--request", method, "--output", str(output),
                   "--write-out", "%{http_code} %{remote_ip} %{time_total}"]
        if ip:
            command += ["--resolve", f"{host}:443:{ip}"]
        if payload is not None:
            upload = Path(directory) / "upload"
            upload.write_bytes(payload)
            command += ["--data-binary", "@" + str(upload)]
        command += ["https://" + host + path]
        config = f'header = "Authorization: Bearer {token}"\n' if token else ""
        result = subprocess.run(command, input=config, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stderr.replace(token, "[redacted]") if token else result.stderr)
        status, remote_ip, elapsed = result.stdout.split()
        record("http", method=method, host=host, pinned_ip=ip,
               remote_ip=remote_ip, status=int(status), seconds=float(elapsed))
        return int(status), output.read_bytes()


def grpc(args, token, method, body, ip=None, host=None):
    host = host or args.host
    proto = Path(__file__).with_name("reapi-smoke.proto")
    command = [args.grpcurl, "-max-time", "20", "-authority", host,
               "-import-path", str(proto.parent), "-proto", proto.name,
               "-expand-headers", "-H", "authorization: Bearer ${SPEC95_PROBE_TOKEN}",
               "-d", "@", (ip or host) + ":443",
               "build.bazel.remote.execution.v2.ContentAddressableStorage/" + method]
    started = time.monotonic()
    result = subprocess.run(command, input=json.dumps(body), text=True, capture_output=True,
                            env={**os.environ, "SPEC95_PROBE_TOKEN": token})
    if result.returncode:
        raise RuntimeError(result.stderr.replace(token, "[redacted]"))
    response = json.loads(result.stdout)
    entries = response.get("responses", [])
    if len(entries) != 1:
        raise RuntimeError("REAPI did not return exactly one blob result")
    entry = entries[0]
    code = int(entry.get("status", {}).get("code", 0))
    record("grpc", method=method, host=host, pinned_ip=ip, status=code,
           seconds=time.monotonic() - started)
    return code, entry


def roundtrip(args, token):
    payload = os.urandom(64 * 1024)
    digest = {"hash": hashlib.sha256(payload).hexdigest(), "sizeBytes": str(len(payload))}
    query = urllib.parse.urlencode({"tenant_id": args.account, "namespace_id": args.project})
    path = f'/api/cache/gradle/{digest["hash"]}?{query}'
    status, _ = request(args, token, "PUT", path, payload, args.write_ip)
    if status not in (200, 201):
        raise RuntimeError(f"HTTP upload failed: {status}")
    deadline = time.monotonic() + args.replication_timeout
    while True:
        status, actual = request(args, token, "GET", path, ip=args.read_ip, host=args.read_host)
        if status == 200:
            if actual != payload:
                raise RuntimeError("HTTP artifact contents differ")
            break
        if status != 404 or time.monotonic() >= deadline:
            raise RuntimeError(f"HTTP download failed: {status}")
        time.sleep(1)
    code, entry = grpc(args, token, "BatchUpdateBlobs", {
        "instanceName": args.project,
        "requests": [{"digest": digest, "data": base64.b64encode(payload).decode()}],
    }, args.write_ip)
    if code != 0 or entry.get("digest") != digest:
        raise RuntimeError("REAPI upload failed or returned a different digest")
    deadline = time.monotonic() + args.replication_timeout
    while True:
        code, entry = grpc(args, token, "BatchReadBlobs", {
            "instanceName": args.project, "digests": [digest],
        }, args.read_ip, args.read_host)
        if code == 0:
            if entry.get("digest") != digest or base64.b64decode(entry.get("data", "")) != payload:
                raise RuntimeError("REAPI artifact contents differ")
            break
        if code != 5 or time.monotonic() >= deadline:
            raise RuntimeError(f"REAPI download failed: {code}")
        time.sleep(1)
    record("roundtrip_passed", sha256=digest["hash"], bytes=len(payload))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["ready", "roundtrip"])
    parser.add_argument("--host", required=True)
    parser.add_argument("--account", required=True)
    parser.add_argument("--project", default="probe")
    parser.add_argument("--token-file", type=Path)
    parser.add_argument("--write-ip", help="Pin upload/ready to a box; preserve hostname and TLS verification")
    parser.add_argument("--read-ip", help="Pin reads to a second box to validate cross-region replication")
    parser.add_argument("--read-host", help="Use a different staging hostname for regional baseline reads")
    parser.add_argument("--replication-timeout", type=int, default=60)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--interval", type=float, default=5)
    parser.add_argument("--curl", default="curl")
    parser.add_argument("--grpcurl", default="grpcurl")
    args = parser.parse_args()
    for host in (args.host, args.read_host or args.host):
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*-staging\.(cache|kura)\.tuist\.dev", host):
            parser.error("only staging cache/kura hostnames are allowed")
        if not host.startswith(args.account + "-"):
            parser.error("hostname must belong to the supplied test account")
    if args.repeat < 1 or args.interval < 0 or args.replication_timeout < 0:
        parser.error("repeat must be positive and durations nonnegative")
    token = args.token_file.read_text().strip() if args.token_file else ""
    if token and not re.fullmatch(r"[A-Za-z0-9_.=+/-]+", token):
        parser.error("invalid token format")
    if args.mode == "roundtrip" and not token:
        parser.error("roundtrip requires --token-file")
    for iteration in range(args.repeat):
        if args.mode == "ready":
            status, _ = request(args, "", "GET", "/ready", ip=args.write_ip)
            if status != 200:
                raise RuntimeError(f"readiness failed: {status}")
        else:
            roundtrip(args, token)
        if iteration + 1 < args.repeat:
            time.sleep(args.interval)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as error:
        record("failed", error=str(error))
        raise SystemExit(1)
