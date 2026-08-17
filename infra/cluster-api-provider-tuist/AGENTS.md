# cluster-api-provider-tuist

Cluster API infrastructure provider that joins Scaleway and OVH nodes as
workers into the existing caph/Hetzner clusters, surfaced through
CAPI's standard Machine/MachineDeployment shape. It manages four
machine kinds:

- `ScalewayAppleSiliconMachine` — Mac minis (Tart), SSH-bootstrapped
  with tart-cri/tart-kubelet.
- `ScalewayElasticMetalMachine` — Scaleway Linux bare metal (e.g. the
  `kura-scw-fr-par` runner-cache node), SSH self-join (Elastic Metal
  has no user-data channel); adopts a pre-ordered box and
  **reinstalls it (wipe) on release**.
- `DediboxMachine` — Scaleway Dedibox bare metal (eu-central); adopts a
  pre-prepped box and reinstalls it (wipe) back to the pool on release.
- `OVHDedicatedMachine` — OVHcloud US bare metal (us-east / us-west);
  adopts a pre-prepped box and reinstalls it (wipe) back to the pool on
  release.

All bootstrap with an operator-minted kubelet identity + SSH self-join,
then wait for `Node.Ready`. The three Linux kinds share the
`controllers/linux` package and bind that identity to `system:node`;
Apple Silicon uses the `tart-kubelet` role. The Elastic Metal kind is
designed in `docs/scaleway-elastic-metal-support.md`; the sections below
detail the Apple Silicon kind.

## CRDs

| Kind | Purpose |
|---|---|
| `ScalewayAppleSiliconMachine` | One Mac mini. Has the Scaleway server type, zone, OS, per-host pod CIDR, fleet name (ties Machines on the same fleet to one shared SSH key), and kubelet version. SSH and bootstrap material are operator-managed — no Secret refs in the spec. |
| `ScalewayAppleSiliconMachineTemplate` | Template MachineDeployments / MachineSets clone from. |
| `ScalewayElasticMetalMachine` (+ `…Template`) | One Scaleway Elastic Metal server (Linux bare metal): offer type, zone, OS, PN id, node taints, `fleetName`. SSH self-join (no user-data channel); local-NVMe (`scw-local-nvme`) cache. Reinstall-on-release. |
| `DediboxMachine` (+ `…Template`) | One Scaleway Dedibox bare-metal server (eu-central): adopts a pre-prepped box by tag, `fleetName`. Left installed on release. |
| `OVHDedicatedMachine` (+ `…Template`) | One OVHcloud US bare-metal server (us-east / us-west): adopts a pre-prepped box by displayName prefix, `fleetName`. Left installed on release. |
| `TuistCluster` | Cluster-level stub (CAPI core requires it for the parent Cluster to validate). Sets `Status.Ready=true` once it exists. Shared by all machine kinds. |

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
 │   └── TuistClusterReconciler  │
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

Beyond first bootstrap, a drift loop re-pushes host config to already-Ready
hosts when the operator's `bootstrap.HostConfigHash` differs from the
Machine's `Status.HostConfigHash`. That hash is a fleet-wide fingerprint over
everything the operator pushes — the rendered install scripts plus the
embedded binaries (tart-kubelet, tailscale, node_exporter, tuist-log-shipper) — computed once at
startup from operator-image + fleet-config inputs with every per-host field
zeroed. So shipping a new operator image with a changed script, fleet CIDR/tag,
or re-baked binary rolls to existing hosts on the next reconcile, not only on a
tart-kubelet binary change. The re-push is zero-downtime (running Tart VMs
survive `UpdateTartKubelet`).

Terminal-failed CRs are excluded from the drift loop, but the exclusion
expires. It lifts on either a new `HostConfigHash` (compared against
`Status.FailedHostConfigHash`, not the last-applied one — a broken config never
becomes the applied one) or `--tartkubelet-terminal-retry-after` elapsing since
`Status.LastUpdateFailureTime` (default 30m). The cooldown exists because the
hash exit only covers a host that REJECTED the config, while most terminal
failures are a host the operator could not reach (`dial tcp ...:22: i/o
timeout`). Those used to stay terminal indefinitely — Ready, schedulable, still
running jobs — pinned to whatever config was last pushed, so a fleet-wide fix
could roll and silently miss them. A persistently-broken config still backs off
to one attempt budget per cooldown rather than per reconcile, so the retry cap
keeps doing its job.

