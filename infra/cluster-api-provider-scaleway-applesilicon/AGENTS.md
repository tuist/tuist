# cluster-api-provider-scaleway-applesilicon

Cluster API infrastructure provider that manages Scaleway Apple
Silicon Mac minis as Kubernetes nodes. Watches CRs, calls Scaleway's
API to order machines, SSHes in to bootstrap kubelet + tart-cri,
waits for `Node.Ready`, surfaces all of it through CAPI's standard
Machine/MachineDeployment shape.

## CRDs

| Kind | Purpose |
|---|---|
| `ScalewayAppleSiliconMachine` | One Mac mini. Has the Scaleway server type, zone, OS, per-host pod CIDR, and Secret refs for SSH key + cluster bootstrap material. |
| `ScalewayAppleSiliconMachineTemplate` | Template MachineDeployments / MachineSets clone from. |
| `ScalewayAppleSiliconCluster` | Cluster-level stub (CAPI core requires it for the parent Cluster to validate). Sets `Status.Ready=true` once it exists. |

API group: `infrastructure.cluster.x-k8s.io/v1alpha1`. Short names:
`samm`, `sammt`, `sasc`.

## Architecture

```
 K8s API server                                  (control plane)
       │
       │ ScalewayAppleSiliconMachine CR
       ▼
 ┌──────────────────────────────────────────────┐
 │ capi-scaleway-applesilicon manager           │
 │   ├── ScalewayAppleSiliconMachineReconciler  │
 │   │   ├── 1. Stage: Provisioning             │
 │   │   │      scaleway.CreateServer(...)      │
 │   │   │      → ProviderID, IP, sudo password │
 │   │   ├── 2. Stage: Bootstrapping            │
 │   │   │      bootstrap.Run(SSH, Tart, kubelet,│
 │   │   │      tart-cri, launchd, ...)         │
 │   │   └── 3. Stage: Ready                    │
 │   │          poll Node object until Ready    │
 │   └── ScalewayAppleSiliconClusterReconciler  │
 │         └── stub: Status.Ready=true          │
 └──────────┬───────────────────────────────────┘
            │ HTTPS (Scaleway SDK)         │ SSH (per-machine SSH key)
            ▼                              ▼
       Scaleway API                  Mac mini host
                                       (kubelet + tart-cri)
                                              │
                                              │ kubelet self-registers
                                              ▼
                                     K8s API server (Node)
```

The MachineReconciler is idempotent at every stage: re-running on a
partially-bootstrapped host completes the missing steps without
redoing finished ones. Failures requeue with backoff; only terminal
errors (Scaleway 400s, validation failures) set
`Status.FailureReason`.

## Module layout

```
infra/cluster-api-provider-scaleway-applesilicon/
├── api/v1alpha1/
│   ├── groupversion_info.go
│   ├── scalewayapplesiliconmachine_types.go
│   ├── scalewayapplesiliconmachinetemplate_types.go
│   ├── scalewayapplesiliconcluster_types.go
│   └── zz_generated.deepcopy.go
├── controllers/
│   ├── scalewayapplesiliconmachine_controller.go
│   └── scalewayapplesiliconcluster_controller.go
├── internal/
│   ├── scaleway/   # Scaleway SDK wrapper
│   └── bootstrap/  # SSH-driven kubelet/tart-cri install
├── cmd/manager/    # controller-manager entry point
├── config/
│   ├── crd/        # CRD manifests
│   └── rbac/       # ClusterRole for the manager
├── Dockerfile
└── AGENTS.md (this file)
```

## Required Secrets (one per fleet)

| Secret | Keys | Purpose |
|---|---|---|
| `<release>-capi-scaleway-applesilicon` | `access-key`, `secret-key`, `project-id` | Scaleway API auth for the operator. |
| `<fleet>-ssh` | `id_ed25519` | SSH key the operator uses to bootstrap each Mac mini. Public half must be registered with the Scaleway tenant so it lands in `~/.ssh/authorized_keys` at first boot. |
| `<fleet>-bootstrap` | `bootstrap-token`, `api-server`, `ca-cert-data`, optional `kubelet-version` | Cluster join material kubelet uses on each new Mac mini. |

The chart deliberately doesn't manage these — operators seed them via
1Password → ESO sync, or `kubectl create secret` by hand. Token
rotation is a Secret update; the operator picks up the new value on
the next reconcile.

## Build

```bash
cd infra/cluster-api-provider-scaleway-applesilicon
go test ./...
go build ./...
docker build -f Dockerfile -t ghcr.io/tuist/capi-provider-scaleway-applesilicon:dev ../..
```

The Dockerfile is multi-stage: it cross-builds tart-cri + tart-cni
for darwin/arm64 (so the manager can ship them to Mac minis at
bootstrap time) and builds the manager itself for whatever
linux/<arch> the cluster runs on.

## Operating

### Scale up
```bash
kubectl scale machinedeployment <fleet-name> --replicas=4
```
Two new ScalewayAppleSiliconMachines are created → operator orders
two Mac minis from Scaleway → ~5 min later `kubectl get nodes` shows
them Ready.

### Scale down
```bash
kubectl scale machinedeployment <fleet-name> --replicas=1
```
CAPI core picks the most-recently-created Machines for deletion;
operator releases them via Scaleway's API (the 24h Apple licensing
floor still applies — Scaleway keeps charging until the boundary).

### Replace a wedged host
```bash
kubectl delete machine <machine-name>
```
The MachineSet immediately creates a replacement; the old Mac mini
is released back to Scaleway after the operator's delete reconcile.

### Investigate a failure
```bash
kubectl describe scalewayapplesiliconmachine <name>
# Check the Conditions: Provisioned / Bootstrapped / NodeReady
kubectl get events --field-selector involvedObject.kind=ScalewayAppleSiliconMachine
```

## What's not implemented yet

- **Per-host pod CIDR allocation.** Today the chart hand-assigns each
  fleet a single pod CIDR; if you scale beyond 1 replica with the
  same CIDR, the second host's CNI plugin will allocate IPs from the
  same range (collisions). Options to fix: (a) bumped to a CIDR
  manager controller in the operator, (b) per-Machine CIDR
  annotation that the chart pre-computes, (c) Calico/Cilium IPAM
  delegated to the cluster's existing CNI. (a) is the right
  long-term answer; (b) is the cheap interim. Watch this space when
  the fleet grows past 1 replica per env.
- **Cross-host pod-to-pod routing.** Lives at the tart-cni layer, not
  the CAPI provider. See `infra/tart-cri/AGENTS.md`.
- **Webhooks for validation.** CRD-level OpenAPI schema catches
  obvious shape errors; semantic validation (e.g. valid Scaleway
  zone) happens at reconcile time, returning a Failed condition.
- **Events for in-progress lifecycle stages.** Today `kubectl describe
  machine` shows Conditions; explicit `Event` objects per state
  transition would make tail-following easier.
