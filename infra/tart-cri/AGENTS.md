# tart-cri

Container Runtime Interface (CRI) implementation that drives Tart on
macOS. Lets a Mac mini join a Kubernetes cluster as a real node:
kubelet on the host talks to `tart-cri` over a Unix socket, and
`tart-cri` translates Pod operations into `tart` CLI invocations.

## Why this exists

Cirrus Labs' Orchard models the same shape — workers, VMs, scheduling,
control channel — as a parallel control plane that lives outside the
cluster. tart-cri makes Mac minis first-class k8s nodes instead, so:

- `kubectl get nodes` lists every Mac mini.
- Pods scheduled with `nodeSelector: kubernetes.io/os=darwin` land as
  Tart VMs.
- `kubectl logs`, `kubectl describe pod`, `Events`, HPA, ResourceQuota
  all work without translation layers.
- Future macOS workloads (CI runners, signing services, etc.) compose
  through the same primitives Linux workloads use.

The trade-off vs Orchard: more code we own (Tart-CRI implementation,
CNI plugin, kubelet bootstrap on macOS), no third-party control plane
dependency.

## Architecture

```
 K8s API server
       │
       │ kubelet on Mac mini
       ▼
 ┌──────────────────────────────┐
 │ tart-cri (Unix socket)       │
 │   ├── RuntimeService         │
 │   │     ├── PodSandbox CRUD  │
 │   │     ├── Container CRUD   │
 │   │     └── ContainerStatus  │
 │   └── ImageService           │
 │         ├── PullImage        │
 │         └── ListImages       │
 └──────────┬───────────────────┘
            │ tart CLI subprocess calls
            ▼
       Tart VMs on the host
```

One Pod ↔ one Tart VM. Multi-container Pods are not supported — kubelet
gracefully refuses to schedule them onto the node based on the runtime
status conditions we report.

## Layout

```
infra/tart-cri/
├── cmd/
│   ├── tart-cri/main.go     # CRI gRPC server kubelet connects to
│   └── tart-cni/main.go     # CNI plugin (IPAM + interface setup)
└── internal/
    ├── runtimeservice/      # CRI RuntimeService impl
    ├── imageservice/        # CRI ImageService impl
    ├── state/               # Persistent sandbox/container state
    └── tart/                # Tart CLI wrapper
```

## Build

```bash
cd infra/tart-cri
go test ./...
go build ./...
```

Two binaries are produced: `tart-cri` (the runtime) and `tart-cni`
(the CNI plugin).

## Bootstrap on a Mac mini

1. **Install Tart** (`brew install cirruslabs/cli/tart`) and ensure
   the host has a live GUI session (Virtualization.framework requirement).
2. **Install kubelet** for darwin/arm64. The upstream binary builds
   for macOS; pull from `dl.k8s.io/release/v1.32.x/bin/darwin/arm64/kubelet`.
3. **Drop tart-cri + tart-cni** binaries to `/usr/local/bin`.
4. **Generate kubeconfig** via the cluster's bootstrap token (same
   pattern as joining a Linux node — kubeadm-style or via Cluster
   API).
5. **Write the kubelet config** at `/etc/kubernetes/kubelet-config.yaml`
   pointing `containerRuntimeEndpoint` at `unix:///var/run/tart-cri/tart-cri.sock`.
6. **Configure the CNI** at `/etc/cni/net.d/10-tart.conflist` with
   the per-host pod CIDR sliced from the cluster CIDR.
7. **Boot tart-cri + kubelet under launchd** — see `platform/`
   templates for the plists.

After step 7, `kubectl get nodes` on the cluster should show the Mac
mini as `Ready` after ~30 seconds.

## Networking

The CNI plugin in this version (`tart-cni`) handles per-host IPAM
only. Cross-host pod-to-pod routing is currently unimplemented; Pods
on a Mac mini can:

- Egress to the public internet freely.
- Reach other Pods *on the same Mac mini*.
- **Not** reach Pods on other nodes via ClusterIP, and **not** be
  reached by in-cluster Services from other nodes.

Adding cross-host routing is a CNI plugin chain extension (e.g. a
WireGuard plugin that follows tart-cni in the chain) — left for a
follow-up because xcresult-processor doesn't need ingress
reachability. The CI runner workload (#10264) will require it; expect
that PR to add a WireGuard CNI plugin to the chain.

## What's not implemented

CRI surface intentionally stubbed with `Unimplemented`:

- `Exec` / `ExecSync` / `Attach` — `kubectl exec` returns a clear
  error. Implement when needed; would map to `tart exec` (SSH).
- `PortForward` — same.
- `ContainerStats` / `ListContainerStats` — disables `kubectl top
  pod`. Add when HPA on macOS workloads needs metric-based scaling.
- `UpdateContainerResources` — we don't change resources mid-flight;
  k8s' Deployment controller recreates the Pod for resource changes.

## Testing

Unit tests cover the Tart wrapper and the persistent state store.
End-to-end testing (kubelet ↔ tart-cri ↔ Tart on a real Mac mini) is
the cutover validation step — we don't have a way to test it from
this repo today.