The drift re-push dials the mini's **public IP first, then falls back to the
tailnet**. Once a runner mini starts booting Tart VMs its Internet Sharing /
vmnet setup filters inbound `:22` on the public interface, so a public-IP dial
times out and the fleet's roll wedges — while the same host stays reachable on
the tailnet (that's the path its metrics are scraped over). So when the public
handshake never completes (empty fingerprint = a pure connect failure, distinct
from a mid-session error), `UpdateTartKubelet` retries over the mini's
egress-Service DNS (`egressHost`, port 22 added to
`reconcileTailscaleEgressService`), which routes through the ProxyGroup — this
needs `tcp:22` in the `tag:tuist-k8s-<env>` → `tag:tuist-macmini-<env>` grant
(`infra/tailscale/acls.json`, mirrored to the admin console). The fallback sets
`SkipTailscaleInstall`: `installTailscale` stops tailscaled to swap its binary,
which over a tailnet-transported session would drop the tunnel mid-update and
strand the mini off the tailnet — so a tailnet-transported roll can't update
Tailscale itself (rare; needs the public path or re-provisioning). Public-first
means fresh/idle minis (public open, egress Service maybe not yet rewritten by
the operator) never touch the tailnet path, and by the time a mini's public
path is filtered its egress Service has long existed. cfg.IP is a pure dial
target on the update path (HostConfigHash strips it), so the fallback re-points
it without changing what's pushed; the whole transport is controller-side only,
so `HostConfigHash` is unchanged and an already-terminal CR only retries once
its cooldown elapses (or `Status.FailureReason` is cleared by hand).

### Host observability

Two agents ride the operator image onto every mini, both installed by
`macos-host-bootstrap` and both re-pushed by the drift loop (their bytes are in
`HostConfigHash`, so forgetting to thread one through `UpdateTartKubelet` makes
it silently skip on every roll — which is exactly what happened to
`node_exporter` once).

They travel in opposite directions, and the asymmetry is not a preference:

- **`node_exporter`** is *pulled*. `alloy-metrics` dials `:9100` through the
  Tailscale operator's egress ProxyGroup. It binds the tailnet IP specifically
  so it is never exposed on the mini's public interface.
- **`tuist-log-shipper`** ([`infra/macos-log-shipper`](../macos-log-shipper))
  is *pushed*. A file has no scrapeable surface, and nothing in the cluster can
  tail one on a macOS host: a Pod on a macOS Node is a Tart VM, so a
  DaemonSet-shaped collector sees a guest filesystem, not the host's. It tails
  `/var/log/tart-kubelet.log` — the launchd sink for everything the reconciler,
  node agent and volume manager log — and POSTs to the in-cluster Alloy
  receiver's `loki.source.api` over the tailnet, so no Grafana Cloud credential
  is distributed to the fleet. Query `{job="tuist-macos-tart-kubelet"}`.

Both are gated on Tailscale being wired, for mirrored reasons: without a
tailnet, the pull agent would have to listen somewhere public, and the push
agent has no route to its target at all.

### SSH ingress guard

Both dial paths land on the same listener, so both fail together. A Scaleway
Mac mini's public interface is internet-facing and its `:22` absorbs continuous
SSH brute-force traffic; several hundred half-open connections from scanner
ranges sit in `SYN_RCVD`, past `SOMAXCONN`, and the kernel drops every new SYN.
launchd (not sshd) owns that socket and binds it to `*:22`, so an exhausted
backlog blocks the tailnet fallback exactly as hard as the public path. That is
how a host stops accepting config pushes on every path at once and drifts on a
stale tart-kubelet (recovered automatically by the reboot tier below).

`installSSHIngressGuard` (bootstrap + drift, right after `installTailscale`)
drops inbound `:22` at the pf edge from everything except the tailnet
(`100.64.0.0/10`), loopback, `--ssh-ingress-allow-cidrs`, and the live session's
own source address. Notes:

- It runs *after* Tailscale so it never narrows `:22` before the fallback path
  exists, and it no-ops entirely when Tailscale isn't wired: without a second
  path, a wrong allow list strands the host behind VNC.
- The rules live in the `com.apple/tuist.sshguard` sub-anchor, the same trick
  `renderVMNATScript` uses. A top-level `anchor` appended to `/etc/pf.conf` is
  only read on a full ruleset load (i.e. at boot), so on a running host
  `pfctl -a` would populate an anchor nothing evaluates while the drift update
  stamped `HostConfigHash` as converged: the guard would report shipped and
  filter nothing until a reboot. The stock pf.conf already carries
  `anchor "com.apple/*"`, so a sub-anchor under it is live the moment it is
  written. Nothing here edits `/etc/pf.conf`, and a test asserts that.
  `dev.tuist.pfctl-sshguard` re-loads the anchor file at boot and every 60s, so
  the rules survive a reboot or an external flush with no SSH round trip.
- Loopback must stay open or `renderSSHReachabilityScript`'s `127.0.0.1:22`
  probe reads as a permanent wedge and reloads ssh every minute.
- Folding the live session's source into the table makes the guard
  self-correcting: if the operator's egress address changes and the configured
  list goes stale, the public dial is dropped, the drift loop falls back to the
  tailnet, and that push rewrites the table with the new address.
- Put the operator's SSH egress in `--ssh-ingress-allow-cidrs` to keep the
  public path usable, since a tailnet-transported roll can't update Tailscale
  itself (`SkipTailscaleInstall`, above).
- The host-side backlog drain alone can't fix this. It clears a queue the flood
  refills within seconds, which is why hosts stayed wedged for weeks with the
  watchdog installed and firing.
- The guard ships **over SSH**, so it cannot reach a host that is already
  wedged — the hosts that need it most are the ones that can no longer receive
  it. `rebootUnreachableHost` (below) is what breaks that circularity.

### Reboot recovery for an unreachable host

The cooldown re-arms the retry budget but assumes the host recovers on its own
"once it is reachable again". A backlog-wedged mini never does: every retry is
another dropped SYN, so the CR cycles terminal → cooldown → five doomed dials →
terminal indefinitely, on a stale config, while `:8080`/`:9100`/`:5900` keep
answering and the Node keeps posting Ready.

So when the update budget is exhausted *and* the failure was connect-level
(empty fingerprint — the same signal the tailnet fallback keys on),
`rebootUnreachableHost` asks Scaleway to reboot the mini once. That drops the
`SYN_RCVD` table and recreates the listener, reopening `:22` long enough for
the next cooldown to push the current config — which installs the ingress guard
and stops the wedge recurring. It is the drift-loop counterpart to
`handleBootstrapFailure`'s tier 1, and it replaces consoling in over VNC as the
only recovery.

It never releases the host: unlike a bootstrap failure, the mini is
bootstrapped, Ready and running work, so wiping it would cost far more than the
stale config it is stuck on. `Status.UpdateRebootIssued` makes it one-shot per
wedge, cleared on a successful roll and deliberately *not* by the cooldown — a
host still unreachable after a reboot is not one more boot away from working,
and re-firing every cooldown would reboot a dead mini forever instead of
leaving the terminal state for the stuck-Failed alert to surface.

**The reboot is gated on proving the host is idle**, which is the one place
this tier must NOT copy `handleBootstrapFailure`. A bootstrapping host runs
nothing by definition; a drift-wedged one is Ready, schedulable and usually
mid-job, because the wedge takes out only the ssh accept path. `hostWork`
establishes idleness fail-closed — anything it cannot determine counts as busy
— and the evidence differs per fleet:

- **Pod fleets** (runners, macos): cordon the Node first, then count its
  non-terminal Pods. The cordon is not politeness, it is what makes the count
  durable: these Pods go through the default scheduler with a
  `tuist.dev/fleet` nodeSelector, so an uncordoned node can be handed a job
  between the count and the reboot. `Status.UpdateRebootCordoned` records that
  the cordon is ours, so the successful roll lifts only what this recovery
  placed and a hand-parked host stays parked.
- **Builder fleets** (`Spec.GHActionsRunner` set): ask GitHub whether the
  runner (registered under the machine name) is busy. Bakes run under a
  launchd LaunchAgent and **no Pod ever selects the builder fleet**, so a Pod
  query returns empty whether the host is idle or halfway through a
  `tart push` — Kubernetes has no opinion worth having here. Builders are
  never cordoned, since a cordon would imply a protection it does not give.

A deferral is not a verdict: it consumes no one-shot, emits
`RebootDeferredHostBusy`, and the next exhausted budget re-checks. A busy host
therefore keeps running on a stale config until it drains, which is the correct
trade against killing a job to deliver a config push.

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
infra/cluster-api-provider-tuist/
├── api/v1alpha1/
│   ├── groupversion_info.go
│   ├── scalewayapplesiliconmachine_types.go (+ …template)
│   ├── scalewayelasticmetalmachine_types.go (+ …template)
│   ├── dediboxmachine_types.go (+ …template)
│   ├── ovhdedicatedmachine_types.go (+ …template)
│   ├── tuistcluster_types.go
│   └── zz_generated.deepcopy.go
├── controllers/
│   ├── scalewayapplesiliconmachine_controller.go
│   ├── tuistcluster_controller.go
│   ├── fleetspread_controller.go
│   ├── orphan_reclaimer.go
│   └── linux/      # the 3 Linux fleet kinds (Dedibox / OVH / Elastic Metal)
│       ├── dediboxmachine_controller.go
│       ├── ovhdedicatedmachine_controller.go
│       ├── scalewayelasticmetalmachine_controller.go
│       ├── linux_cloudinit.go       # shared self-join script + kubelet config (Layers 2+3)
│       └── kubelet_config_drift.go  # zero-downtime re-push of kubelet config to Ready nodes
├── internal/
│   ├── scaleway/     # Scaleway SDK wrapper
│   ├── credentials/  # fleet SSH keys + per-machine kubelet identities
│   └── bootstrap/    # SSH-driven kubelet/tart-cri install
├── cmd/manager/    # controller-manager entry point
├── config/
│   └── rbac/       # ClusterRole for the manager
├── Dockerfile      # cross-builds the darwin/arm64 host artifacts (tart-kubelet,
│                   # tuist-log-shipper, tailscale) alongside the linux manager
└── AGENTS.md (this file)
```

CRDs live in [`infra/helm/tuist/crds/`](../helm/tuist/crds/) so Helm
installs them on first `helm install`. Helm 3 skips that directory on
upgrades, so the deploy workflow re-applies it every run
(`kubectl apply -f "$HELM_CHART_PATH/crds/"` in
[`server-deployment.yml`](../../.github/workflows/server-deployment.yml)) —
schema changes ship with the deploy that carries them, no operator step.

A schema change is therefore a live change to what the apiserver accepts,
including for the CRs **CAPI clones on its own**. Adding a required field
to a machine spec makes every MachineTemplate that predates it un-clonable,
which surfaces as `InfrastructureTemplateCloningFailed` on the next
MachineSet scale-up rather than at deploy time — and Helm does not backfill
the field onto a live template (it patches these CRs manifest-to-manifest,
so a field the live object never received is never added). Prefer an
optional field with a controller-side default over a required one.

## Node extended resources

The Linux machine controllers patch two integer extended resources onto the
Nodes they own (`controllers/shared/node_egress.go`, `node_memory.go`), both
re-applied every reconcile so a kubelet re-registration that resets status
cannot strand them. Each exists because the scheduler's native bin-pack cannot
see the quantity in question:

- `tuist.dev/egress-mbps` — the box's NIC budget, which Kubernetes has no
  concept of. Taken from the machine's `EgressBudgetMbps`.
- `tuist.dev/memory-ceiling-mib` — a bounded multiple
  (`MemoryCeilingOversubscription`) of the node's own allocatable memory.
  Kura cache pods run a memory *ceiling* above their *floor*, so their ceilings
  oversubscribe the box while `requests.memory` only bin-packs the floors. This
  is what bounds that overlap, keeping the worst case within what kernel reclaim
  can absorb instead of what the OOM killer has to resolve.

Consumers request the matching resource with request == limit (extended
resources are integer and non-overcommittable). A pod that requests one on a
node that does not advertise it never schedules, which is why both are opt-in
on the consumer side.

## Node memory governance

`kubeletMemoryGovernanceBlock` in `controllers/linux/linux_cloudinit.go` carries
three settings that only make sense together. Read that constant's comment for
the per-setting reasoning; what matters here is the ordering between them and
how they reach a running node.

1. **`systemReserved` / `kubeReserved`** carve the daemons that live outside any
   pod out of allocatable. This has to come first: MemoryQoS derives its
   protection from pod *requests*, so with allocatable equal to capacity the
   scheduler can promise pods the whole box and the protection would then
   squeeze the kubelet itself.
2. **`evictionHard`** raises `memory.available` off the 100Mi default. On a
   31GiB box that default leaves so little margin that the kernel OOM killer
   usually beats the eviction manager, turning contention into a SIGKILL
   mid-transfer rather than an evicted pod with an event. It **replaces** the
   kubelet defaults rather than merging, so all four signals are restated.
3. **`MemoryQoS`** (alpha, off by default upstream — enabled here deliberately)
   maps requests onto cgroup v2 `memory.min` / `memory.low`, which is what makes
   the memory floor kernel-enforced instead of advisory. `memoryThrottlingFactor`
   is pinned to `1.0` so `memory.high` sits at the limit: the default 0.9 would
   throttle on `memory.current`, which counts the clean artifact page cache a
   warm cache node is supposed to hold.

**This is version-dependent, and the fleet is on v1.34.** There, MemoryQoS sets
`memory.min` from requests for Burstable containers too, so a cache pod's floor
is hard, unreclaimable protection. That is safe only because the reservations
land first: `memory.min` is memory the kernel may not reclaim, so it OOMs rather
than reclaims once the protected total approaches capacity. The
`sum(requests) <= allocatable` invariant with allocatable properly reserved is
what keeps the protected total clear of the box.

**Upgrading to v1.36+ silently disables it.** v1.36 splits protection out into a
new `memoryReservationPolicy` field defaulting to `None`, and retiers it so
`TieredReservation` gives Guaranteed pods `memory.min` and Burstable pods the
softer `memory.low`. With this config unchanged on v1.36 the result is no
protection at all and no throttling either (the factor is pinned to 1.0) — a
silent no-op, not a visible failure. Set `memoryReservationPolicy:
TieredReservation` as part of the version bump, never before it: an unknown
field fails KubeletConfiguration's strict decode and the kubelet will not start.
The same warning sits on `linuxCloudInitOptions.K8sMinor`, which is what an
upgrade actually edits.

**Propagation.** `desiredKubeletConfigHash` fingerprints the rendered config, so
any change here re-pushes through `kubelet_config_drift.go` to every already-Ready
node and restarts its kubelet — no machine roll, and running pods survive (the
re-push never touches containerd, apt, or the `/data` mounts), but it lands on
all three Linux fleets at once. Prefer a low-traffic window.

**Rollback is not symmetric.** Turning `MemoryQoS` back off does not reliably
clear the `memory.min` / `memory.low` values already written to existing cgroups
(kubernetes/kubernetes#138436), so a node may need a kubelet restart or reboot to
fully shed them. Budget for that rather than assuming a revert is instant.

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
   these permission sets, all at project scope:

   - `AppleSiliconFullAccess` — order/release Mac minis, list server
     types and OS images (the Apple Silicon fleets).
   - `ElasticMetalFullAccess` — list/order/release Elastic Metal
     servers (the kura runner-cache fleet). Elastic Metal is a
     **separate Scaleway product** from Apple Silicon; without this
     set the EM reconciler 403s on its first `list elastic metal
     servers` call and never orders a node, so the cache stays down
     and a deploy waiting on the fleet hangs.
   - `PrivateNetworksFullAccess` — attach servers to the runner-cache
     Private Network (find-or-created by name).
   - `IPAMReadOnly` — read the PN-assigned address the self-join uses.
   - `SSHKeysFullAccess` — register the per-fleet Ed25519 public key
     the operator generates on first reconcile. **Do not use
     `IAMManager`** despite the name suggesting it covers SSH keys;
     Scaleway gates `ssh_key` write under `SSHKeysFullAccess`
     specifically.

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
cd infra/cluster-api-provider-tuist
go test ./...
go build ./...
docker build -f Dockerfile -t ghcr.io/tuist/capi-provider-scaleway-applesilicon:dev ../..
```

The Dockerfile is multi-stage: it cross-builds tart-cri + tart-cni
for darwin/arm64 (so the manager can ship them to Mac minis at
bootstrap time) and builds the manager itself for whatever
linux/<arch> the cluster runs on.

## Operating

### Bring a pre-ordered bare-metal box into the pool (Dedibox / OVH)

The Dedibox and OVH kinds adopt a *pre-prepared* box rather than ordering or
installing one, the same shape as the Apple Silicon fleet. **Adoption is a claim
+ SSH self-join only; the OS install never runs on the adoption path** (that is
what keeps a *claimed* box's self-join fast). A box must be installed (Ubuntu +
the fleet key + a known sudo password) and marked *before* it joins the pool. The
`baremetal:prep-*` tasks do the install and the marking in one step.

**Prerequisites, per env, in the `tuist-k8s-<env>` 1Password vault:**

- Provider API token:
  - OVH: `OVH_API` with fields `application-key` / `application-secret` /
    `consumer-key`, minted on the **same entity** as the fleet's `endpoint` (the
    US boxes live on OVHcloud US, so `ovh-us` / api.us.ovhcloud.com; a token
    minted on a different entity reads as "invalid"). It must be scoped for the
    whole flow, not just reinstall: a reinstall-only token still 403s on naming
    (`PUT /service/*`) and can't read the displayName for adoption
    (`GET /services/*`). Mint it with this pre-filled link (OVH US):
    `https://api.us.ovhcloud.com/createToken/?GET=/dedicated/server&GET=/dedicated/server/*&GET=/services/*&GET=/service/*&GET=/me/*&POST=/dedicated/server/*&POST=/me/*&PUT=/service/*`
  - Dedibox: `DEDIBOX_SCW_API` with fields `secret-key` / `project-id`.
  - Exactly one item per title per vault. A duplicate makes `op read` (prep) and
    ESO ambiguous and wedges both.
