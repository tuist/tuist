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
stale tart-kubelet until someone consoles in over VNC.

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

- `tuist.dev/egress-mbps` — the box's public egress budget, which Kubernetes has
  no concept of. Taken from what OVH reports for the individual box, falling back
  to the machine's `EgressBudgetMbps` (see below); the other Linux kinds take the
  spec value directly.
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

### Per-box egress discovery (OVH)

`EgressBudgetMbps` reaches a machine from its MachineTemplate, so every box a
MachineDeployment clones carries the same number. That is fine while a fleet is
one box per region and wrong the moment a region holds mixed hardware — a box on
a purchased uplink upgrade, or a slower one added later. Over-stating a box's
budget fails silently: the scheduler bin-packs floors the wire cannot deliver and
the egress-tree agent rates its HTB root to match, so the symptom is traffic
overrunning the link, not an error anyone is paged about.

The reconciler therefore resolves the budget from the box, reading
`bandwidth.OvhToInternet` from OVH's
`/dedicated/server/{serviceName}/specifications/network`
(`internal/ovh/client.go`, `controllers/linux/ovh_egress.go`), and falls back to
the spec value for a box it cannot read. It is on for every OVH machine with a
configured budget — zero already means "does not participate in egress governance"
(the chart omits the field, the capacity helper no-ops, the tree agent leaves the
node's pods unshaped), and rating such a box would override that opt-out with no
way back, since the helper can lower an advertised capacity but never remove the
key. The `tuist.dev/disable-egress-discovery` annotation on one OVHDedicatedMachine
excludes that box — no call is made for it, and any reading already recorded on it stops
counting. Presence is the whole signal, the value is never read (the same shape as
CAPI's own `cluster.x-k8s.io/paused`, honoured a few lines up in that reconciler),
so a disable flag never has to answer what `false` or a misspelling means. Removing
the annotation brings the box back. There is no fleet-wide switch: the blast radius of a bad reading
is one node, and a staged rollout is expressed by annotating the boxes that should
wait and removing those annotations one at a time.

Three things about that response are load-bearing. `connection` and
`vrack.bandwidth` sit next to the field we read and report the switch link (25
Gbit/s on every box we run, whatever the public path is limited to), so keying
off either over-commits the public path a cache actually serves from. The value
is a `{unit, value}` pair whose unit is a free-form string, not an enum — taking
the bare number would advertise 5 Mbps for a box reported as "5 Gbps". And every
field in the block is nullable, so an absent bandwidth block is an ordinary
answer, not an error: it resolves to zero, which keeps the node on its spec
value.

Discovery **raises a node's budget, never lowers it**: the floor is whatever the
node already advertises, or the configured budget, whichever is higher. A box's contractual
bandwidth does not shrink on its own — that happens because someone downgraded the
plan, which already has a human attached — whereas a wrong-low reading (an API
blip, a partial response, a box throttled over its monthly quota) is plausible and
expensive: the egress-tree agent re-rates the node's HTB root in place, throttling
live traffic on a box that can carry far more, and the floor only catches garbage.
A lower reading is therefore recorded and surfaced rather than applied.

`tuist.dev/egress-mbps-override` pins a machine's advertised budget to a value the
operator chose, in both directions, and is the single lever for changing a live node —
`spec.egressBudgetMbps` reaches a machine only when it is cloned from its template
(the MachineDeployment is `OnDelete`), so it is the fleet default and the floor rather
than something an operator moves. `status.egressSource` records what decided the
budget last time (`discovery` / `manual` / `configured`), which is what makes a pin
reversible: the ratchet is anchored to what the node advertises, so once a pin is
removed that anchor is a number a human typed, and the recorded source is how the
controller knows to ignore it for one reconcile and re-derive from readings. That
source is recorded only once the capacity patch has landed, so a failed write leaves
the release to be retried rather than spending it on a node that never moved — which
would strand the node at the pin's value, with the ratchet then anchoring on it.

The pin does not apply to a machine whose configured budget is zero, and that is the
one place it refines nothing. Such a box is outside egress governance, and the
node-capacity helper writes the extended resource but has no path that removes it —
so a pin would bring the box in and then have no way to take it back out, leaving the
node advertising the operator's number after the annotation was gone. Give the machine
a budget first; the pin then moves it, reversibly, like anywhere else. A pin left on a
zero-budget machine is ignored and logged rather than silently dropped. The same
one-way property is why `spec.egressBudgetMbps: 0` does not withdraw a node that is
already advertising a budget: it stops the controller managing the key, it does not
remove it. Withdrawing a live box means deleting the machine (which deletes its Node),
not zeroing the field.

Events fire when the node's advertised budget actually moves — `EgressBudgetIncreased`
or `EgressBudgetReduced`, naming both numbers and what decided the new one — not when
a reading arrives. A reading the floor refuses changes nothing on the node, and the
standing disagreement between what OVH reports and what the node advertises is a
metric with history rather than a moment to catch. The events name no remedy, because
the remedy is three moves and naming one of them sends people to do the one that is
inert on its own.

Accepting a confirmed reduction is three moves, in order: **pin** (the node drops
now), **lower the budget** on the machine and in the fleet values (durable, and
correct for the next machine cloned from the template), then **unpin** (the node lands
on the reading). Unpinning before lowering the budget springs the node back to the
configured value — the over-commit the pin was hiding. Disabling discovery also
applies downward directly: the ratchet only ever holds against the controller's own
readings, never against an explicit human decision.

A reading is either a number or nothing: there is no plausibility band around it.
The floor already refuses anything below the configured budget, so a decode that
starts yielding 1 after a response-shape change is refused and surfaced as a
reduction rather than silently applied, and a ceiling would only ever be a guess
that the next faster box trips.

Three gauges publish the numbers behind a node's budget, all labelled `node`:
`capt_ovh_egress_reported_mbps` (what OVH says, plus `service` and `tier`),
`capt_ovh_egress_configured_mbps` (the spec value) and
`capt_ovh_egress_advertised_mbps` (what was patched onto the node). They are
published together because a divergence is then a fact about one reconcile rather
than a race between exporters, and the `node` label is explicit — nothing adds one
at scrape time, and the operator's own `instance`/`pod` labels name the node the
*operator* runs on. `reported < configured` is the alert; the same series are what
a later decision to auto-apply reductions would be argued from.

The reading is cached in status and refreshed daily, not per reconcile: the
machine reconciles every 10 minutes and the number tracks a contract. Neither a
failed call nor an unusable answer overwrites the cached value — a renamed or
dropped bandwidth block is an ordinary answer returning zero, and writing it
through would hand the node back to a spec value that may sit well above the wire.
A failed call is additionally floored to one attempt per 10 minutes (in memory, per
machine UID), because it leaves the refresh timestamp unstamped and a machine in
the not-yet-Ready tail requeues every 20s. The reading records the service name it
came from, so a machine re-adopted onto a different box is read again rather than
rated from its predecessor's number. That check is applied where the budget is
decided, not only inside the discovery function: most paths reaching a capacity
decision never enter it — a machine inside the read backoff, or one whose
`serviceName` an operator cleared to force re-adoption — and a reading from another
box must not rate this one on any of them. A mismatch also resets the ratchet,
because the anchor is the node's advertised capacity and that survives a kubelet
re-registration by design, so dropping the reading alone would leave the previous
box's budget holding the new one up. A machine carrying
`tuist.dev/disable-egress-discovery` is skipped entirely.

That annotation survives CAPI's in-place propagation because of an ownership
detail worth knowing: every MachineSet reconcile SSA-patches the InfraMachine's
labels and annotations from the MachineSet template under the `capi-machineset`
field manager, and SSA prunes only keys that manager owns. Our templates set no
annotations, so it owns none. Adding this key to a MachineDeployment's
`spec.template.metadata.annotations` therefore turns it into a per-fleet switch
that overrides every per-box annotation in that fleet.

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

### Disk layout, and why it is an install-time decision

Every install these kinds start lays down a redundant root plus a **separate XFS
`/data`**, and the self-join then mounts `/data` with `prjquota` and refuses to
join a box where it cannot (`dataProjectQuotaScript` in
`controllers/linux/linux_cloudinit.go`).

The image store gets a reserved project of its own (`containerdQuotaScript`,
project 100). It is the only consumer of `/data` that is not a tenant, and a
per-volume quota is a ceiling rather than a reservation, so a tenant inside its
own ceiling can still be denied space something else took first. Nothing else
bounds it: the kubelet's image GC triggers on the FILESYSTEM being nearly full,
so it only reclaims once the box is already squeezing tenants. The ceiling is
deliberately generous, because containerd hitting it means failed pulls that
image GC cannot resolve, and unlike the `/data` mount setup a failure to apply
it does not fail the join.

The chain it exists to close: a Kura cache PV is a local-path *directory* on
`/data`, a directory has no size, so the pod's `ephemeral-storage` request is
scheduler admission at placement time and nothing bounds what one account
actually writes. An `ephemeral-storage` limit would not help: it is enforced
against the pod's writable layer, logs and emptyDir, none of which is where the
cache lives. XFS project quotas are the only real boundary, and the
local-path-provisioner hooks in `infra/helm/tuist/templates/kura-fleet-storage.yaml`
set one per volume from the PVC's requested size (which the kura-controller
sizes from `KuraInstance.spec.storageSize`). Without it, one instance filling
the box crosses kubelet's eviction line and takes down every tenant on it.

The layout comes from the box's real disk groups (`ovh.PlanStorage`,
`GET /dedicated/server/{name}/specifications/hardware`), so one code path covers
every shape in the fleet: `/boot` + a capped `/` + `/data` filling the rest, on
the box's LARGEST disk group.

