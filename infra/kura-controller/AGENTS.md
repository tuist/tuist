# Kura Controller

This module contains the Kubernetes controller that reconciles Kura account endpoint custom resources.

## Scope

- API group: `kura.tuist.dev`
- Primary resource: `KuraInstance`
- Controller output: Kubernetes workload resources for one account-region Kura deployment.

## Deployment Topology

- **Cache traffic (HTTPS)**: each `KuraInstance` with `spec.publicHost` set gets a Hetzner Cloud LoadBalancer in TCP-passthrough mode targeting the runtime's TLS-terminating HTTPS port (`4443`). When the controller's `--grpc-cluster-issuer` flag is set, the controller creates a cert-manager `Certificate` per instance against that ClusterIssuer; the issued Secret is mounted into the runtime, which terminates TLS itself. Health checks talk plain HTTP to the runtime's plain HTTP port (`4000`). Hetzner-managed certificates are not used because Tuist's `kura.tuist.dev` zone lives on Cloudflare, so Hetzner can't validate the domain it would issue for.
- **gRPC for Bazel**: setting `spec.grpcPublicHost` provisions a separate Hetzner LoadBalancer in TCP passthrough mode. When `--grpc-cluster-issuer` is set, the controller creates a cert-manager `Certificate` per instance; the issued Secret is mounted into the runtime, which terminates TLS itself. With no issuer the gRPC port is exposed plaintext — only acceptable for kind/dev clusters.
- **Single-AZ Hetzner**: each managed region is one Hetzner location (`fsn1`/`ash`/`hil`) without zones. Topology spread is hostname-only — three replicas tolerate one node loss, but a location-wide outage takes the whole regional Kura down. Cross-region failover is the user's responsibility (provision Kura in multiple regions; CLI/Bazel can target any of them).
- **Scheduling fallback**: by default the runtime prefers nodes labeled `node.cluster.x-k8s.io/pool=kura`, but it only requires `kubernetes.io/os=linux` and tolerates the standard control-plane taints. That lets a degraded regional cluster keep serving from control-plane nodes when the dedicated `kura` pool disappears. An explicit `spec.nodeSelector` still becomes a hard requirement and is mirrored into the Hetzner LoadBalancer node selector.
- **Per-tenant isolation**: a `NetworkPolicy` per `KuraInstance` restricts ingress to (a) pods of the same instance and (b) cluster-namespaced peers reaching `http`/`grpc` only. Egress is unrestricted because the runtime needs to reach the Tuist API and the OTLP collector.
- **PVC retention**: the StatefulSet uses `whenDeleted: Delete` so a destroyed `KuraInstance` releases its hcloud volumes, and `whenScaled: Retain` so a replica scaling event keeps its cache.
- **Resource limits**: the controller deliberately does **not** set `KURA_FILE_DESCRIPTOR_POOL_SIZE`, `KURA_MEMORY_SOFT_LIMIT_BYTES`, etc. The runtime derives those at startup from the pod's cgroup memory limit and `RLIMIT_NOFILE`. Tune the pod-level `resources.limits.memory` instead — the soft/hard application limits are 70% / 85% of that.

## Development

- Run tests with `go test ./...` from this directory.
- Keep generated CRDs in `infra/helm/tuist/crds/` aligned with API changes.
- Keep the controller independent from the Scaleway Apple Silicon CAPI provider. Kura endpoint lifecycle is a product workload concern, not a macOS node infrastructure concern.
- cert-manager must be installed in the cluster before turning on `--grpc-cluster-issuer`. The controller does not provision the issuer itself. The same issuer is used for both the public HTTPS and gRPC Certificates.