- Fleet SSH key, when the fleet sets `sshExternalSecret.enabled: true` (the
  current default for managed fleets): a 1Password item (`OVH_FLEET_SSH` /
  `DEDIBOX_FLEET_SSH`) with fields `private-key` / `public-key` / `sudo-password`.
  ESO syncs it to the `<fleet>-ssh` Secret, and the prep task reads the key
  material straight from 1Password (no cluster access needed). Legacy fleets that
  still mint the key in-cluster use `baremetal:mint-fleet-key` instead.

**Steps:**

1. **Pre-order the box** in the provider console (out of band; the controllers
   never order). OVH ADVANCE-1 for the US regions, Dedibox for eu-central.
2. **Prep it.** Installs Ubuntu + the fleet key + sudo password, then sets the
   adoption marker as its final step, reading the tag / displayName prefix from
   `values-managed-<env>.yaml`. The install is async (~20-40 min; poll the
   console). `PREP_NAMESPACE` selects the env (hence the `tuist-k8s-<env>` vault
   and the values file); the OVH second arg is the fleet name:
   ```bash
   PREP_NAMESPACE=tuist-production mise run baremetal:prep-dedibox 184798
   PREP_NAMESPACE=tuist-production mise run baremetal:prep-ovh ns1034936.ip-40-160-72.us tuist-tuist-ovh-fleet-us-east
   ```
   Pass `PREP_SKIP_MARK=1` to stage capacity without marking it in yet, then
   release it later with `baremetal:mark-dedibox` / `baremetal:mark-ovh` (those
   are also the tasks to re-name a box).