The RAID level comes from that group's disk count (`DiskGroup.raidLevel`): RAID
10 on an even group of four or more disks, RAID 1 on two or three, none on one.
This decides usable capacity, not just redundancy. A layout installed at RAID 1
mirrors across every disk the partitioning covers, so a four-disk group installed
that way carries ONE disk of `/data` and the extra disks buy nothing. Order a box
with the larger disk option and it is RAID 10 that turns those disks into space.
Odd counts above three fall back to RAID 1 rather than parity: RAID 5/6 is a
different durability and rebuild trade to pick deliberately, and no box in the
fleet has that shape.

It is deliberately ONE storage entry. OVH documents storage customization for a
single disk group per install, so a box with a small OS mirror plus a larger data
mirror gets its whole layout on the larger mirror and leaves the smaller one
untouched, rather than the two-entry payload that shape invites. Two entries
would be either rejected or silently reduced to the first, and the silent case
installs a box with no `/data` at all. That is recoverable, since the self-join
then refuses to bring it up, but only after a wipe and a ~30 minute install.
Using the second group needs either a verified multi-group flow or post-install
assembly of the untouched disks; neither exists today, and no cache capacity is
lost by leaving it idle, since the cache lives on the larger group either way.

`StartInstall` refuses to post a reinstall it cannot plan a layout for, rather
than falling back to the provider's default single-root install. Dedibox takes
the same shape by formatting the default layout's `/data` as XFS
(`internal/dedibox`), since its API already carves small-root + large-`/data`.

