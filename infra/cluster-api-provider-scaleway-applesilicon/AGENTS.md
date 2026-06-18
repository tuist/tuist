# cluster-api-provider-scaleway-applesilicon

Cluster API infrastructure provider that joins Scaleway nodes as
workers into the existing caph/Hetzner clusters, surfaced through
CAPI's standard Machine/MachineDeployment shape. It manages two
machine kinds:

- `ScalewayAppleSiliconMachine` — Mac minis (Tart), SSH-bootstrapped
  with tart-cri/tart-kubelet.
- `ScalewayElasticMetalMachine` — Linux bare metal (e.g. the
  `kura-scw-fr-par` runner-cache node), SSH self-join (Elastic Metal
  has no user-data channel).

Both order/release via Scaleway's API and bootstrap with an
operator-minted kubelet identity + SSH self-join, then wait for
`Node.Ready`. The Elastic Metal kind binds that identity to
`system:node`; Apple Silicon uses the `tart-kubelet` role. The Elastic
Metal kind is designed in `docs/scaleway-elastic-metal-support.md`; the
sections below detail the Apple Silicon kind.

## CRDs

| Kind | Purpose |
|---|---|
| `ScalewayAppleSiliconMachine` | One Mac mini. Has the Scaleway server type, zone, OS, per-host pod CIDR, fleet name (ties Machines on the same fleet to one shared SSH key), and kubelet version. SSH and bootstrap material are operator-managed — no Secret refs in the spec. |
| `ScalewayAppleSiliconMachineTemplate` | Template MachineDeployments / MachineSets clone from. |
| `ScalewayElasticMetalMachine` (+ `…Template`) | One Scaleway Elastic Metal server (Linux bare metal): offer type, zone, OS, PN id, node taints. SSH self-join (no user-data channel); local-NVMe (`scw-local-nvme`) cache. |
| `ScalewayAppleSiliconCluster` | Cluster-level stub (CAPI core requires it for the parent Cluster to validate). Sets `Status.Ready=true` once it exists. Shared by all machine kinds. |

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
 │   │   ├── 1. Stage: Adopting                 │
 │   │   │      scaleway.AdoptFromPool(...)     │
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

Two auxiliary controllers run alongside it:

- **OrphanReclaimer** (`controllers/orphan_reclaimer.go`) — a
  leader-gated periodic sweep that returns Scaleway hosts which were
  claimed by the controller but whose CR is gone (a legacy CR that
  skipped release, a force-delete that bypassed the finalizer, a crash
  mid-claim) back to the adopt pool, so a strand can't silently drain
  the pool and keep billing under Apple's 24h floor. The per-Machine
  delete path only covers what reaches it; the sweep is the convergent
  backstop. A host is left untouched unless it is certainly
  ours-but-unowned — not in the pool, not mid-adoption, and named after
  no live CR (the claim renames a pool host to its CR's name, so a live
  CR name is the authoritative "owned" signal). Active reclaim is gated
  on a claim-name prefix; report-only otherwise. Exports the
  `scaleway_orphan_servers` gauge. Enabled by
  `macosFleet.orphanReclaim.poolPrefix`, which also serves as the
  delete path's pool-prefix fallback for legacy CRs.
