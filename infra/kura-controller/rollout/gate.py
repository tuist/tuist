"""Publication gate for regional Kura endpoints; uses current kubecontext."""

import argparse
import base64
import concurrent.futures
import http.client
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import time

from peer_probe_job import PeerProbeJob


def kube(namespace, kind, name=None, allow_missing=False):
    args = ["kubectl", "--request-timeout=15s", "-n", namespace, "get", kind]
    if os.environ.get("KURA_ROLLOUT_CONTEXT"):
        args += ["--context", os.environ["KURA_ROLLOUT_CONTEXT"]]
    if name:
        args.append(name)
    if allow_missing:
        args.append("--ignore-not-found")
    result = subprocess.run(args + ["-o", "json"], capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise RuntimeError(f"cannot read {namespace}/{kind}/{name or '*'}")
    if allow_missing and not result.stdout.strip():
        return None
    return json.loads(result.stdout)


def published_domains(deployment):
    for container in deployment["spec"]["template"]["spec"]["containers"]:
        for env in container.get("env", []):
            if env["name"] == "TUIST_KURA_REGIONAL_DNS_DOMAINS":
                return json.loads(env["value"])
    return {}


def plan(resources, namespace=None):
    controller = next((r for r in resources if r["kind"] == "Deployment" and
                       r["metadata"].get("labels", {}).get("app.kubernetes.io/component") == "kura-controller"), None)
    server = next((r for r in resources if r["kind"] == "Deployment" and
                   r["metadata"].get("labels", {}).get("app.kubernetes.io/component") == "server"), None)
    if not server or not published_domains(server):
        return {}
    if not controller:
        raise ValueError("regional publication requires the controller")
    flags = dict(arg[2:].split("=", 1) for arg in controller["spec"]["template"]["spec"]["containers"][0]["args"] if arg.startswith("--") and "=" in arg)
    regions = json.loads(flags["regional-routing-config"])
    domains = published_domains(server)
    regions = [r for r in regions if r["region"] in domains]
    if domains != {r["region"]: r["domain"] for r in regions}:
        raise ValueError("controller and server regional domains differ")
    return {"namespace": controller["metadata"]["namespace"], "regions": regions,
            "serverNamespace": namespace or server["metadata"].get("namespace") or "default", "serverName": server["metadata"]["name"],
            "certificate": flags["public-tls-secret-name"]}


def needs_preparation(config):
    if not config:
        return False
    deployment = kube(config["serverNamespace"], "deployment", config["serverName"], allow_missing=True)
    live = published_domains(deployment) if deployment else {}
    return any(live.get(r["region"]) != r["domain"] for r in config["regions"])


def preparation_values(config):
    deployment = kube(config["serverNamespace"], "deployment", config["serverName"], allow_missing=True)
    live = published_domains(deployment) if deployment else {}
    desired = {r["region"]: r["domain"] for r in config["regions"]}
    if any(desired.get(region) != domain for region, domain in live.items()):
        raise ValueError("preparation cannot change or remove an already published regional domain")
    return {"kuraController": {"regionalRouting": {
        "publishEndpoints": True, "publicationRegions": sorted(live)}}}


def targets(endpoint, hostname):
    return {address for record in endpoint.get("spec", {}).get("endpoints", [])
            if record["dnsName"] == hostname and record["recordType"] in ("A", "AAAA")
            for address in record["targets"]}


def verify_dns(hostname, expected):
    actual = {result[4][0] for result in socket.getaddrinfo(hostname, None, type=socket.SOCK_STREAM)}
    if not expected or actual != expected:
        raise RuntimeError(f"DNS has not converged for {hostname}")


def https_probe(host, address):
    context = ssl.create_default_context()
    context.set_alpn_protocols(["http/1.1"])
    try:
        with socket.create_connection((address, 443), timeout=5) as sock:
            with context.wrap_socket(sock, server_hostname=host) as tls:
                tls.sendall(f"GET /up HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode())
                response = http.client.HTTPResponse(tls)
                response.begin()
                if response.status != 200:
                    raise RuntimeError(f"{host} via {address}: /up returned {response.status}")
    except (OSError, http.client.HTTPException) as error:
        raise RuntimeError(f"{host} via {address}:443: public probe failed: {error}") from None


def peer_probe(host, addresses, secret):
    data = {key: base64.b64decode(secret["data"][key]) for key in ("ca.pem", "tls.crt", "tls.key")}
    context = ssl.create_default_context(cadata=data["ca.pem"].decode())
    with tempfile.TemporaryDirectory(prefix="kura-peer-probe-") as directory:
        for key, value in data.items():
            path = Path(directory) / key
            path.write_bytes(value)
            os.chmod(path, 0o600)
        context.load_cert_chain(str(Path(directory) / "tls.crt"), str(Path(directory) / "tls.key"))
        for address in addresses:
            try:
                with socket.create_connection((address, 7443), timeout=5) as sock:
                    with context.wrap_socket(sock, server_hostname=host) as tls:
                        # TLS 1.3 can report a rejected client certificate only on
                        # the first read, after wrap_socket has already returned.
                        tls.sendall(f"GET /_internal/status HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode())
                        response = http.client.HTTPResponse(tls)
                        response.begin()
                        if response.status != 200:
                            raise RuntimeError(f"{host} via {address}: peer status returned {response.status}")
            except (OSError, http.client.HTTPException) as error:
                raise RuntimeError(f"{host} via {address}:7443: peer probe failed: {error}") from None


def check(config, peer_transport=None):
    peer_transport = peer_transport or peer_probe
    namespace = config["namespace"]
    certificate = kube(namespace, "certificate", config["certificate"])
    if not any(c["type"] == "Ready" and c["status"] == "True" and
               c.get("observedGeneration") == certificate["metadata"]["generation"]
               for c in certificate.get("status", {}).get("conditions", [])):
        raise RuntimeError("regional wildcard certificate is not Ready")
    instances = kube(namespace, "kurainstances")["items"]
    ingresses = {i["metadata"]["name"]: i for i in kube(namespace, "ingresses")["items"]}
    workloads = {s["metadata"]["name"]: s for s in kube(namespace, "statefulsets")["items"]}
    endpoints = {e["metadata"]["name"]: e for e in kube(namespace, "dnsendpoints")["items"]}
    regional_names = {f"kura-regional-{r['region']}-dns" for r in config["regions"]}
    individual_hosts = {record["dnsName"] for name, endpoint in endpoints.items() if name not in regional_names
                        for record in endpoint.get("spec", {}).get("endpoints", [])}
    tasks = []
    for region in config["regions"]:
        domain = region["domain"]
        if "*." + domain not in certificate["spec"]["dnsNames"]:
            raise RuntimeError(f"certificate does not include {domain}")
        endpoint = endpoints.get(f"kura-regional-{region['region']}-dns", {})
        public = targets(endpoint, "*." + domain)
        peers = targets(endpoint, "*.peer." + domain)
        verify_dns("regional-rollout-probe." + domain, public)
        verify_dns("peer." + domain, public)
        for instance in instances:
            spec = instance["spec"]
            if spec.get("private") or spec.get("region") != region["region"]:
                continue
            if not spec.get("publicHostNetwork") or spec.get("ingressClassName") != region["ingressClass"]:
                raise RuntimeError("instance does not match its regional ingress configuration")
            name = instance["metadata"]["name"]
            workload = workloads.get(name, {})
            status = workload.get("status", {})
            replicas = workload.get("spec", {}).get("replicas", 1)
            if (status.get("readyReplicas", 0) != replicas or
                    status.get("updatedReplicas", 0) != replicas or
                    status.get("observedGeneration") != workload.get("metadata", {}).get("generation") or
                    not status.get("updateRevision") or
                    status.get("currentRevision") != status["updateRevision"]):
                raise RuntimeError(f"peer certificate rollout incomplete for {name}")
            host = spec["accountHandle"] + "." + domain
            peer_host = spec["accountHandle"] + ".peer." + domain
            if host in individual_hosts or peer_host in individual_hosts:
                raise RuntimeError(f"individual regional DNS records still exist for {name}")
            for ingress_name in (name, name + "-grpc"):
                ingress = ingresses.get(ingress_name, {})
                if host not in [r["host"] for r in ingress.get("spec", {}).get("rules", [])]:
                    raise RuntimeError(f"regional alias missing from {ingress_name}")
                if ingress["metadata"].get("annotations", {}).get("external-dns.alpha.kubernetes.io/controller") != "kura-controller":
                    raise RuntimeError(f"individual DNS publication still enabled for {ingress_name}")
            verify_dns(host, public)
            for address in public:
                tasks.append((https_probe, (host, address)))
            if spec.get("meshPublicPeerHost"):
                verify_dns(peer_host, peers)
                secret = kube(namespace, "secret", spec.get("peerTLSSecretName") or name + "-peer-tls")
                tasks.append((peer_transport, (peer_host, peers, secret)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        futures = [executor.submit(function, *args) for function, args in tasks]
        for future in futures:
            future.result()
    return len(tasks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "needed", "prepare-values", "wait"])
    parser.add_argument("file")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--namespace", help="Helm server release namespace")
    args = parser.parse_args()
    config = json.loads(Path(args.file).read_text())
    if args.action == "plan":
        print(json.dumps(plan(config, args.namespace)))
    elif args.action == "needed":
        print("true" if needs_preparation(config) else "false")
    elif args.action == "prepare-values":
        print(json.dumps(preparation_values(config)))
    elif config:
        deadline = time.monotonic() + args.timeout
        with PeerProbeJob(config["namespace"]) as probe_job:
            peer_transport = lambda host, addresses, secret: probe_job.probe(peer_probe, host, addresses, secret)
            while True:
                try:
                    count = check(config, peer_transport)
                    print(f"Regional routing ready: {len(config['regions'])} regions, {count} serving-path probes")
                    return
                except (RuntimeError, OSError, ValueError, KeyError, http.client.HTTPException, subprocess.TimeoutExpired) as error:
                    if time.monotonic() >= deadline:
                        raise SystemExit(f"Regional publication blocked: {error}") from None
                    print(f"Waiting for regional routing: {error}", flush=True)
                    time.sleep(10)


if __name__ == "__main__":
    main()