Elastic Metal goes through Scaleway's partitioning schema (`internal/scaleway/partitioning.go`),
which is the best-instrumented of the three: `GetDefaultPartitioningSchema`
returns the offer's own layout to transform, so the planner never guesses the
disk count, device naming, or whether the OS is mirrored, and
`ValidatePartitioningSchema` checks the result against the real offer WITHOUT
touching a server. `PartitioningSchemaFor` runs both before either install path
posts, so a schema the provider would reject stops the install rather than
wiping a box to discover it. `PlanSchema` takes /data out of root's partition
and mirrors it exactly as the default mirrors root.


**Already-adopted boxes need a reinstall.** Partitioning cannot change in place,
so a box installed before this has either no separate `/data` or an ext4 one, and
its cache volumes stay unbounded. They keep working: the provisioner hooks no-op
with a log rather than refusing, so an old box does not become unschedulable, and
`kura_volume_quota_enforced` is `0` on exactly those nodes, which is the query for
what is left to convert.

### Converting a live cache box

**Do not delete the Machine out from under running cache pods.** It deadlocks,
and this is pre-existing rather than anything the quota work introduced:

1. CAPI drains the Node before the infrastructure controller runs. Draining
   evicts a cache pod.
2. That pod's PVC is still bound to a local-path PV with a
   `kubernetes.io/hostname` affinity to the box being drained, so the replacement
   pod has nowhere to schedule and stays Pending.
