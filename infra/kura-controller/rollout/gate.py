"""Publication gate for regional Kura endpoints; uses current kubecontext."""

import argparse
import base64
import concurrent.futures
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import ssl
import subprocess
import tempfile
import time

from peer_probe_job import PeerProbeJob, IPv6ProbeJobs


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
        raise RuntimeError(f"cannot read {namespace}/{kind}/{name or '*'}: {result.stderr.strip()[:2000]}")
    if allow_missing and not result.stdout.strip():
        return None
    return json.loads(result.stdout)


def published_domains(deployment):
    for container in deployment["spec"]["template"]["spec"]["containers"]:
        for env in container.get("env", []):
            if env["name"] == "TUIST_KURA_REGIONAL_DNS_DOMAINS":
                return json.loads(env["value"])
    return {}


def controller_argument(arguments, name):
    prefix = "--" + name + "="
    for argument in reversed(arguments):
        if argument.startswith(prefix):
            return argument[len(prefix):]
    raise ValueError(f"controller argument is missing: {name}")


def plan(resources, namespace=None):
    controller = next((r for r in resources if r["kind"] == "Deployment" and
                       r["metadata"].get("labels", {}).get("app.kubernetes.io/component") == "kura-controller"), None)
    server = next((r for r in resources if r["kind"] == "Deployment" and
                   r["metadata"].get("labels", {}).get("app.kubernetes.io/component") == "server"), None)
    if not server or not published_domains(server):
        return {}
    if not controller:
        raise ValueError("regional publication requires the controller")
    arguments = controller["spec"]["template"]["spec"]["containers"][0]["args"]
    regions = json.loads(controller_argument(arguments, "regional-routing-config"))
    # This flag names a Kubernetes resource; it contains no certificate or key
    # material. Read only the two arguments the metadata-only plan needs.
    certificate_name = controller_argument(arguments, "public-tls-secret-name")
    if len(certificate_name) > 253 or any(
        len(label) > 63 or not re.fullmatch(r"[a-z0-9](?:[-a-z0-9]*[a-z0-9])?", label)
        for label in certificate_name.split(".")
    ):
        raise ValueError("public certificate reference is not a valid Kubernetes resource name")
    domains = published_domains(server)
    regions = [r for r in regions if r["region"] in domains]
    if domains != {r["region"]: r["domain"] for r in regions}:
        raise ValueError("controller and server regional domains differ")
    return {"namespace": controller["metadata"]["namespace"], "regions": regions,
            "serverNamespace": namespace or server["metadata"].get("namespace") or "default", "serverName": server["metadata"]["name"],
            "certificate": certificate_name}


def pending_plan(config):
    if not config:
        return {}
    deployment = kube(config["serverNamespace"], "deployment", config["serverName"], allow_missing=True)
    live = published_domains(deployment) if deployment else {}
    pending = [r for r in config["regions"] if live.get(r["region"]) != r["domain"]]
    return {**config, "regions": pending} if pending else {}


def needs_preparation(config):
    return bool(pending_plan(config))


def check_legacy_peer_services(config):
    if not config:
        return
    namespace = config["namespace"]
    regions = {r["region"] for r in config["regions"]}
    instances = [i for i in kube(namespace, "kurainstances")["items"]
                 if i["spec"].get("region") in regions and not i["spec"].get("private")]
    accounts = {i["spec"]["accountHandle"] for i in instances}
    names = {i["metadata"]["name"] for i in instances}
    hosts = set()
    for instance in instances:
        hosts.add(instance["spec"].get("meshPublicPeerHost"))
        aliases = json.loads(instance["metadata"].get("annotations", {}).get("kura.tuist.dev/legacy-peer-hosts", "[]"))
        if not isinstance(aliases, list) or not all(isinstance(host, str) for host in aliases):
            raise ValueError("legacy peer hosts must be a JSON array of DNS names")
        hosts.update(aliases)
    hosts.discard(None)
    hosts.discard("")
    for service in kube(namespace, "services")["items"]:
        metadata = service["metadata"]
        labels = metadata.get("labels", {})
        annotations = metadata.get("annotations", {})
        service_hosts = {annotations.get("external-dns.alpha.kubernetes.io/hostname"), annotations.get("kura.tuist.dev/legacy-peer-host")}
        selects_instance = service.get("spec", {}).get("selector", {}).get("app.kubernetes.io/instance") in names
        if (not metadata.get("ownerReferences") and
                labels.get("app.kubernetes.io/managed-by") == "kura-controller" and
                not labels.get("app.kubernetes.io/instance") and
                labels.get("tuist.dev/account") in accounts and
                (bool(service_hosts & hosts) or selects_instance) and
                service.get("spec", {}).get("type") == "LoadBalancer"):
            raise RuntimeError(f"finish legacy peer LoadBalancer retirement before regional publication: {namespace}/{metadata['name']}")


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
    context.minimum_version = ssl.TLSVersion.TLSv1_2
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
    context.minimum_version = ssl.TLSVersion.TLSv1_2
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


def check(config, peer_transport=None, public_transport=None):
    peer_transport = peer_transport or peer_probe
    public_transport = public_transport or https_probe
    namespace = config["namespace"]
    certificate = kube(namespace, "certificate", config["certificate"])
    if not any(c["type"] == "Ready" and c["status"] == "True" and
               c.get("observedGeneration") == certificate["metadata"]["generation"]
               for c in certificate.get("status", {}).get("conditions", [])):
        raise RuntimeError("regional wildcard certificate is not Ready")
    check_legacy_peer_services(config)
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
                tasks.append((public_transport, (host, address)))
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
    parser.add_argument("action", choices=["plan", "pending", "needed", "preflight", "prepare-values", "wait"])
    parser.add_argument("file")
    parser.add_argument("--timeout", type=int, default=2400)
    parser.add_argument("--namespace", help="Helm server release namespace")
    args = parser.parse_args()
    config = json.loads(Path(args.file).read_text())
    if args.action == "plan":
        print(json.dumps(plan(config, args.namespace)))
    elif args.action == "pending":
        print(json.dumps(pending_plan(config)))
    elif args.action == "preflight":
        check_legacy_peer_services(config)
    elif args.action == "needed":
        print("true" if needs_preparation(config) else "false")
    elif args.action == "prepare-values":
        print(json.dumps(preparation_values(config)))
    elif config:
        deadline = time.monotonic() + args.timeout
        with PeerProbeJob(config["namespace"], lifetime=args.timeout + 180) as probe_job, IPv6ProbeJobs(config["namespace"], kube, args.timeout + 180) as ipv6_jobs:
            def peer_transport(host, addresses, secret):
                ipv4 = {address for address in addresses if ipaddress.ip_address(address).version == 4}
                if ipv4:
                    probe_job.probe(peer_probe, host, ipv4, secret)
                for address in addresses - ipv4:
                    ipv6_jobs.peer_probe(peer_probe, host, address, secret)
            def public_transport(host, address):
                if ipaddress.ip_address(address).version == 6:
                    ipv6_jobs.probe(https_probe, host, address)
                else:
                    https_probe(host, address)

            while True:
                try:
                    count = check(config, peer_transport, public_transport)
                    print(f"Regional routing ready: {len(config['regions'])} regions, {count} serving-path probes")
                    return
                except (RuntimeError, OSError, ValueError, KeyError, http.client.HTTPException, subprocess.TimeoutExpired) as error:
                    if time.monotonic() >= deadline:
                        raise SystemExit(f"Regional publication blocked: {error}") from None
                    print(f"Waiting for regional routing: {error}", flush=True)
                    time.sleep(10)


if __name__ == "__main__":
    main()
