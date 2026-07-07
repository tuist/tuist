# Design: declarative Scaleway Elastic Metal nodes via the in-house provider

Status: implemented. The kura runner-cache node (`kura-scw-fr-par`) is a
declaratively-provisioned Scaleway **Elastic Metal** worker in the
staging/canary/production clusters, managed by this provider.

## Scope

The kura runner-cache node runs as a worker in the **same** cluster as the
Hetzner kura nodes, provisioned and managed by this provider. Everything about
it is declared in-repo (Helm values + the CR spec):

- its node labels (`node.cluster.x-k8s.io/pool=kura-scw-fr-par`,
  `tuist.dev/pn-ipv4`) and the `tuist.dev/runner-cache:NoSchedule` taint;
- the Private Network attachment and the `scaleway://` providerID;
- CAPI lifecycle (scale, replace, heal) alongside the Hetzner kura pool, with
  each environment's pool reproducible from values.

## Why this provider (not upstream CAPS, not cloud-init)

- **Upstream `cluster-api-provider-scaleway` does not fit.** It models a
  Scaleway-infra cluster (`ScalewayCluster` owns the PrivateNetwork and control
  plane). Our clusters are `HetznerCluster` (caph), single infrastructure
  provider, and the mesh/NodePort design requires the kura node to be a
  **worker in the existing cluster** — not a separate Scaleway cluster. CAPI
  doesn't let a CAPS worker pool attach to a Hetzner-infra cluster.
- **This provider already does exactly that** for Apple Silicon: a stub
  `TuistCluster` (only there to satisfy CAPI parent-Cluster
  validation) + a self-join that registers the machine into the existing caph
  cluster as a worker, through the standard Machine/MachineDeployment shape. The
  Elastic Metal kind is the same pattern with a different provisioning call.
- **A committed cloud-init script** would make the join reproducible but carries
  no lifecycle (scale/replace/heal) and no CAPI integration.

## Architecture

The provider has two machine kinds, sharing the stub cluster, the CAPI
Machine/MachineDeployment shape, the SSH self-join bootstrap, and the orphan
reclaimer:

| Kind | Server | Cache storage |
|---|---|---|
| `ScalewayAppleSiliconMachine` | Mac mini (Tart) | — |
| `ScalewayElasticMetalMachine` | Scaleway Elastic Metal (Linux bare metal) | local NVMe (`scw-local-nvme`) |

Both **mint a per-machine kubelet identity and SSH-deliver a self-join** — they
do **not** use the CAPI kubeadm bootstrap provider. This cluster's control
plane is externally managed (caph/Hetzner), so there is no kubeadm join
endpoint for workers: the operator mints a node ServiceAccount token + CA,
renders a kubelet kubeconfig into a self-join script (install
containerd/kubelet, write the kubeconfig, register with
`--register-with-taints`), SSHes in, and the node joins with that identity. The
Elastic Metal kind binds that identity to `system:node`; Apple Silicon uses the
`tart-kubelet` role. The MachineDeployment carries a `noop-bootstrap` secret,
exactly like the macOS fleets — there is no `KubeadmConfigTemplate`.

Elastic Metal is the runner-cache shape because a bare-metal box gives ~10
Gbit/s flat PN and local NVMe at ~27 Gbit/s, versus a PRO2-S Instance's
token-bucketed ~1.5 Gbit/s PN and ~4 Gbit/s `scw-bssd` — cheaper, with more RAM
for warm-set page cache.

```
 ScalewayElasticMetalMachine CR (one EM box)
        │
        ▼
 capi-scaleway-applesilicon manager
   └── ScalewayElasticMetalMachineReconciler
        ├── Order       baremetal.CreateServer(offerType, zone, OS); record ServerID
        │               (idempotent find-by-name so a restart re-finds it)
        ├── OS install  poll until install completes (~30-60m; box is
        │               unreachable until then — no user-data channel)
        ├── PN as VLAN  EnsurePrivateNetwork → attach + resolve the VLAN tag
        ├── Bootstrap   mint kubelet identity → render self-join → SSH-deliver
        │               (TOFU host-key pinned per machine); then set providerID
        └── Ready       link Node by providerID; stamp the dynamic
                        tuist.dev/pn-ipv4 label (read from IPAM) onto it
```

### CRDs

| Kind | Purpose |
|---|---|
| `ScalewayElasticMetalMachine(Template)` | One Scaleway Elastic Metal server. Spec: `offerType`, `zone`, `os`, `privateNetworkName`, `privateNetworkCIDR`, `nodeTaints`; status: `providerID`, `serverID`, `privateNetworkVLAN`, `phase`. |
| (reuse) `TuistCluster` | Generic stub satisfying CAPI parent-Cluster validation, shared by both machine kinds. |

