# Design: declarative Scaleway Linux nodes (Instance + Elastic Metal) via the in-house provider

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

## Why extend this provider (not upstream CAPS, not cloud-init)

- **Upstream `cluster-api-provider-scaleway` does not fit.** It models a
  Scaleway-infra cluster (`ScalewayCluster` owns the PrivateNetwork and control
  plane). Our clusters are `HetznerCluster` (caph), single infrastructure
  provider, and the mesh/NodePort design requires the kura node to be a
  **worker in the existing cluster** — not a separate Scaleway cluster. CAPI
  doesn't let a CAPS worker pool attach to a Hetzner-infra cluster.
- **This provider already solves exactly that** for Apple Silicon: a stub
  `ScalewayAppleSiliconCluster` (only there to satisfy CAPI parent-Cluster
  validation) + a self-join that registers the machine into the existing caph
  cluster as a worker, surfaced through the standard Machine/MachineDeployment
  shape. The Linux kinds are the same pattern with a different provisioning
  call and bootstrap-delivery channel.
- **A committed cloud-init script** would make the join reproducible but gives
  no lifecycle (scale/replace/heal) and no CAPI integration — strictly weaker
  than what the Hetzner pool and the macOS fleets already have.

## Architecture

The provider has **three** machine kinds, sharing the stub cluster, the CAPI
Machine/MachineDeployment shape, the SSH/self-join bootstrap, and the orphan
reclaimer:

| Kind | Server | Bootstrap delivery | Cache storage |
|---|---|---|---|
| `ScalewayAppleSiliconMachine` | Mac mini (Tart) | SSH | — |
| `ScalewayInstanceMachine` | Scaleway Instance (x86/ARM, e.g. PRO2-S) | cloud-init user-data | SBS (`scw-bssd`) |
| `ScalewayElasticMetalMachine` | Scaleway Elastic Metal (bare metal) | SSH (no user-data channel) | local NVMe (`scw-local-nvme`) |

All three **mint a per-machine kubelet identity and render a self-join** — they
do **not** use the CAPI kubeadm bootstrap provider. This cluster's control
plane is externally managed (caph/Hetzner), so there is no kubeadm join
endpoint for workers: the operator mints a node ServiceAccount token + CA,
renders a kubelet kubeconfig into a Linux self-join script (install
containerd/kubelet, write the kubeconfig, register with
`--register-with-taints`), and the node joins with that identity (bound to
`system:node`). The MachineDeployment therefore carries a `noop-bootstrap`
secret, exactly like the macOS fleets — there is no `KubeadmConfigTemplate`.

**The kura runner-cache node runs on Elastic Metal, not a PRO2-S Instance.** A
PRO2-S PN is token-bucketed to ~1.5 Gbit/s under sustained load and `scw-bssd`
caps disk at ~4 Gbit/s, while an `EM-B220E` gives ~10 Gbit/s flat PN and local
NVMe at ~27 Gbit/s — cheaper, with more RAM for warm-set page cache. The
`ScalewayInstanceMachine` kind remains for any future Instance-class Linux pool.

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

The Instance reconciler is the same shape minus the OS-install wait, delivering
the self-join as cloud-init `user_data` instead of over SSH, and using SBS
instead of local NVMe.

### CRDs

| Kind | Purpose |
|---|---|
| `ScalewayInstanceMachine(Template)` | One Scaleway Instance. Spec: `commercialType`, `zone`, `image`, `privateNetworkID`, `nodeTaints` (+ status-managed `providerID`). |
| `ScalewayElasticMetalMachine(Template)` | One Scaleway Elastic Metal server. Spec: `offerType`, `zone`, `os`, `privateNetworkID`, `nodeTaints`; status: `providerID`, `serverID`, `privateNetworkVLAN`, `phase`. |
| (reuse) `ScalewayAppleSiliconCluster` | Generic stub satisfying CAPI parent-Cluster validation, shared by all machine kinds. |

API group is `infrastructure.cluster.x-k8s.io/v1alpha1`.

### Bootstrap (identity-mint self-join)

`renderLinuxBootstrapScript` produces the same Linux self-join for both Linux
kinds — install containerd/kubelet from the pkgs.k8s.io channel, drop the
kubelet kubeconfig (rendered from the per-machine identity the operator minted
via `EnsureNodeIdentity` → bound to `system:node`), and start kubelet with
`--register-with-taints` carrying the CR's `nodeTaints`. Only the delivery
differs:

- **Instance**: handed to the Instance API as cloud-init `user_data`; the node
  self-joins on first boot.
- **Elastic Metal**: there is no user-data channel, so after the OS install
  completes the reconciler SSHes in as `ubuntu` and pipes the script to a
  shell. The SSH dial uses TOFU host-key verification (shared
  `macos-host-bootstrap.HostKeyState`): the host fingerprint is pinned in the
  per-machine bootstrap Secret on first contact and verified on every retry.

### PN as a VLAN (Elastic Metal only)

