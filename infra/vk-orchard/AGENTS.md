# vk-orchard

Virtual Kubelet provider that exposes the Tuist Orchard fleet (Scaleway
Mac minis hosting Tart VMs) as a virtual Kubernetes node. Lets the
cluster schedule macOS workloads as standard `Deployment`s / `Job`s with
`nodeSelector: kubernetes.io/os=darwin` and a `tuist.dev/macos`
toleration, instead of requiring a custom CRD per workload.

## Design

```
 K8s API server
       │
       │ Pod create/delete events
       ▼
 vk-orchard pod (Go, this directory)
       ├── PodController (upstream virtual-kubelet/node)
       │     └── routes Pod events to internal/provider
       ├── NodeController (upstream virtual-kubelet/node)
       │     └── publishes virtual Node + heartbeats
       └── HTTP kubelet API on :10250
             └── kubectl logs / exec / port-forward proxy
       │
       │ HTTPS (basic-auth via service account)
       ▼
 Orchard control plane
       │ Tart API + SSH
       ▼
 Mac minis (Scaleway, fleet managed by #10264's OrchardWorkerPool CRD)
```

## What's translated

| K8s primitive | Orchard / Tart side |
|---|---|
| Pod create | `POST /v1/vms` with image, cpu, memory, user-data (Pod env as JSON) |
| Pod delete | `DELETE /v1/vms/{name}` (idempotent on 404) |
| Pod status | poll `GET /v1/vms/{name}`, translate VM state → PodStatus |
| Container logs | `GET /v1/vms/{name}/logs?follow=true` |
| Node capacity | sum of online workers' CPU/memory minus VMs in flight |
| Node ready condition | green when ≥1 Orchard worker is online |

## What's intentionally not translated

- **Multi-container Pods, init containers** — rejected at admission.
- **PVC / hostPath volumes** — rejected.
- **HTTP probes** — VMs have no in-cluster IP. Use `exec` probes (a
  follow-up; not implemented in this version).
- **`kubectl exec`, `kubectl attach`** — return a clear "not implemented"
  error. Deferred until Orchard's exec endpoint is verified end-to-end.
- **`port-forward`** — not supported; no cluster networking into VMs.
- **Cluster-network reachability** — VMs reach Postgres + S3 over public
  internet. Fine for the xcresult-processor workload (no in-cluster
  callers); future workloads that need ClusterIP routing would add a
  Tailscale/WireGuard sidecar in their image.

## Layout

```
infra/vk-orchard/
├── cmd/vk-orchard/main.go        # entry point, wires the VK runtime
├── internal/orchard/             # Orchard HTTP client (port of Elixir)
│   ├── client.go
│   └── client_test.go
├── internal/provider/            # PodLifecycleHandler + NodeProvider
│   ├── provider.go
│   ├── node.go
│   └── provider_test.go
├── Dockerfile                    # distroless runtime image
├── go.mod / go.sum
└── AGENTS.md (this file)
```

## Configuration

Environment variables (set on the Pod spec via the chart):

| Var | Required | Notes |
|---|---|---|
| `ORCHARD_URL` | yes | e.g. `https://orchard.tuist.dev` |
| `ORCHARD_SERVICE_ACCOUNT_NAME` | yes | Orchard SA name |
| `ORCHARD_SERVICE_ACCOUNT_TOKEN` | yes | from k8s Secret |
| `VK_NODE_NAME` | no | default `tuist-orchard` |
| `VK_LISTEN_ADDR` | no | default `:10250` |
| `KUBECONFIG` | no | for local dev only; in-cluster uses the SA |

## Build

```bash
cd infra/vk-orchard
go test ./...
go build ./...
docker build -t ghcr.io/tuist/vk-orchard:dev .
```

## Deploy

The Helm chart (`infra/helm/tuist/templates/vk-orchard.yaml`) deploys
this as a single-replica Deployment with the right RBAC. Future HA: add
leader election via a k8s Lease and bump replicas.