API group is `infrastructure.cluster.x-k8s.io/v1alpha1`.

### Bootstrap (identity-mint self-join)

`renderLinuxBootstrapScript` produces the self-join — install containerd/kubelet
from the pkgs.k8s.io channel, drop the kubelet kubeconfig (rendered from the
per-machine identity the operator mints via `EnsureNodeIdentity` → bound to
`system:node`), and start kubelet with `--register-with-taints` carrying the
CR's `nodeTaints`. Elastic Metal has no user-data channel, so after the OS
install completes the reconciler SSHes in as `ubuntu` and pipes the script to a
shell. The SSH dial uses TOFU host-key verification (shared
`macos-host-bootstrap.HostKeyState`): the host fingerprint is pinned in the
per-machine bootstrap Secret on first contact and verified on every retry.

### PN as a VLAN

Elastic Metal delivers the Private Network as a tagged VLAN on the primary NIC,
not an auto-DHCP'd second interface, so the reconciler attaches the PN, resolves
the VLAN tag (`EnsurePrivateNetwork`, requeues while Scaleway lags stamping it),
and the self-join script materialises the VLAN interface before kubelet starts.

### Scaleway API (`internal/scaleway`)

Alongside the Apple Silicon `AdoptFromPool`, the client has baremetal methods
(`CreateServer`, `FindServerByName`, `DeleteServer`, `EnsurePrivateNetwork`,
`GetServer`, `PrivateNetworkIP`, install-status helpers). The Go SDK in `go.mod`
covers `baremetal`, `vpc`, and `ipam`.

## Declarative wiring (Helm)

`infra/helm/tuist/templates/kura-fleet.yaml` renders, per env:

- a `ScalewayElasticMetalMachineTemplate` (`offerType`, `zone`, `os`, PN id, and
  `nodeTaints` = `tuist.dev/runner-cache=true:NoSchedule`);
- a `MachineDeployment` whose `bootstrap.dataSecretName` is the shared
  `noop-bootstrap` secret (no kubeadm join), `infrastructureRef` → the
  MachineTemplate, `replicas` from `.Values.kuraFleet.replicas`, and the Machine
  label `node.cluster.x-k8s.io/pool=kura-scw-fr-par` that CAPI propagates to the
  Node.

Per-env values live in `values-managed-<env>.yaml`: staging/canary
`EM-B220E-NVME`, production `EM-I220E`. The Private Network is named
(`privateNetworkName`, default `tuist-runner-cache`) rather than referenced by
UUID; the operator find-or-creates it per env, and the macOS fleet attaches to
the same name so both share one PN.
The taint rides `nodeTaints` (the reconciler passes it to the kubelet's
`--register-with-taints`); the pool label rides CAPI Machine→Node propagation.
No ClusterClass change — the Scaleway fleet is a standalone MachineDeployment
attached to the caph cluster, not a ClusterClass topology entry.

## Cross-cutting

- **apiserver `--kubelet-preferred-address-types`** carries `InternalIP`,
  delivered as a ClusterClass `kubeletPreferredAddressTypes` variable + patch.
  The default equals the current value, so applying it is a no-op; each env
  flips the variable to insert `InternalIP` on its own control-plane rollout.
  Cross-cloud nodes (Elastic Metal + macOS PN) report a reachable `InternalIP`
  but no `ExternalIP` and a Hostname the Hetzner apiserver can't resolve, so
  this is what lets the apiserver reach those kubelets for `logs`/`exec`.
- **Node replacement**: on Machine delete the provider deletes the Node object
  and reaps the PVCs bound to node-local PVs pinned to the departing box's
  hostname (`deleteNodeLocalPVCs`, called from each Linux provider's
  `reconcileDelete`). A node-local (local-NVMe) PV can't follow the box, so
  without this the replacement node's cache StatefulSet would stay Pending on the
  old node's unbindable PV; deleting the orphaned PVC lets it provision a fresh
  volume. The cache re-warms from the per-account-CA mesh (local NVMe isn't
  re-attachable like block storage); the durable mesh state is per-account and
  rebuilds, so there's no data loss.
- **Naming**: the provider binary/repo is `...-applesilicon`; with a Linux kind
  alongside Apple Silicon that's a misnomer, kept for now (a rename is broad
  churn: image, chart, RBAC, CRD group). Revisit if it keeps growing.
- **IAM**: each env's provider key carries `ElasticMetalFullAccess` (list /
  order / release the EM server), `PrivateNetworksFullAccess` + `IPAMReadOnly`
  (attach the PN and read its address), plus `AppleSiliconFullAccess` +
  `SSHKeysFullAccess` shared with the macOS fleet. `ElasticMetalFullAccess` is
  the easy one to miss: it's a separate Scaleway product from Apple Silicon, so
  a key with `AppleSiliconFullAccess` but not `ElasticMetalFullAccess` 403s on
  the EM reconciler's first `list elastic metal servers` call and never orders a
  node.

