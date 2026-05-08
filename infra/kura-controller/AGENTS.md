# Kura Controller

This module contains the Kubernetes controller that reconciles Kura account endpoint custom resources.

## Scope

- API group: `kura.tuist.dev`
- Primary resource: `KuraInstance`
- Controller output: Kubernetes workload resources for one account-region Kura deployment.

## Deployment Topology

- **Cache traffic (HTTP)**: each `KuraInstance` with `spec.publicHost` set gets a Hetzner Cloud LoadBalancer in HTTPS mode with managed certificates. The LB terminates TLS as HTTP/1.1 to the runtime, which is fine for the cache protocol.
- **gRPC for Bazel**: setting `spec.grpcPublicHost` provisions a separate Hetzner LoadBalancer in TCP passthrough mode (Hetzner managed certificates only support HTTP/HTTPS, not gRPC over HTTP/2). When the controller's `--grpc-cluster-issuer` flag is set, the controller also creates a cert-manager `Certificate` per instance; the issued Secret is mounted into the runtime, which then terminates TLS itself. With no issuer the gRPC port is exposed plaintext — only acceptable for kind/dev clusters.
- **Single-AZ Hetzner**: each managed region is one Hetzner location (`fsn1`/`ash`/`hil`) without zones. Topology spread is hostname-only — three replicas tolerate one node loss, but a location-wide outage takes the whole regional Kura down. Cross-region failover is the user's responsibility (provision Kura in multiple regions; CLI/Bazel can target any of them).
- **Per-tenant isolation**: a `NetworkPolicy` per `KuraInstance` restricts ingress to (a) pods of the same instance and (b) cluster-namespaced peers reaching `http`/`grpc` only. Egress is unrestricted because the runtime needs to reach the Tuist API and the OTLP collector.
- **PVC retention**: the StatefulSet uses `whenDeleted: Delete` so a destroyed `KuraInstance` releases its hcloud volumes, and `whenScaled: Retain` so a replica scaling event keeps its cache.
- **Resource limits**: the controller deliberately does **not** set `KURA_FILE_DESCRIPTOR_POOL_SIZE`, `KURA_MEMORY_SOFT_LIMIT_BYTES`, etc. The runtime derives those at startup from the pod's cgroup memory limit and `RLIMIT_NOFILE`. Tune the pod-level `resources.limits.memory` instead — the soft/hard application limits are 70% / 85% of that.

## Development

- Run tests with `go test ./...` from this directory.
- Keep generated CRDs in `infra/helm/tuist/crds/` aligned with API changes.
- Keep the controller independent from the Scaleway Apple Silicon CAPI provider. Kura endpoint lifecycle is a product workload concern, not a macOS node infrastructure concern.
- cert-manager must be installed in the cluster before turning on `--grpc-cluster-issuer`. The controller does not provision the issuer itself.