3. Each `KuraInstance` has a `PodDisruptionBudget` of `minAvailable: 1`, so with
   the first replica down the eviction API refuses the second.
4. `deleteNodeLocalPVCs` (below) is what would free the volume, and it runs
   AFTER drain in `reconcileDelete`. With `nodeDrainTimeout` unset on these
   fleets, drain has no deadline, so the Machine sits in Deleting indefinitely.

**The controller does this for you.** Annotate the outgoing node
`tuist.dev/kura-evacuate` and the kura-controller runs the sequence below
itself, one replica at a time, gated on each moved pod reporting a completed
catch-up (`infra/kura-controller/controllers/node_evacuation.go`). Bring up the
replacement box first; with nowhere to land it deliberately does nothing. Once
the box holds no cache pods, delete its Machine as normal.

The manual sequence, for reference and for anything the controller does not
cover. A region's instances run a primary plus a warm standby, and the public
Service selects ONE of them by pod name, so the standby can be moved with
nothing user-visible happening:

1. Prep a second box into the region's pool and raise `replicas`. Before
   touching anything live, confirm the new box can actually enforce: provision a
   throwaway PVC on it and check `kura_volume_quota_enforced` is `1` there. The
   provisioner hook is fail-closed, so a box that cannot enforce will hold the
   migration at Pending rather than proceeding, and that is much better
   discovered before the old box is cordoned.
2. Cordon the old box. This is not optional and the controller enforces it: an
   annotated box that is still schedulable is refused, because
   `instancePodAffinity` PREFERS co-locating an instance's pods, so the
   replacement would be pulled straight back onto the box being retired and the
   move would loop, burning the volume's cache on every turn.
3. Move the STANDBY replica: delete its PVC (it stays Terminating under
   `pvc-protection`), then delete its pod. Deleting the pod first only rebinds it
   to the same PV. Once both are gone the StatefulSet recreates them and
   `WaitForFirstConsumer` binds the new claim on the second box.
4. Wait for the moved replica to catch up from its peer before handing it
   traffic. Kura backfills a fresh replica from the peer it joins (`kura/src/backfill/`),
   so the cache content follows even though the volume does not; gate on that
   pod's backfill metrics rather than a timer.
5. Let the primary role hand over, then repeat 3-4 for the ex-primary.
6. Delete the old Machine once it holds no cache pods. Drain is trivial now, and
   release reinstalls it onto the split layout and returns it to the pool.

Releasing an OVH box is not a contract termination, so a region left at two boxes
keeps paying for both. Decide whether the second box is capacity you want or a
contract to cancel out of band.

The deadlock itself is now defused declaratively: the `kura-cache-skip`
`MachineDrainRule` in `infra/k8s/clusters/machinedrainrules.yaml` tells Cluster
API not to evict cache Pods, so drain completes, the PVC reap runs, and the
StatefulSets reprovision on whatever box is left in the pool. That is a safety
net rather than the procedure: it makes the naive path terminate instead of
hang, but it gives up the cache, since both replicas are co-located and deleting
their box leaves no peer to backfill from. Use the staged move above to keep a
region warm.