- **FleetSpreadReconciler** (`controllers/fleetspread_controller.go`) —
  re-rolls a target Deployment when the Ready Mac mini set changes so
  Pods spread across newly-joined hosts.

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
│   ├── scalewayapplesiliconcluster_controller.go
│   ├── fleetspread_controller.go
│   └── orphan_reclaimer.go
├── internal/
│   ├── scaleway/   # Scaleway SDK wrapper
│   └── bootstrap/  # SSH-driven kubelet/tart-cri install
├── cmd/manager/    # controller-manager entry point
├── config/
│   └── rbac/       # ClusterRole for the manager
├── Dockerfile
└── AGENTS.md (this file)
```

CRDs live in [`infra/helm/tuist/crds/`](../helm/tuist/crds/) so Helm
installs them automatically on first `helm install` (Helm 3 ignores
the `crds/` directory on upgrades, which is what we want — CRD
schema changes go through a deliberate `kubectl apply` rather than
piggybacking on routine deploys).

## Operator UX: one Secret in 1Password

The only thing an operator manages by hand is **Scaleway IAM
credentials in 1Password**. The chart's `ExternalSecret` template
syncs those into a cluster Secret automatically; everything else is
operator-managed:

| Secret | Source | Purpose |
|---|---|---|
| `<release>-capi-scaleway-applesilicon` | 1Password → ESO | Scaleway API auth for the operator. Three fields: `access-key`, `secret-key`, `project-id`. |
| `<fleet-name>-ssh` | **Generated by the operator on first reconcile** | Per-fleet Ed25519 SSH keypair. The operator registers the public half with Scaleway via the IAM API, stores the private half here. The chart doesn't reference this Secret directly. |
| Bootstrap material | **Minted by the operator on each Machine reconcile** | API server URL + CA cert read from the operator pod's in-cluster service-account context. Bootstrap token created as a `bootstrap.kubernetes.io/token` Secret in `kube-system` with 24h TTL. No 1Password entry, no manual rotation. |

Day-1 operator runbook:

1. **Drop Scaleway IAM creds in 1Password.** One item per env in the
   matching `tuist-k8s-<env>` vault — same convention as
   `MASTER_KEY`, `PROCESSOR_DATABASE_PASSWORD`, and
   `KUBEADM_BOOTSTRAP_TOKEN`:

   - `op://tuist-k8s-staging/SCALEWAY_API/{access-key,secret-key,project-id}`
   - `op://tuist-k8s-canary/SCALEWAY_API/{access-key,secret-key,project-id}`
   - `op://tuist-k8s-production/SCALEWAY_API/{access-key,secret-key,project-id}`

   Each env gets its own Scaleway IAM application scoped to that
   cluster's needs; a leaked staging key rotates without disrupting
   production. The IAM policy attached to that application needs
   exactly two permission sets:

   - `AppleSiliconFullAccess` (project scope) — order/release Mac
     minis, list server types and OS images.
   - `SSHKeysFullAccess` (project scope) — register the per-fleet
     Ed25519 public key the operator generates on first reconcile.
     **Do not use `IAMManager`** despite the name suggesting it
     covers SSH keys; Scaleway gates `ssh_key` write under
     `SSHKeysFullAccess` specifically.

   Each cluster's pre-configured `ClusterSecretStore "onepassword"` is
   already scoped to the right vault, so the chart references the
   bare item name and ESO picks the correct vault automatically.

2. **Set the chart values** (managed cloud — defaults shown):

   ```yaml
   macosFleet:
     enabled: true
     controlPlane:
       host: api.tuist.dev
     scaleway:
       externalSecrets:
         item: SCALEWAY_API   # bare item name; vault from ClusterSecretStore
   ```

3. **Deploy.**

   ```bash
   helm upgrade tuist infra/helm/tuist -f ...
   ```

That's it. The MachineDeployment's `replicas` field controls the
fleet size from there. No `kubectl create secret` calls.

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
CAPI core picks the most-recently-created Machines for deletion. The
controller renames the host back into the pool namespace
(`<poolPrefix><uuid>`) and triggers a Scaleway OS reinstall; the
host stays alive, returns to factory-default state, and becomes
eligible for the next adoption once Scaleway flips it back to
`Delivered + Ready`. The 24h Apple licensing floor stays in
operator-owned territory — you keep paying for capacity you already
pre-ordered until you decide to release it via the Scaleway console.

### Replace a wedged host
```bash
kubectl delete machine <machine-name>
```
The MachineSet immediately creates a replacement; the old Mac mini
is renamed back into the pool, reinstalled, and re-eligible for the
next adoption. The replacement Machine will adopt either this host
(post-reinstall) or any other available pool host, whichever
Scaleway returns to `Ready` first.

If the host is genuinely broken (kernel panic loop, hardware fault,
retired SKU) and must not be re-adopted, release it via the
Scaleway console before deleting the Machine — the controller has
no physical-terminate path.

### Investigate a failure
```bash
kubectl describe scalewayapplesiliconmachine <name>
# Check Conditions (Provisioned / Bootstrapped) and Events (lifecycle
# transitions, drift-loop attempts, terminal-failure transitions)
kubectl get events --field-selector involvedObject.kind=ScalewayAppleSiliconMachine
```