Elastic Metal delivers the Private Network as a tagged VLAN on the primary NIC,
not an auto-DHCP'd second interface, so the reconciler attaches the PN, resolves
the VLAN tag (`EnsurePrivateNetwork`, requeues while Scaleway lags stamping it),
and the self-join script materialises the VLAN interface before kubelet starts.

### Scaleway API (`internal/scaleway`)

Alongside the Apple Silicon `AdoptFromPool`, the client has baremetal methods
(`CreateServer`, `FindServerByName`, `DeleteServer`, `EnsurePrivateNetwork`,
`GetServer`, `PrivateNetworkIP`, install-status helpers) and the Instance-API
equivalents. The Go SDK in `go.mod` covers `baremetal`, `instance`, `vpc`, and
`ipam`.

## Declarative wiring (Helm)

`infra/helm/tuist/templates/kura-fleet.yaml` renders, per env:

- a MachineTemplate — `ScalewayElasticMetalMachineTemplate` or
  `ScalewayInstanceMachineTemplate`, selected by `kuraFleet.machine.kind`
  (`offerType`/`commercialType`, `zone`, `os`/`image`, PN id, and `nodeTaints`
  = `tuist.dev/runner-cache=true:NoSchedule`);
- a `MachineDeployment` whose `bootstrap.dataSecretName` is the shared
  `noop-bootstrap` secret (no kubeadm join), `infrastructureRef` → the
  MachineTemplate, `replicas` from `.Values.kuraFleet.replicas`, and the
  Machine label `node.cluster.x-k8s.io/pool=kura-scw-fr-par` that CAPI
  propagates to the Node.

Per-env values live in `values-managed-<env>.yaml`: staging/canary
`EM-B220E-NVME`, production `EM-I220E`, each with its own `privateNetworkID`.
The taint rides `nodeTaints` (the reconciler passes it to the kubelet's
`--register-with-taints`); the pool label rides CAPI Machine→Node propagation.
No ClusterClass change — the Scaleway fleets are standalone MachineDeployments
attached to the caph cluster, not ClusterClass topology entries.

## Cross-cutting

- **apiserver `--kubelet-preferred-address-types`** carries `InternalIP`,
  delivered as a ClusterClass `kubeletPreferredAddressTypes` variable + patch.
  The default equals the current value, so applying it is a no-op; each env
  flips the variable to insert `InternalIP` on its own control-plane rollout.
  Cross-cloud nodes (Elastic Metal + macOS PN) report a reachable `InternalIP`
  but no `ExternalIP` and a Hostname the Hetzner apiserver can't resolve, so
  this is what lets the apiserver reach those kubelets for `logs`/`exec`.
- **Node replacement**: CAPI cordons and drains a removed Machine. A
  replacement EM node re-warms its cache (local NVMe isn't re-attachable like
  SBS) and the per-account-CA mesh re-bootstraps onto it; the durable mesh
  state is per-account and rebuilds, so there's no data loss.
- **Naming**: the provider binary/repo is `...-applesilicon`; with three
  machine kinds that's a misnomer, kept for now (a rename is broad churn:
  image, chart, RBAC, CRD group). Revisit if it keeps growing.
- **IAM**: each env's provider key carries `PrivateNetworksFullAccess` +
  `IPAMReadOnly` (+ BlockStorage for SBS-backed Instance pools).

## End-to-end path

The `kura-fleet` MachineDeployment orders the EM box; the controller attaches
the PN as a VLAN and resolves it, the SSH self-join registers the node, and it
reaches Ready with providerID + `tuist.dev/pn-ipv4` + pool label + taint. The
runner-cache pod schedules onto it (local-NVMe PVC), meshes with the account's
Hetzner peers, and macOS runners reach the cache over the PN NodePort
(exercised by `runners-staging-smoke.yml`). The orphan reclaimer releases
servers left behind by failed provisions.

## Out of scope

- Renaming the provider.
- Upstream CAPS adoption.
- Managed-Kubernetes (Kapsule) pools.

## Remaining gaps

- **Storage-class migration isn't declarative**: a StatefulSet's
  `volumeClaimTemplates` are immutable and the controller updates in place, so
  changing a live KuraInstance's `storageClassName` (e.g. `scw-bssd`→
  `scw-local-nvme`) silently no-ops and needs a manual delete+recreate; the
  controller should detect the change and recreate.
- **Stuck-`:failed` runner-cache nodes aren't auto-retried** server-side
  (`nodes_to_retry` only self-heals servers with `current_image_tag == nil`),
  so a node that deployed then failed needs an operator reset.
- **First-connect SSH window (Elastic Metal)**: TOFU pins on first contact, but
  Scaleway baremetal exposes no host key to pin out of band, so the very first
  dial is trust-on-first-use. Strictly stronger than blind trust and consistent
  with the rest of the provider; revisit if Scaleway surfaces a host key.
- **Image vs `preKubeadmCommands`-style install**: the self-join installs
  containerd + kubelet on a stock image (slower, network-dependent joins). Bake
  a Scaleway image if join time/reliability becomes a problem.
