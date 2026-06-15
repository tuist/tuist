# Design: declarative Scaleway Instance (Linux) nodes via the in-house provider

Status: proposed. Owner: TBD. Tracking the kura runner-cache node
(`kura-scw-fr-par`), today a hand-joined PRO2-S.

## Problem

The Scaleway fr-par kura runner-cache node (`51.15.216.34`, PRO2-S) was
`kubeadm`-joined to the staging cluster out-of-band (cloud-init, labels
and `scaleway://` providerID applied by hand). Nothing in the repo
manages it, so:

- its node labels (`node.cluster.x-k8s.io/pool=kura-scw-fr-par`,
  `tuist.dev/pn-ipv4`) and the wanted `tuist.dev/runner-cache:NoSchedule`
  taint have no durable, reviewable home — re-joining or replacing the
  node loses them;
- there is no lifecycle (scale, replace, heal) the way the Hetzner kura
  pool gets from CAPI;
- prod can't be stood up reproducibly.

Goal: bring this node (and a future prod pool) under declarative CAPI
management, in the **same** cluster as the Hetzner nodes, with labels +
taint + PN attachment + providerID all declared in-repo.

## Why extend this provider (not upstream CAPS, not cloud-init)

- **Upstream `cluster-api-provider-scaleway` does not fit.** It models a
  Scaleway-infra cluster (`ScalewayCluster` owns the PrivateNetwork and
  control plane). Our clusters are `HetznerCluster` (caph), single
  infrastructure provider, and the mesh/NodePort design requires the kura
  node to be a **worker in the existing staging cluster** — not a
  separate Scaleway cluster. CAPI doesn't let a CAPS worker pool attach
  to a Hetzner-infra cluster.
- **This provider already solves exactly that** for Apple Silicon: a stub
  `ScalewayAppleSiliconCluster` (only there to satisfy CAPI parent-Cluster
  validation) + SSH bootstrap that joins the machine to the existing caph
  cluster as a worker, surfaced through the standard
  Machine/MachineDeployment shape. Linux Instances are the same pattern
  with a different provisioning call.
- **A committed cloud-init script** would make the join reproducible but
  gives no lifecycle (scale/replace/heal) and no CAPI integration — a
  strictly weaker end state than what the Hetzner pool and the macOS
  fleets already have.

## Architecture

Add a second machine kind to this provider for regular Scaleway
**Instances** (x86/ARM Linux servers via the Instance API), alongside the
Apple Silicon kind. Reuse everything that isn't provisioning-specific: the
stub cluster, the CAPI Machine/MachineDeployment shape, the SSH bootstrap
runner, the orphan reclaimer pattern.

```
 ScalewayInstanceMachine CR (one PRO2-S)
        │
        ▼
 capi-scaleway-applesilicon manager  (rename deferred; see Naming)
   └── ScalewayInstanceMachineReconciler
        ├── 1. WaitBootstrap  read Machine.Spec.Bootstrap.DataSecretName
        │                     (CAPI kubeadm bootstrap provider rendered the
        │                      join cloud-init: token, CA hash, endpoint,
        │                      nodeRegistration labels + taints)
        ├── 2. Creating       scaleway.CreateInstance(type, zone, image),
        │                     cloud-init user-data = the bootstrap secret;
        │                     attach PN; power on → providerID
        └── 3. Ready          poll Node until Ready, then patch the dynamic
                              `tuist.dev/pn-ipv4` label onto it
```