### Unstick a host whose CAPI bootstrap is failing on sudo

Symptom: `kubectl describe scalewayapplesiliconmachine <name>` shows
`BootstrappedCondition=False` with a message containing `sudo:`
errors, or the bootstrap looping on early SSH steps after Stage 1
provisioning succeeded.

Root cause is almost always: the operator-stored `m1` password in
the bootstrap Secret has drifted from what's actually set on the
host (Scaleway-issued password rotated, host got reinstalled,
controller crashed mid-store, etc.). CAPI's bootstrap can SSH in
(fleet key works) but can't `sudo -S` to install
`/etc/sudoers.d/m1-nopasswd`, so every subsequent step fails.

Recovery: run `prepare-fleet-host` to install the sudoers entry
out-of-band using the operator-provided current password.

```bash
# Get the live m1 password from Scaleway:
scw apple-silicon server get <server-id> zone=<zone> -o json \
  | jq -r .vnc_url
# (Password is between `m1:` and `@` in the vnc:// URL.)

# Then:
mise run k8s:prepare-fleet-host <env> <fleet-name> <host-ip>
```

The script SSHes in with the fleet key (which Scaleway auto-injects
at first boot via project-level keys), prompts for the password,
installs `/etc/sudoers.d/m1-nopasswd` and `/etc/kcpassword` /
`autoLoginUser`. After that, CAPI's bootstrap proceeds without ever
needing a correct password in its Secret.

If the fleet pubkey isn't on the host (rare — Scaleway didn't
inject), the script's SSH probe fails with `Permission denied`.
Recover by VNC'ing into the host and pasting the pubkey into
`~/.ssh/scw_authorized_keys`, then re-running the script. Don't
bother with `~/.ssh/authorized_keys` — Scaleway's `sshd_config`
reads both files, but `scw_authorized_keys` is the one the
first-boot injection writes to, so anything you add there
mirrors the auto-inject convention.

### Detach a CR without releasing its Scaleway host

Reserved for recovering from a duplicate-claim state (multiple CRs
ended up bound to the same Scaleway server) or for hand-rolling a CR
off a host that's actively serving traffic. The standard
`kubectl delete machine <name>` path always calls Scaleway's
`ReleaseToPool` against the bound host (rename + reinstall), which
is the wrong move when the host is shared OR you want to keep its
current state intact.

The reconciler skips Scaleway release whenever `status.serverID` is
empty at delete time. But clearing `status.serverID` before the
delete races the reconcile loop — it sees the empty serverID and
runs `AdoptFromPool` against the pool. To latch the loop off
during cleanup, set the CAPI `cluster.x-k8s.io/paused` annotation
on the CR *before* clearing status:

```bash
NS=tuist
NAME=tuist-tuist-runners-fleet-mndbc-xxxxx

# 1. Latch the reconciler off — annotate FIRST. Until this lands,
#    every subsequent patch is racing.
kubectl -n "$NS" annotate scalewayapplesiliconmachine "$NAME" \
  cluster.x-k8s.io/paused=true --overwrite

# 2. Clear status.serverID (so reconcileDelete skips ReleaseToPool)
#    and spec.providerID (so CAPI core doesn't keep referencing
#    the abandoned binding).
kubectl -n "$NS" patch scalewayapplesiliconmachine "$NAME" \
  --subresource=status --type=merge -p '{"status":{"serverID":""}}'
kubectl -n "$NS" patch scalewayapplesiliconmachine "$NAME" \
  --type=merge -p '{"spec":{"providerID":null}}'

# 3. Delete the parent Machine. The pause annotation only latches
#    reconcileNormal — reconcileDelete still runs on
#    DeletionTimestamp regardless, observes the empty serverID,
#    and skips the Scaleway release.
kubectl -n "$NS" delete machine "$NAME"
```

The MachineSet will create a replacement CR with a fresh suffix,
which adopts an unclaimed pool host on its next reconcile.

After cleanup, if you renamed the original Scaleway host
out-of-band (e.g. during a duplicate-claim untangling), rename it
back so the pool prefix matches and a future `AdoptFromPool` can
pick it up:

```bash
scw apple-silicon server update <id> zone=<zone> name=tuist-pool-...
```