3. **Declare the fleet at `replicas: 1`** in `values-managed-<env>.yaml` and
   deploy. The controller claims the marked box and self-joins it in ~2-5 min.
   `replicas` here is the **box** count (one per region today); a region's
   KuraInstance runs its own pod replicas on top of the box. Because the box is
   prepped before the deploy, the fleet can come up at 1 directly. Only a *true*
   cold start (deploying before any box is prepped) needs the old `replicas: 0`
   then-scale dance, since an enabled fleet with no adoptable box sits at MD 0/1
   and wedges `helm --wait` (the `dig`-based template preserves an explicit 0).

**Fleet naming.** The singular `ovhFleet` renders `tuist-tuist-ovh-fleet` and
`dediboxFleet` renders `tuist-tuist-dedibox-fleet`. Additional OVH regions live
in the `ovhFleets` map and render `tuist-tuist-ovh-fleet-<key>` (e.g.
`tuist-tuist-ovh-fleet-us-east`). The adopt marker comes from that fleet's
values: `adoptTag` (Dedibox) or `adoptDisplayNamePrefix` (OVH, a prefix match).
Production today: tag `tuist-kura-production` (eu-central), displayName prefixes
`tuist-kura-ovh-production-us-east` / `-us-west` (OVH).

Release (`reconcileDelete`) drops the Node + identity + TOFU pin and **reinstalls
the box back into the pool**. It stays a monthly contract (release is not a contract
termination), but the reinstall wipes the OS to a clean, claimable state — any
node-local volume is lost and the host key rotates, so the next claim re-TOFUs it.

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
(`<poolPrefix><uuid>`) and triggers a Scaleway OS reinstall onto the
Machine's own `spec.os`; the host stays alive, returns to
factory-default state, and becomes eligible for the next adoption
once Scaleway flips it back to `Delivered + Ready`. The 24h Apple
licensing floor stays in operator-owned territory — you keep paying
for capacity you already pre-ordered until you decide to release it
via the Scaleway console.