Bootstrap is **not** SSH/token-managed by this provider (the Apple Silicon
kind does that because Macs can't kubeadm-join). The Linux instance uses the
standard CAPI contract: a `KubeadmConfigTemplate` drives the kubeadm
bootstrap provider, which renders the join cloud-init into the Machine's
bootstrap data Secret; the reconciler just hands that to the instance as
cloud-init user-data and the node self-joins.

### CRDs

| Kind | Purpose |
|---|---|
| `ScalewayInstanceMachine` | One Scaleway Instance. Spec: `commercialType` (e.g. `PRO2-S`), `zone`, `image`, `rootVolumeGB`, `privateNetworkID`, `nodeLabels`, `nodeTaints`, `kubeletVersion`, `providerID` (status-managed). |
| `ScalewayInstanceMachineTemplate` | Template the MachineDeployment clones from. |
| (reuse) `ScalewayAppleSiliconCluster` | Already a generic stub. Either reuse as-is, or rename to a neutral `ScalewayCluster`-stub kind shared by both machine kinds (deferred — cosmetic). |

API group stays `infrastructure.cluster.x-k8s.io/v1alpha1`.

### Reconciler stages (idempotent)

1. **WaitForBootstrap** — block until `Machine.Spec.Bootstrap.DataSecretName`
   is set; the CAPI kubeadm bootstrap provider populates it with the join
   cloud-init (token, CA hash, join endpoint, and the
   `nodeRegistration` static labels + taints from the KubeadmConfigTemplate).
2. **Creating** — if no `providerID`, call the Scaleway **Instance API** to
   create the server (commercial type, zone, image, root volume) with the
   bootstrap secret as cloud-init `user_data`, attach the configured
   PrivateNetwork (CreatePrivateNIC), power on. Persist
   `providerID = scaleway://instance/<zone>/<id>` (the same foreign
   providerID the hand-join used, so hcloud CCM never reaps the node).
   Idempotent via a name/tag lookup so a controller restart re-finds the
   server instead of creating a duplicate.
3. **Ready** — poll the `Node` until `Ready`. The pool label
   (`node.cluster.x-k8s.io/pool`) arrives via CAPI Machine→Node label
   propagation; the taint via `nodeRegistration.taints`. Patch the dynamic
   `tuist.dev/pn-ipv4` label (read from IPAM for the instance's PN NIC)
   onto the Node here — kubelet can't self-set `tuist.dev/*` labels under
   NodeRestriction and CAPI doesn't propagate that prefix.

Deletion: drain (CAPI handles cordon/drain via the Machine), then Instance
API delete + PN detach + volume cleanup. Add the Instance kind to the
OrphanReclaimer sweep.

### Scaleway API additions (`internal/scaleway`)

The client today only has Apple Silicon `AdoptFromPool`. Add Instance-API
methods: `CreateInstance`, `DeleteInstance`, `AttachPrivateNetwork`,
`GetInstance` (for idempotent rediscovery by claim tag). The Go SDK
already in `go.mod` covers `instance` + `vpc`.

## Declarative wiring (Helm, mirrors `macos-fleet.yaml`)

New chart template `kura-fleet.yaml` rendering:

- a `ScalewayInstanceMachineTemplate` (commercialType, zone, image, PN id —
  pure infra);
- a `KubeadmConfigTemplate` carrying the join `joinConfiguration`:
  `nodeRegistration.taints` = `tuist.dev/runner-cache=true:NoSchedule`,
  `nodeRegistration.kubeletExtraArgs` as needed, and `preKubeadmCommands`
  to install containerd + kubeadm/kubelet on the base image (or bake an
  image later);
- a `MachineDeployment` (`clusterName` = the capi cluster,
  `bootstrap.configRef` → the KubeadmConfigTemplate, `infrastructureRef` →
  the ScalewayInstanceMachineTemplate, `replicas` from
  `.Values.kuraFleet.replicas`, and the Machine `metadata.labels`
  `node.cluster.x-k8s.io/pool=kura-scw-fr-par` that CAPI propagates to the
  Node).

So the taint + pool label this PR's toleration targets become declarative
here, with per-env values (`scw-fr-par` PN id, replicas) in
`values-managed-<env>.yaml`. No ClusterClass change — the Scaleway fleets
are standalone MachineDeployments attached to the caph cluster, not
ClusterClass topology entries. (The macOS fleets use a `noop-bootstrap`
secret because they don't kubeadm-join; the Linux pool uses a real kubeadm
bootstrap config instead.)

## Cross-cutting items

- **apiserver `--kubelet-preferred-address-types`** has no `InternalIP`,
  so today the node is named by its public IP. For a clean managed node
  this should be fixed via the ClusterClass control-plane config (adds
  `InternalIP`), a CP rollout across envs — already a tracked follow-up,
  do it before/with this so managed nodes get sane names.
- **Migration of the live node**: once the managed pool provisions a
  fresh node, cordon + drain the hand-joined `51.15.216.34`, delete it,
  and let the kura runner-cache pods reschedule onto the managed node
  (the per-account-CA mesh re-bootstraps; brief cache-warm cost only).
  No data loss — SBS volumes are per-account and re-attach by PVC.
- **Naming**: the provider binary/repo is `...-applesilicon`. Adding a
  Linux kind makes that a misnomer. Recommend keeping the name for now
  (a rename is broad churn: image, chart, RBAC, CRD group) and noting it;
  revisit if/when a third machine kind lands.
- **IAM**: reuse the provider's existing Scaleway credentials; Instance +
  VPC scopes may need adding to the IAM policy used for Apple Silicon.

## Phasing

1. CRDs + types + deepcopy + RBAC for `ScalewayInstanceMachine(Template)`.
2. Scaleway Instance API client methods + tests.
3. `ScalewayInstanceMachineReconciler` (Creating/Bootstrapping/Ready/Delete) + Linux bootstrap steps; envtest coverage mirroring the Apple Silicon reconciler tests.
4. Helm `kura-fleet.yaml` + per-env values; ship behind `kuraFleet.enabled=false` until validated.
5. Staging: enable, let it provision a managed node, migrate off the hand-joined one, verify mesh + NodePort + taint.
6. Prod pool sizing (2× POP2-HC per the handoff) once staging is proven.

## Out of scope

- Renaming the provider.
- Upstream CAPS adoption.
- Managed-Kubernetes (Kapsule) pools.

## Risks / open questions

- **Image vs preKubeadmCommands**: first cut installs containerd +
  kubeadm/kubelet via `preKubeadmCommands` on a stock Ubuntu image (slower
  joins, network-dependent). If join time or reliability is a problem, bake
  a Scaleway image with image-builder (as the macOS fleets do for Tart) —
  deferred until the simple path is proven on staging.
- **cloud-init support**: relies on the Scaleway Instance `user_data`
  `cloud-init` key being honored by the base image's cloud-init. Standard
  for Scaleway Ubuntu images; verify on the first staging provision.
- **pn-ipv4 timing**: the PN NIC must be attached and IPAM-assigned before
  the Node-label patch; sequence create→attach-PN→poweron→(node registers)
  →read IPAM→patch label. The label is best-effort and re-patched on
  reconcile until set.
- **Idempotency without a pool**: Apple Silicon adopts from a pre-ordered
  pool; Instances are created on demand, so rediscovery keys on a
  name/tag set at create time to avoid duplicate servers after a restart.
- **Live validation**: provisioning a real Instance + join is done on
  staging by the team (the agent can't order servers); the kubeadm path is
  standard CAPI, so failures should surface as ordinary Machine/Node
  conditions rather than novel bootstrap bugs.