## End-to-end path

The `kura-fleet` MachineDeployment orders the EM box; the controller attaches
the PN as a VLAN and resolves it, the SSH self-join registers the node, and it
reaches Ready with providerID + `tuist.dev/pn-ipv4` + pool label + taint. The
runner-cache pod schedules onto it (local-NVMe PVC), meshes with the account's
Hetzner peers, and macOS runners reach the cache over the PN NodePort (exercised
by `runners-staging-smoke.yml`). The orphan reclaimer releases servers left
behind by failed provisions.

## Bringing up the macOS runner cache in an environment

`kuraFleet.enabled` provisions the EM node, but routing the Mac fleet's build
cache to it needs three gates flipped together in that env's values (see
`values-managed-{staging,canary,production}.yaml`):

1. advertise the macOS-serving private region: add `scw-fr-par-runners` to
   `TUIST_KURA_AVAILABLE_REGIONS`;
2. enable macOS cluster-network dispatch:
   `TUIST_RUNNERS_CLUSTER_NETWORK_PLATFORMS=linux,macos`;
3. attach the minis to the PN: `macosFleet.vmCachePrivateNetwork.{name,cidr}`.

One prerequisite is not in the deploy pipeline and must exist per env, or
dispatch returns no endpoint and builds fall back to the public cache (the
cutover degrades rather than breaks while it is missing):

- **A Private Network named `tuist-runner-cache`** in the env's Scaleway
  project. The operator find-or-creates it from `172.16.0.0/22`, but rename the
  env's existing runner-cache PN to that name so the EM node and the minis share
  the one you already set up rather than landing on a fresh one.

The `scw-local-nvme` StorageClass the cache PVCs bind against now ships with the
chart (`templates/kura-fleet-storage.yaml`, gated on the same `kuraFleet.enabled`
flag), so it no longer has to be applied by hand. The provider IAM key also needs
`ElasticMetalFullAccess` (see the IAM note above), without which the EM order
403s.

## Out of scope

- Renaming the provider.
- Upstream CAPS adoption.
- Managed-Kubernetes (Kapsule) pools.

## Remaining gaps

- **Storage-class migration isn't declarative** — *fixed*: a StatefulSet's
  `volumeClaimTemplates` are immutable, so a live KuraInstance's `storageClassName`
  change (e.g. `scw-bssd`→`scw-local-nvme`) can't update in place. The
  kura-controller's `reconcileStaleDataStorage` now detects a data PVC whose
  storage class no longer matches the CR (or a volume orphaned by a reprovisioned
  node) and recreates the StatefulSet with a fresh PVC. The cache is regenerable,
  so the recreate is non-disruptive.

- **Runner-cache readiness has no alert**: the private runner-cache regions
  expose no public endpoint, so they skip the public HTTPS readiness probe and
  are the instances with the *least* monitoring — a storage wedge (both gaps
  above) ran ~34h unnoticed. There is no alert-as-code in this repo (rules live
  in Grafana Cloud), so add one there against the remote-written
  kube-state-metrics. The driving metrics already ship (the chart's default KSM
  allow-list keeps `kube_statefulset_*`); only the Grafana Cloud rule is missing:

  ```promql
  # KuraRunnerCacheNotReady (severity: warning, for: 15m)
  # A per-account Kura StatefulSet has been short of ready replicas for 15m.
  kube_statefulset_status_replicas_ready{namespace="kura"}
    < kube_statefulset_replicas{namespace="kura"}
  ```

  The standard kube-prometheus `KubeStatefulSetReplicasMismatch` alert would also
  catch this if it is enabled and routed for the `kura` namespace — it was not,
  which is why the wedge was silent. Enabling/routing that is the lighter path;
  the scoped rule above is the explicit alternative.
- **Stuck-`:failed` runner-cache nodes aren't auto-retried** server-side
  (`nodes_to_retry` only self-heals servers with `current_image_tag == nil`),
  so a node that deployed then failed needs an operator reset.
- **First-connect SSH window**: TOFU pins on first contact, but Scaleway
  baremetal exposes no host key to pin out of band, so the very first dial is
  trust-on-first-use. Strictly stronger than blind trust and consistent with the
  rest of the provider; revisit if Scaleway surfaces a host key.
- **Image vs in-line install**: the self-join installs containerd + kubelet on a
  stock image (slower, network-dependent joins). Bake a Scaleway image if join
  time/reliability becomes a problem.