`spec.os` names a macOS release **family** — `Tahoe`, `Sequoia`,
`Sonoma` — not a point release. Adoption accepts any pool host in the
family, and release reinstalls onto the family's newest published
image the host's SKU can boot, so a fleet tracks Scaleway's point
releases instead of chasing them.

Do not put an image name there. Scaleway retires point releases
without notice and reimages released hosts onto the server type's
current default, so an exact pin drifts out from under its fleet and
nothing in the pool can satisfy it again — staging lost its whole
runner pool that way in Aug 2026 while pinned to `macos-tahoe-26.3`.
Adoption therefore refuses a versioned pin outright with an
`InvalidOSPin` condition rather than quietly widening it. The values
to set are
`{macosFleet,runnersFleet,buildersFleet}.machine.os`; `OnDelete`
means live hosts are not churned by the change.

### A Machine stuck on `InvalidOSPin`

The pin lives on each Machine's own spec, cloned from the template at
creation and never re-synced, so a Machine created before the family
switch keeps its versioned pin. That is inert while it holds a host,
but the moment it goes hostless — bootstrap exhaustion releases the
host and leaves the Machine hostless, or it was already pending — its
next adoption is refused and it loops on `InvalidOSPin` every 5
minutes. Editing the fleet's values does nothing for it: the template
is already correct.