Setting `nodeDrainTimeout` on these fleets would additionally bound the failure
if a future Pod shape reintroduces the same shape of stall. Worth doing
independently of any conversion.

### Scale up
```bash
kubectl scale machinedeployment <fleet-name> --replicas=4
```
Two new ScalewayAppleSiliconMachines are created → operator orders
two Mac minis from Scaleway → ~5 min later `kubectl get nodes` shows
them Ready.

### Multi-guest hosts and mixed-SKU fleets

Apple's macOS SLA permits two virtualized macOS guests per host, and
Tart enforces it. Whether a host actually runs two is a sizing
decision, not a code path: tart-kubelet advertises `hostCPU` /
`hostMemoryMB` as the Node's capacity and kube-scheduler fits guest
Pods into it, so a host admits `hostMemoryMB / podMemoryMB` guests.
Size `hostMemoryMB` as an exact multiple of the pool's Pod memory
request so both dimensions bind at the same number — leaving CPU as
the only thing standing between the fleet and a third guest makes the
cap an accident of the current Pod shape.

Five spec fields are per-Machine so one operator can run a
heterogeneous fleet, all resolved in `hostConfig` and therefore all
reflected in `desiredHostConfigHash`:

| Field | What it sizes |
| --- | --- |
| `hostCPU` / `hostMemoryMB` | Node capacity — the actual guest-count control |
| `maxPods` | Node Pod ceiling. Counts **every** Pod bound to the Node, and a terminal Pod holds its slot until GC — so it is guests x 2, not guests + system Pods. See below |
| `guestCapacity` | The per-guest host resources: the VNC relay port range and the disk-pressure goldens floor. Declares intent; creates no capacity |
| `runnerCacheVolumeGiB` | The per-account cache volume's quota, which tracks the SKU's disk |

`maxPods` is sized as guests x 2 + 1 because a Pod stays bound to its
Node after it finishes: each guest slot can transiently hold its running
Pod plus a predecessor GC has not collected yet (observed on the live
fleet 2026-08-25 — a single-guest host carrying one Running and one
Succeeded Pod), and the +1 is margin. So 3 for a single-guest host, 5
for a dual-guest one.

Keep that margin. It is not where the SLA is enforced and does not need
to be — Tart refuses a third VM and `hostCPU`/`hostMemoryMB` bind the
guest count first, so a higher value admits no extra guest. But a node
sitting exactly at its ceiling rejects Pods with `Too many pods` while
`macosFleetAllocatableMemory` still counts its slots as available, so
the autoscaler keeps targeting a node that cannot take them until GC
catches up. Nothing is reserved for host-system Pods — `hcloud-csi-node`, the
usual suspect, is kept off macOS by a `kubernetes.io/os NotIn [darwin]`
required nodeAffinity rather than by the macOS taint, which its blanket
`Exists` tolerations ignore.

`guestCapacity` exists so those last two resources have one source of
truth. Both are per-guest and neither is derivable from the others —
`maxPods` folds in system Pods, and `hostMemoryMB / podMemoryMB` is not
knowable host-side, since the host does not know the pool's Pod shape.

A single-guest host resolves `guestCapacity` to 1, which is already
tart-kubelet's default for both derived values, and the plist renderer
omits a flag at its default — so adding a multi-guest SKU to a fleet
does **not** drift the single-guest hosts already in it. There is a
test pinning that (`TestDesiredHostConfigHash_UnchangedForSingleGuestMachines`);
if it fails, deploying the operator silently rolls launchd on every
mini in every macOS fleet.

The VNC relay is the one thing that genuinely breaks without this. Its
port is pinned per host (so the per-Mac Tailscale egress Service can
declare it) while a relay is per *Pod*, so a second guest needs a
second port and the Service has to front it. The chart expresses a
mixed fleet through `runnersFleet.machineGroups[]` — see the comments
in `infra/helm/tuist/templates/runners-fleet.yaml` for why each group
gets its own Machine-object label but shares the fleet's Node label.

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