```bash
kubectl delete machine <machine-name>
```

The MachineSet re-clones from the current template and the
replacement carries the family. Safe when the Machine holds no host
(`status.serverID` empty) — there is nothing to release. Patching
`spec.os` to the family on the existing CR works too and skips the
re-clone.

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

### Make `kubectl logs`/`exec` work on a fleet node

The apiserver dials the kubelet at the node's InternalIP:10250. When
`logs`/`exec`/`attach`/`port-forward` fail against a fleet node (Dedibox / Elastic
Metal / OVH), the error says which piece is off:

| `kubectl logs <fleet-pod>` error | Fix |
|---|---|
| `dial tcp: lookup <node> … no such host` | apiserver's `--kubelet-preferred-address-types` is missing `InternalIP`. It comes from the `kubeletPreferredAddressTypes` variable in `infra/k8s/clusters/cluster-<env>.yaml`; applying that Cluster CR via `mgmt-cluster-apply` rolls the CP with it. If the running flag doesn't change, the KCP is stuck: `kubectl -n <ns> describe kcp <name>` (a roll blocked behind a CP Machine with no Node). |
| `remote error: tls: internal error` | kubelet has no serving cert. |
| `401` / `Unauthorized` | kubelet config is missing `clientCAFile`. |

The kubelet-config rows converge on their own after a new operator image rolls;
check the node picked it up (the stamped hash appears once the re-push ran):

```bash
kubectl get node <fleet-node> -o jsonpath='{.metadata.annotations.tuist\.dev/kubelet-config-hash}'
```

`kubectl delete machine <name>` re-provisions to force it. On **Elastic Metal**,
two things bite:

- The re-push SSHes in with the fleet key, so the box must be authorized with it.
  `ssh: unable to authenticate … [none publickey]` means it isn't, and the box is
  re-keyed only at reinstall with the key of `machine.Spec.FleetName`. An empty
  `fleetName` uses a per-machine key that mismatches, so make sure it's set.
- A reinstalled box can fail apt (`exited with status 100`) when PN DHCP writes
  `/etc/resolv.conf` with only `nameserver 169.254.169.254`, which the box
  firewalls off. SSH in as `ubuntu` and swap it for `nameserver 1.1.1.1`.

Emergency bypass for a wedged CP: add `InternalIP` to
`--kubelet-preferred-address-types` in
`/etc/kubernetes/manifests/kube-apiserver.yaml` on the CP node (`kubectl debug
node/<cp>` → `chroot /host`; back up outside `manifests/`, swap atomically). It
persists until the CP is rebuilt.

```bash
kubectl -n kube-system logs <pod-on-a-fleet-node> --tail=5   # streams, no dial error
kubectl exec <pod-on-a-fleet-node> -- true
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
