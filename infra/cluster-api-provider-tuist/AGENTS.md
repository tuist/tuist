# cluster-api-provider-tuist

Cluster API infrastructure provider that joins Scaleway and OVH nodes as
workers into the existing caph/Hetzner clusters, surfaced through
CAPI's standard Machine/MachineDeployment shape. It manages these
machine kinds:

- `ScalewayAppleSiliconMachine` — Mac minis (Tart), SSH-bootstrapped
  with tart-cri/tart-kubelet.
- `RackAppleSiliconMachine`: Mac minis **we own**, in a rack we
  operate (the BER1 colo programme). Same host bootstrap and drift
  loop as the Scaleway kind; the host comes from a `RackHost` in the
  cluster's own inventory rather than a vendor API, and its reboot is
  a PDU outlet. See "Rack-owned hosts" below.
- `RackLinuxMachine`: x86 Linux machines **we own** in the same rack (the
  BER1 edge, services and storage nodes), one per `RackLinuxHost`, which the
  operator creates with its CAPI Machine, joined over their own tailnet address with a kubeadm
  `system:node` identity and kept converged. See "Rack-owned Linux hosts"
  below.
- `ScalewayElasticMetalMachine` — Scaleway Linux bare metal (e.g. the
  `kura-scw-fr-par` runner-cache node), SSH self-join (Elastic Metal
  has no user-data channel); adopts a pre-ordered box and
  **reinstalls it (wipe) on release**.
- `DediboxMachine` — Scaleway Dedibox bare metal (eu-west); adopts a
  pre-prepped box and reinstalls it (wipe) back to the pool on release.
- `OVHDedicatedMachine` — OVHcloud US bare metal (the us-east / us-west /
  ap-southeast cache regions, and the Gravelines Linux runner pool); adopts a
  pre-prepped box and reinstalls it (wipe) back to the pool on release.

All bootstrap with an operator-minted kubelet identity + SSH self-join,
then wait for `Node.Ready`. The three Linux kinds share the
`controllers/linux` package and bind that identity to `system:node`;
Apple Silicon uses the `tart-kubelet` role. The Elastic Metal kind is
designed in `docs/scaleway-elastic-metal-support.md`; the sections below
detail the Apple Silicon kind.

A fifth kind for Vultr is designed but not built, in
`docs/vultr-baremetal-support.md`. It is the only provider whose API cannot be
given a partitioning plan, so its box is converted after install by
`baremetal:prep-vultr` rather than installed into the right layout, and that
pushes a conversion stage into the release-then-reinstall lifecycle the other
Linux kinds share. Until it exists, the `sa-west` box is hand-joined.

## CRDs

| Kind | Purpose |
|---|---|
| `ScalewayAppleSiliconMachine` | One Mac mini. Has the Scaleway server type, zone, OS, per-host pod CIDR, fleet name (ties Machines on the same fleet to one shared SSH key), and kubelet version. SSH and bootstrap material are operator-managed — no Secret refs in the spec. |
| `ScalewayAppleSiliconMachineTemplate` | Template MachineDeployments / MachineSets clone from. |
| `RackAppleSiliconMachine` (+ `…Template`) | One Mac mini we own. Carries only workload shape (sizing, fleet, kubelet version) plus the `adoptPool` it claims from: no host identity at all, which is what lets one template be cloned N times. |
| `RackHost` | One physical Mac mini in a rack we operate: serial, dial address, the subnet routers that address is dialled through, rack/shelf/U, PDU outlet, claimed/free. Pure inventory: nothing running on the host reads it. |
| `RackLinuxMachine` | One rack Linux node, created by the operator with its CAPI Machine under its host's name: the host it is, the name it joined under, its converge state. |
| `RackLinuxHost` | One x86 Linux machine we own, named after its SMBIOS UUID: its hostname, role, site, the tailnet tags its install joins it with, its node labels and taints, whether it is powered on (`online`), the reinstall it asks for (`reinstallGeneration`) and its AMT. Status carries its provisioning state, boot MAC, hardware, current tailnet device, a published install, power and AMT's state. |
| `RackLinuxCandidate` | A machine whose install stick found no install published for it, from what it announced to a rack boot server: SMBIOS UUID (its name), serial, product, NICs, its TPM's endorsement key, the `bootMAC` to declare (its i226-LM), the edge that heard it, the host that declares it, if any, and the last announcement that conflicted with the first. The boot servers write it and the operator marks it. |
| `ScalewayElasticMetalMachine` (+ `…Template`) | One Scaleway Elastic Metal server (Linux bare metal): offer type, zone, OS, PN id, node taints, `fleetName`. SSH self-join (no user-data channel); local-NVMe (`scw-local-nvme`) cache. Reinstall-on-release. |
| `DediboxMachine` (+ `…Template`) | One Scaleway Dedibox bare-metal server (eu-west): adopts a pre-prepped box by tag, `fleetName`. Reinstall-on-release. |
| `OVHDedicatedMachine` (+ `…Template`) | One OVHcloud US bare-metal server (the us-east / us-west / ap-southeast cache regions and the Gravelines runner pool): adopts a pre-prepped box by displayName prefix, `fleetName`, `nodeTaints`. Reinstall-on-release. |
| `TuistCluster` | Cluster-level stub (CAPI core requires it for the parent Cluster to validate). Sets `Status.Ready=true` once it exists. Shared by all machine kinds. |
| `FailoverIP` | One vendor failover/additional IP kept routed to a healthy box of a Kura bare-metal pool, draining off a box whose peer demux is rolling. Cluster-scoped, not a CAPI machine kind. |

API group: `infrastructure.cluster.x-k8s.io/v1alpha1`. Short names:
`samm`, `sammt`, `sasc`, `rasm`, `rasmt`, `rh`, `rlm`, `rlmt`, `rlh`.

Every kind above is generated from the annotated types in
[`api/v1alpha1/`](api/v1alpha1/) by
`mise run capi-scaleway-applesilicon:generate`, which also writes
`zz_generated.deepcopy.go` and stamps the `cluster.x-k8s.io/v1beta1` contract
label CAPI core discovers providers by. Schema, printer columns, and the status
subresource all come from `+kubebuilder:` markers, so a manifest edited by hand
is reverted by the next run. The `generated` job in
[`capi-provider-scaleway-applesilicon-image.yml`](../../.github/workflows/capi-provider-scaleway-applesilicon-image.yml)
re-runs the task and fails on a diff.

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
- Tart VMs keep `:22` to the internet and nothing on the host. A VM's egress
  arrives inbound on the vmnet bridge with its `192.168.64.x` source before it
  is NAT'd out, so the catch-all block would drop every SSH a customer workload
  makes, and the VM range gets its own pass. Two blocks sit above that pass:
  one for a sibling VM (`<vm_ssh_sources>`) and one for every host address
  (`self`). Blocking the bridge address alone is not enough. A VM that dials
  the host's en0, LAN or tailnet address is delivered to the same `*:22`
  listener, so a workload could flood the backlog the guard exists to protect.
  This was reproduced from a runner VM on `ber1-proto-01` on 2026-09-24.
- Use static `self`, never `(self)`. xnu's pf has no interface groups, so the
  dynamic form resolves to an empty table: it loads cleanly and blocks nothing
  (also verified on `ber1-proto-01`). pfctl expands static `self` to the host's
  current addresses on every load, and the re-arm reloads every 60s, so an
  address the host gains is covered within a minute. The re-arm must keep
  reloading even when the anchor file is unchanged.
- Every pass rule carries `flags any`. On a fresh host `installVMEgressFirewall`
  enables pf under the bootstrap's own session, so that session has no state
  when the guard loads, and under pf's default `flags S/SA` its next packet
  hits the block. macOS pf tracks a connection it picks up mid-stream with the
  maximum window scale, so the adopted session is not throttled.
- Folding the live session's source into the table makes the guard
  self-correcting: if the operator's egress address changes and the configured
  list goes stale, the public dial is dropped, the drift loop falls back to the
  tailnet, and that push rewrites the table with the new address. It is not
  durable, though: every push replaces the previous session's source, so
  anything that must keep working when the host has lost its tailnet identity
  belongs in the configured list.
- A rack host's list is the fleet's plus its RackHost `spec.sshIngressAllowCIDRs`:
  the LAN address of each subnet router its address is dialled through. A
  router forwards with SNAT (the default on Linux, the only mode on macOS), so
  the host sees the router, not the operator. A rented mini that drops off the
  tailnet can still be dialled on its public address because the operator's
  egress is in the fleet list; a rack mini has no public address, so without
  the router in its list it is reachable only from its console. That is what
  stranded the BER1 prototype on 2026-09-18 (see "Rack-owned hosts").
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

## Rack-owned hosts

`RackAppleSiliconMachine` joins Mac minis we bought, in a rack we operate. It
is the Scaleway kind with the provider removed and the pool moved in-cluster:
same `bootstrap.Run`, same `HostConfigHash` drift loop, same terminal-failure
and cooldown rules, same per-machine tailnet egress Service: all of which live
in `controllers/macos/hostagent.go` and are shared rather than copied, because
those rules are the ones this provider has repeatedly got wrong in ways that
stay invisible until a fleet has been running stale config for weeks.

### Why two CRs

Every other machine kind gets its pool from a vendor API: Scaleway's server list
filtered by a name prefix, OVH's by a displayName prefix, Dedibox's by a tag.
Hardware we own has no such API, so the pool has to be Kubernetes objects: one
`RackHost` per box, carrying the physical facts, and a `RackAppleSiliconMachine`
that claims one.

Folding the address and the outlet onto the Machine instead is the obvious
simplification and it does not work. A MachineTemplate is **cloned**, so every
replica would carry the same address; you would need one MachineDeployment per
box, `kubectl scale` would stop meaning anything, and: the part that actually
bites: a MachineHealthCheck remediation would recreate the Machine onto the
same broken host forever, because there would be nothing else for it to land on.

**The claim is a status `Update`, not a merge patch.** `Update` carries the
resourceVersion the host was read at, so the apiserver rejects the second of two
racing claims and the loser retries. A merge patch sends no resourceVersion:
both claims would "succeed", both machines would bootstrap the same box, and the
second would take over the first's Node. This is the one place in the provider
where one object's reconciler writes another object's status, and it is why
`rackhosts/status` is in the operator's ClusterRole.

### Where it deliberately diverges from the Scaleway kind

Everything that differs is about ownership, and each divergence has a failure
mode behind it:

- **Credentials are read, never minted.** `EnsureFleetSSHKey` / `FleetSudoPassword`
  generate a credential when the Secret has none, which is right when the
  operator can then install it on the host. A rack host is keyed and given its
  account by MDM *before* the cluster sees it, so a minted credential is one no
  host has heard of: a generated SSH key fails every dial forever while reading
  as a key problem, and a generated sudo password is XOR'd into
  `/etc/kcpassword`, which breaks auto-login, so Virtualization.framework has
  no console and every `tart run` fails for the life of the host. Both are
  reachable in the window before ESO's first sync, so the static kind uses
  `ReadFleetSSHCredentials`, which errors and requeues instead.
- **Reboot is a PDU outlet.** Apple silicon powers on when mains is applied and
  every fleet host runs `pmset autorestart 1`, so cutting and restoring an
  outlet is a cold boot with nobody at a console. `internal/power` holds the
  drivers, and the only one shipped today is `shelly`, which is scoped to home
  and office prototypes: a colo rack's switched PDUs get their own driver.
  `power.Cycle` drives off/settle/on itself rather than using a
  device's native cycle verb, because the settle interval is the one parameter
  that matters and no two devices agree on it. It verifies the outlet actually
  went off before powering back on: a cycle that silently failed to cut power
  would return success, and the caller would wait out a boot that never happened
  and count the recovery as attempted.
- **Giving up quarantines the host.** The Scaleway kind's bootstrap-exhaustion
  path releases the host so a *different* mini gets claimed, which works because
  the pool is a vendor's and refills itself. Hand our own pool the same box back
  and the next reconcile claims it again, so the Machine loops on the one host
  that cannot work. `status.quarantined` takes it out of the pool; it is
  controller-set and operator-cleared, so a bad box stays out until a human says
  it was fixed.
- **It keeps its tailnet identity, and its router path does not depend on it.**
  A rented mini joins the tailnet as an ephemeral device, which Tailscale
  deletes 30 to 60 minutes after it was last seen, however long it had been
  online. (Tailscale's docs say an ephemeral device present for four hours
  "will count as a standard tagged device"; that is billing, not removal.)
  That suits rented capacity, which is wiped on release and can be re-joined
  over its public address. A rack mini joins as a standard device
  (`TailscalePersistentDevice`, set by `rackFleetConfig`) and its SSH ingress
  guard admits its subnet routers (see "SSH ingress guard"), so a box that sat
  powered off comes back reachable both ways. On 2026-09-18 the BER1 prototype
  had neither: after a few days unpowered with the MachineDeployment at 0, it
  came back answering LAN ping, its device deleted from the tailnet, and `:22`
  silently dropped for the router, leaving the console as the only way in. A
  standard device outlives its host, so retiring a box for good (or
  re-imaging it) means deleting its device in the Tailscale admin console.
  An already registered ephemeral device is not converted by a re-push:
  `tailscale up` only uses the key when it has to log in again. The
  `tailscale-device-reaper`, once out of dry-run, still deletes a device
  unseen for its `graceHours` (7 days), so the router entry in the guard, not
  the standard device, is what reaches a box that was off for longer.
- **Delete releases the claim and stops.** No reinstall, no wipe: no API can do
  either to hardware in our own rack. That makes Stage 2 of the delete path
  (dropping the node identity) matter *more* than on rented capacity, not less:
  nothing wipes the disk afterwards, so the kubeconfig stays on the box until
  the next claim overwrites it.

  The same reasoning binds every OTHER path that lets go of a host, which is why
  they all go through `retireHost`: bootstrap exhaustion, and a claim lost
  because the inventory record was deleted or released out of band. Bootstrap
  starts tart-kubelet before its last fatal step (`installLogShipper`), so a
  host can exhaust its attempts while already registering a Node and holding a
  working long-lived token. Retiring it therefore has to revoke that identity,
  delete the Node, and drop the TOFU fingerprint. Skip any one and the damage
  lands on the NEXT host: the replacement is issued the same credentials and the
  same Node name while the retired box keeps running, the stale Node keeps the
  retired host's providerID (which tart-kubelet will not overwrite), or the old
  host's SSH pin rejects a healthy replacement until it is quarantined too.

### The first dial

A rented mini has a public IP the operator can reach before anything is
installed. A rack mini does not, and it is not on the tailnet yet either: 
bootstrap is what puts it there. So `RackHost.spec.address` is the in-rack LAN
address, reached through a **subnet router in the rack** that advertises it,
with a matching `tcp:22` grant in `infra/tailscale/acls.json`.

**Advertise a /32 per host, not the rack's prefix**, for as long as the
catch-all `*->*` grant at the top of that ACL file still exists. A catch-all
subsumes every narrowing below it, so what an advertised route actually exposes
today is every address in it, on every port, to every device on the tailnet:
three clusters' nodes, the rented Mac mini fleet, ops laptops, and every Tart
runner VM holding a tailnet identity. The BER1 prototype's router sits on a HOME
network, where a /24 would hand CI runner VMs the router admin page and every
personal device in the house. The cost of a /32 is that the address becomes
load-bearing in two places, the grant and `RackHost.spec.address`, so give each
host a DHCP reservation and update both together.

**Put the router's own LAN address in `rackFleet.sshIngressAllowCIDRs`** (a
host can override it with its own). The router forwards with SNAT, so that
address is the source every dial through this path arrives from, and the host's
SSH ingress guard drops it otherwise. The chart refuses to render a rack host
without one. Give the router a DHCP reservation too: a new lease is dropped by
every guard in the rack until the value is updated.

**The cluster reaches that address through an egress Service, not directly.**
A Pod has no route to a subnet-routed address; only the Tailscale proxies do.
So the machine reconciler creates a second egress Service per host, named
`rack-<rackhost>`, annotated `tailscale.com/tailnet-ip` with the host's address,
and dials that. It is the mirror of the per-Machine Service beside it: that one
carries `tailscale.com/tailnet-fqdn` and only works once the mini IS a tailnet
node, which is exactly what bootstrap has not done yet.

**And the ProxyGroup has to accept routes**, which is the part with no obvious
symptom. A proxy that does not answers `no matching peer` for a subnet-routed
address while the Service still resolves to a ClusterIP, so every connection
hangs and nothing anywhere names a route as the cause. That is what the
`macminiEgress.proxyGroup.acceptRoutes` ProxyClass in
`infra/helm/tailscale-operator` is for. Every other egress target in the cluster
is a tailnet node reached by its own FQDN, which is why no fleet before this one
needed it. Diagnose with:

```bash
kubectl -n tailscale-operator exec macmini-egress-0 -- tailscale debug prefs | grep RouteAll
kubectl -n tailscale-operator exec macmini-egress-0 -- tailscale ping 192.168.0.41
```

`RouteAll: false` or `no matching peer` is this, not a host fault and not the
ACL.

Routing it separately from the host's own tailnet identity is deliberate:
`installTailscale` stops and replaces tailscaled, which over a session
transported by the host's own tailnet identity would drop the tunnel it is
riding: exactly why the drift loop's tailnet fallback has to set
`SkipTailscaleInstall`. Through a separate router the session survives, so a
rack host can be fully bootstrapped in one pass. The drift loop still falls back
to the per-machine egress Service once the host has joined, for the case where
the LAN address stops answering.

That LAN prefix is **not** in `autoApprovers`. The Connector's Service CIDR is,
because a Pod re-advertises it on every rollout and manual approval would break
the route each time; a rack's subnet router is a long-lived box that advertises
once, so auto-approval would buy nothing and would let any device holding the
approver tag put a private prefix into the tailnet's routing table.

### Two prerequisites before a real rack replaces the prototype

Both are cheap to do early and expensive to retrofit, and neither is visible
from the code.

**1. Remove the catch-all grant before widening past /32.** A rack wants its
mini VLAN advertised as one prefix rather than a /32 per host, and that is only
safe once `{"src": ["*"], "dst": ["*"], "ip": ["*"]}` is gone from
`infra/tailscale/acls.json`. While it is there it subsumes every narrowing
below it, so an advertised prefix is reachable on every port by every device on
the tailnet, CI runner VMs included: those execute customer build code and would
gain SSH to every mini in the rack. The per-env grants in that file were written
to survive the removal (their comment says exactly that), so the work is an
audit of what still depends on the catch-all, chiefly Talos node access and ops
laptops, not a rewrite. Until it is gone, keep advertising per-host /32s, which
is correct but does not scale past a handful of boxes.

**2. Run two subnet routers, not one.** Tailscale supports HA subnet routing:
two nodes advertising the same prefix, one primary, automatic failover. A single
service node is a single point of failure for every first dial and every drift
push into the rack, which is the one path that has no fallback. Already-Ready
Nodes keep working without it, which is precisely why this will look fine right
up until a host needs re-bootstrapping and cannot be reached. The rack's own
power doctrine is to dual-feed the pets; the service node is a pet.

Both are also why the prototype's /32 is not merely a prototype artefact: it is
the shape to keep until (1) is done.

### Operating

Inventory is chart-rendered from `rackFleet.hosts` in the env's values, so
adding a mini is a reviewed values PR rather than a `kubectl apply` in someone's
history.

```bash
kubectl get rh                      # pool, address, claimed-by, power, quarantined
kubectl get rh -o wide              # + serial and site
kubectl get rasm                    # the Machines, with the host each holds
```

`replicas` is a machine count and must not exceed the claimable hosts: a Machine
with nowhere to land sits on `NoAvailableHost` forever, leaving the
MachineDeployment permanently below spec and a `helm upgrade --wait` gated on
that count running out its ceiling. It defaults to the declared host count. An
explicit `0` is meaningful and is preserved (`dig`, not `default`): it declares
the inventory, lets the RackHosts land and be power-polled, and holds the claim
back until the boxes are reachable.

**Reboot a host remotely:**

```bash
kubectl annotate rackhost <name> tuist.dev/power-action=cycle
```

`on`, `off` and `cycle` are one-shot; the controller clears the annotation after
acting, including on failure: a failing `cycle` left annotated would
power-cycle the box on every reconcile. `off` and `cycle` are refused while the
host's Node is Ready and schedulable; cordon it first, or add
`tuist.dev/power-action-force=true`.

**A host nobody can power-cycle** reports `PowerReachable=False` and publishes
`capt_rackhost_power_reachable 0`. That is not a host fault: the mini may be
running perfectly, but it means the fleet has lost its only remote repair for
that box, and it is worth catching before the reboot is needed rather than at
the moment it cannot be done. `capt_rackhost_claimed` summed per pool is the
rack's utilisation; free == 0 is what a scale-up will fail to satisfy.

**A quarantine expires on its own** after `--rackhost-quarantine-retry-after`
(default 30m), and the host returns to the pool with a `QuarantineExpired`
event. That is the normal path, and it is not a convenience: clearing one by
hand needs write access to `rackhosts/status`, which the operator's ClusterRole
has and a human reaching the cluster through the kubectl gateway does NOT, so
without the expiry a quarantined box is capacity nobody on call can recover. It
is usually the right answer too, since most exhaustions are a verdict on the
config being pushed rather than on the hardware, and the fix ships in the next
operator image.

If you do hold the permission, releasing one early is:

```bash
kubectl patch rackhost <name> --subresource=status --type=merge \
  -p '{"status":{"quarantined":false,"quarantineReason":"","quarantinedAt":null}}'
```

A host that keeps re-quarantining is a real fault: read `status.quarantineReason`
and the machine's `BootstrapFailed` events, and set `spec.unclaimable: true` to
take it out of the pool for good while you work on it. A negative
`--rackhost-quarantine-retry-after` disables the expiry fleet-wide, which only
makes sense in a cluster where somebody can actually write that status.

**Recover a host whose guard drops its router.** A host bootstrapped before its
router was in its allow list, or whose router changed address, answers LAN ping
and times out on `:22` from the router. If it is still on the tailnet, the drift
loop's tailnet fallback delivers the new list on its own. If it is not, only
its console can (Screen Sharing over the LAN only helps if it was enabled on
the box; on the BER1 prototype it was not). Add the router to the anchor file
the re-arm LaunchDaemon reloads every minute:

```bash
sudo sed -i '' 's|{ 100.64.0.0/10|{ 100.64.0.0/10, <router-lan-ip>/32|' /etc/pf.anchors/tuist.sshguard
sudo /usr/local/bin/tuist-pf-sshguard
```

The next bootstrap or drift push rewrites the file from the RackHost, and
`installTailscale` re-joins a host whose device was deleted.

**Take a box out of the pool** without deleting its inventory record (bench
work, an RMA) by setting `spec.unclaimable: true`. It stops the next claim; it
does not evict the current one, the same shape as `Node.spec.unschedulable`.

**Renaming a machine kind leaves three objects behind**, in every cluster the
old name reached. The deploy workflow ships CRDs with `kubectl apply -f crds/`,
which adds and updates but never prunes, and the superseded MachineTemplate
carries `helm.sh/resource-policy: keep` so Helm will not collect it either. The
MachineDeployment rolls onto the new kind and the old kind's objects stay:

```bash
kubectl get crd | grep <oldkind>
kubectl get <oldkind>machinetemplates -A
kubectl get machinesets -n <ns> -o custom-columns=\
NAME:.metadata.name,INFRA:.spec.template.spec.infrastructureRef.kind
```

They are inert once the fleet has drained through the old controller, since
nothing reconciles the kind any more and the retained MachineSet is at zero
replicas. Removing them is cluster-admin work and is not available through the
kubectl gateway on any tier, staging included: `machinesets`,
`<kind>machinetemplates` and `customresourcedefinitions` are all read-only
there by design. Delete oldest reference first so no live object is left
pointing at a kind that is going away:

```bash
kubectl delete machineset <old-revision-machineset> -n <ns>
kubectl delete <oldkind>machinetemplate <name> -n <ns>
kubectl delete crd <oldkind>machines.infrastructure.cluster.x-k8s.io \
                   <oldkind>machinetemplates.infrastructure.cluster.x-k8s.io
```

Check `spec.replicas` and that it owns no Machines before deleting a MachineSet:
the other MachineSets under a MachineDeployment are its rollout history and are
not stale.

**Restart CAPI core afterwards.** Its Machine and MachineSet controllers start a
dynamic watch per infrastructure kind they encounter, and that watch lives for
the process lifetime: nothing tears it down when the CRD goes away. The
controller is left listing a kind the apiserver no longer serves, roughly five
lines a minute forever, which on an otherwise silent pod is its entire log
output:

```
failed to list infrastructure.cluster.x-k8s.io/v1alpha1, Kind=<OldKind>:
the server could not find the requested resource
```

```bash
kubectl rollout restart deploy/capi-controller-manager -n capi-system
```

Nothing else reconciles the old kind, so this is log volume rather than a fleet
fault, and no fleet changes across the restart.

## Rack-owned Linux hosts

`RackLinuxMachine` joins x86 Linux machines we own (the BER1 MS-01s) and keeps
them converged. Its inventory is `RackLinuxHost`, rendered from
`rackLinuxFleet.hosts` and named after each machine's SMBIOS UUID; the name the
host runs under is `spec.hostname`. How a box is installed is in
[`infra/rack-nodes/AGENTS.md`](../rack-nodes/AGENTS.md).

**A host is its own Machine** (`racklinuxhost_machine.go`). With
`--rack-linux-cluster-name` and `--rack-linux-bootstrap-secret-name` set, the
host controller keeps a CAPI Machine and the `RackLinuxMachine` it owns under
the host's name, labelled with its role. A box is one host and upgrades in
place, so there is no MachineDeployment claiming boxes from a pool. The
machine's providerID is `rack-linux://<site>/<host UUID>`, so it survives a
rename.

**A host goes through `status.provisioning.state`**: `Registering` (declared,
with no install it can be given yet), `Provisioning` (an install is published
and it has not run it), `Provisioned` (on the tailnet, running the install its
`spec.reinstallGeneration` asks for) and `Deprovisioning` (deleted, being
retired). `status.provisioning.message` says what it waits for.

**The first dial is the host's own tailnet address.** The install joins the
host to the tailnet with a single-use tagged key, so no subnet router is
involved: `RackLinuxHostReconciler` finds the device through the Tailscale API
(the device it recorded, or one whose OS hostname is `spec.hostname` and that
carries every tag in `spec.tailnet.tags`), and the machine reconciler dials it
through an egress Service, `rack-linux-<host UUID>` in the egress namespace,
annotated `tailscale.com/tailnet-ip`. The operator reads the OAuth client from
`--rack-linux-tailscale-secret-name` (`client-id`, `client-secret`, Devices Core
and Auth Keys scopes on the rack tags); its device list is not filtered by tag.
The operator never touches tailscaled, so a session over the host's own tailnet
identity is safe.

**Every install registers a new device.** Once the newest device is connected
and an older one of the host is not, the host controller deletes the older one
and renames the newest to the hostname. Two connected devices are left alone
and reported as `DuplicateDevices`. The machine reconciler keys reinstalls off
the device ID: a new one is held to the SSH host key the install gave it
(below), or, for an install the operator did not publish (a per-host stick),
pinned to the first key it presents.

**The host controller publishes installs** (`racklinuxhost_install.go`,
rendered by `internal/rackinstall`) when `--rack-linux-fleet-name` and
`--rack-linux-install-server-url` are set: for a host with no tailnet device
yet, and for one whose `spec.reinstallGeneration` is above
`status.provisioning.installedGeneration`. It mints a single-use join key for the host's
tags and an ed25519 SSH host key, and writes the autoinstall seed, which carries
both, and an iPXE script under the boot MAC to the `<fleet>-boot` Secret, which
the rack boot server serves, again whenever the Secret lost them, with the
host's UUID and the key's ID beside them. `status.install` records the key, the
MAC, the generation, the device the install replaces and the host key's
fingerprint. A join key lives two hours: one no host fetched yet is renewed 45
minutes before it expires, and one a host fetched is kept until it expires,
since a new one would not reach that installer. A key the Secret no longer
carries, renewed or withdrawn, is revoked. When the install's device joins, the
host controller pins its host key for that device before recording the device,
so the machine reconciler's first dial is held to the key the operator
generated rather than trusting the first one it sees. The boot MAC is `spec.bootMAC`, or the management port the
machine announced (its `RackLinuxCandidate`, below), in `status.bootMAC`; a
host with neither is `Registering` until its stick announces it. The host takes
what the machine announced once, into `status.hardware` (product, serial, NICs,
boot MAC, `pinnedAt`), and never again: a candidate changed since moves
nothing, and one with a `status.conflict` gives nothing (`HardwarePinned`
False, `CandidateConflict`). To take it again, as after replacing a NIC, delete
the candidate and the host's `status.hardware`, and boot the stick. The fleet
key's public half and `--rack-linux-authorized-key` are authorized, and the
console password is minted once per host into `<fleet>-console`. The host
controller reads each host through the manager's uncached `APIReader`: CAPI's
patch helper writes conditions before the rest of the status, and a reconcile
that read the host from the cache in between would mint a second key. A host's
installer is its install stick, which fetches the seed for its MAC from the boot
server (`rackinstall.StickUserData`), or a netboot. A host is rebooted into an install
only once the boot server answering its netboot reported it servable in
`status.boot.servers` (`WaitingForBootServer` until then): the one holding the
site's provisioning address, or, for an `edge`, every other connected edge of
its site, since the edge's own boot server goes down with it and another takes
the address over. A reinstall of a
connected host sets `BootNext` over SSH and reboots it, once: to a boot entry the script creates for a USB disk carrying
`nocloud/tuist-install-stick`, or else to the PXE entry for the MAC; one of a
host off the tailnet power-cycles it through AMT into its network boot (below).
A host with `spec.online: false` is not rebooted into an install. A new device
other than the replaced one withdraws the install and records its generation as
installed; one that comes back on its old install reports `ReinstallDidNotBoot`
after half an hour, and raising the generation again retries. Lowering the
generation back cancels a reinstall. An `edge` host gets an install only while
another `edge` of the same `spec.location.site` is connected to the tailnet to
serve it, or once it was rebooted into it; otherwise its install is withdrawn
and it is installed from a stick. `storage` has no layout yet. The `Installed`
condition says which step a host is on.

**The rack's boot server** (`cmd/rack-boot`, `internal/rackboot`) runs from the
operator's image as the chart's `<fleet>-boot` DaemonSet on each edge node of
the site, with host networking. It binds TFTP and HTTP to the provisioning
address with `IP_FREEBIND`, so the edge holding the address (keepalived's
master) answers and the other takes over the moment the address moves. It
watches the `<fleet>-boot` Secret through the API (its Role reads that Secret
alone) and serves, over TFTP, iPXE's Secure Boot shim, the signed iPXE, both
baked into the image at `/opt/rack-netboot`, and `boot.ipxe`; over HTTP, each
host's iPXE script by its boot MAC and by its UUID, its seed, and the
installer's kernel, initrd, Ubuntu shim and ISO. The ISO is downloaded once per
checksum into `/var/lib/tuist-rack-boot` on the node, from another edge over
the edges' link (`vrrp0`, where each offers its verified ISO and nothing else)
before the internet, verified, and the rest extracted from it. A rack node
reaches no Service address, so it reads the API server from
`/etc/tuist/kubernetes-api`, which the converge writes. Once its ISO is ready,
each edge's boot server reports each install it holds servable in the host's
`status.boot.servers`, with whether it holds the address, and again once it
takes the address over; the list is keyed by the install's join key, and the
operator writes nothing there.

**An install's seed goes only to its host** (`internal/rackseed`). The seed
carries the join key and the host key. For a host whose TPM is pinned
(`status.tpm`), the boot server seals it to that TPM: a machine asks with
`rack-node seed`, which posts to `/hosts/<mac>/seed` and, when the boot server
answers 401, attests with an attestation key its TPM makes; the boot server
checks that key is a TPM's restricted key, and encrypts the seed under a secret
it wraps with credential activation to the pinned endorsement key and that
attestation key, which only that TPM can unwrap. Anyone may ask, since nothing
else can open the answer. A plain `GET` of `user-data` for such a host, as a
netboot's cloud-init makes, gets the install stick's loader, which asks with
`rack-node seed` (fetched from `/tools/rack-node`). A host with no pinned TPM
gets its seed, over either path, only on its segment on a MAC, read from the
kernel's neighbor table for the address that asked, that is its boot MAC or one
of the NICs in its `status.hardware`, never what its candidate lists now, and
after the first only on that MAC. The first hand-out is recorded in
`status.boot` (`servedTo`, `servedAt`, `attested`) before it happens, and one
that could not be recorded is not made. It checks the host's `status.install`
first, so a superseded install is not handed out from a stale Secret. The rest
of an install is not secret.

**A host's TPM is pinned once** (`racklinuxhost_tpm.go`): from the endorsement
key the machine's first announcement carried, when the host takes its hardware
from its candidate, or else, once the host runs its own install, read with
`rack-node ek` over SSH, which holds the host to the host key the operator gave
the install. `TPMPinned` says which; a read that fails is tried again an hour
later. Pinning another, as after replacing a board, is deleting `status.tpm`.

**Machines announce themselves.** While nothing is published for it, a
machine's install stick posts its SMBIOS UUID, serial, product, NICs and TPM
endorsement key (`rack-node ek`) to the boot server's `cgi-bin/announce`, which accepts only those lines, at most 4096
bytes, and keeps a `RackLinuxCandidate` per machine, named after its UUID, with
the boot MAC it names (its i226-LM), for at most 256 machines. Anyone on the
segment can announce, so what a machine announced first is kept: an
announcement under its UUID with another serial, product, endorsement key or
set of NICs, or one that adds an endorsement key the first lacked, is refused
with HTTP 409 and kept only as the candidate's `status.conflict`. Its Role creates
candidates and patches their status; it reads and patches hosts' status for
`status.boot` and nothing else of them. The operator (`racklinux_candidates.go`)
marks each candidate with the hostname of the `RackLinuxHost` named after its
UUID, and drops an undeclared one no boot server has heard from for a week; a
declared one stays, since its host takes its boot MAC and model
(`status.hardware`) from it. Candidates exist because the MS-01 can only
describe itself from its install stick. A machine model with a BMC reports its
inventory out of band, and a fleet of those should take a host's hardware from
the BMC and drop `RackLinuxCandidate` and the announcements with it.

Not yet done: a host with no pinned TPM gets its seed on a MAC, which a machine
on the segment can spoof. The first announcement under a UUID is trusted, so a
machine that announces before the real one can stand in for it; checking the
endorsement key's certificate against the TPM vendor's CA would limit that to
real TPMs. The loader, rack-node and the netboot chain come over plain HTTP on
the segment, so a machine that can answer for the provisioning address can run
code on the real host, which its TPM then serves; sealing the seed to the
host's measured boot (a PCR policy) would close that.

**A rename is a new `spec.hostname`.** The host keeps its UUID, its Machine and
its providerID. The host controller finds the host's recorded device although
its OS hostname is still the old one, and renames it; the machine reconciler
deletes the Node the host joined under (only one with the host's providerID),
clears the owning Machine's `status.nodeRef`, since CAPI records a Machine's
Node once and drains and deletes that one when the Machine goes, and converges
with the rejoin: the new OS hostname, the kubelet's identity
dropped, and a bootstrap token for the new name. `status.nodeName` on the
`RackLinuxMachine` records the name it joined under. An edge's rename also
needs the site definition's edge entries (`infra/rack-switch-fleet`) renamed.

**Deleting a `RackLinuxHost` retires it** (`racklinuxhost_retire.go`, finalizer
`racklinuxhost.cluster.x-k8s.io/finalizer`). The controller withdraws its
install and deletes its Machine, and waits for the Machine to go: its
`RackLinuxMachine` stops the kubelet over the tailnet and deletes the Node
first. Then it deletes the host's egress Service, its tailnet devices (the
recorded one and any other with its hostname and tags) with their host key
pins, and its key in `<fleet>-console`, and drops the finalizer. A step that
fails keeps the finalizer and is retried. The host's AMT Secret stays: it
belongs to the box, whose AMT keeps the password.

**A node's configuration is data, and a node agent applies it**
(`rack_linux_converge.go`, `internal/racknode`, `cmd/rack-node`). The machine
reconciler renders a `RackNodeConfig`, the host's files (kubelet unit and
configuration, CA, local CNI, containerd's registry mirror, sysctl, modules,
the management port's networkd file, `/etc/tuist/kubernetes-api`), the exact
kubelet release the control plane runs and the hostname, into the
`RackLinuxMachine`'s `status.nodeConfig`, hashed. `rack-node` applies one: it
writes only files whose content or mode differs, loads modules and sysctls,
installs containerd with its default configuration on the systemd cgroup
driver, installs exactly the named kubelet from pkgs.k8s.io and never
downgrades it, sets the hostname, restarts containerd or the kubelet when
their files changed, when they are not running, or when the host has not
finished applying this configuration (`/var/lib/tuist/rack-converge.hash`),
and leaves a host kubeadm joined alone. Its result is structured
(`changed`, `restarted`, `applied`, `needsBootstrap`, `foreignJoin`), not an exit
code.

The operator runs it over SSH (`rack-node apply`, the request on stdin and the
result on stdout, the binary uploaded under `/usr/local/lib/tuist/` by its
digest when the host lacks it) to join a host, for a new tailnet device, a
rename, and a Node NotReady for five minutes. Once a node is joined, the node
agent, the chart's `<fleet>-node-agent` DaemonSet running `rack-node agent`
privileged in the host's PID namespace on every rack Linux node, keeps it: it
finds its machine from its Node's providerID, applies the published
configuration within 30 s of a change and every five minutes otherwise, and
reports in `status.agent` (`appliedHash`, `appliedAt`, what it changed,
restarted, or why it failed). While the agent is live (it reported within 15
minutes, without an error), the operator leaves the node to it; a new
configuration it has not applied three minutes after publishing, or no live
agent, is applied over SSH, and without an agent every hour too. The two
never overlap on a host (`flock` on `/run/tuist-rack-node.lock`). A control
plane on a minor other than the operator's `KubernetesMinor` holds converges
(`ConvergeHeld`) until the operator renders for it. Before any converge over
SSH it refuses while `kube-system/cilium` would schedule onto a node carrying
`cilium.io/no-schedule=true`.

**The kubelet's identity is `system:node:<hostname>`, not an operator-minted
ServiceAccount.** When `rack-node apply` reports `needsBootstrap` (the kubelet
has no client certificate valid for ten more minutes), the reconciler deletes a
stale Node of that name (only one with this host's providerID, or none), mints
a one-hour kubeadm bootstrap token labelled `tuist.dev/bootstrap-node`, applies
again with a bootstrap kubeconfig in the request (never in the published
configuration), and deletes the token once the kubelet holds its certificate.
kubeadm's bindings approve the CSR and later rotations. The labels
(`node.cluster.x-k8s.io/instance-type=rack`, `cilium.io/no-schedule=true`, the
role's), the taints, the providerID (`rack-linux://<site>/<host UUID>`) and the
local CNI (`10.254.254.0/24`) are all in place before the kubelet first starts.

**AMT is activated on the hardware the fleet lists** (`racklinuxhost_amt.go`).
A host whose model (`status.hardware.product`) is one of
`--rack-linux-amt-product` (the chart's `rackLinuxFleet.amt.products`), or that
sets `spec.amt.activate: true`, and that has a connected tailnet device, gets
(`spec.amt.activate: false` opts a host out), over SSH, the pinned `rpc` (the Device
Management Toolkit's AMT client, installed at `/usr/local/lib/tuist/rpc-<version>`
from the release tarball's digest), which reads AMT's state and, while AMT is
pre-provisioned, runs `rpc activate --acm`. The provisioning certificate
comes from `--rack-linux-amt-provisioning-secret-name` (`pfx`, `password`,
synced from 1Password `AMT_PROVISIONING_CERT`). The admin password is generated
and stored in the Secret `<host UUID>-amt` before the first attempt, and that
Secret outlives the host: AMT keeps the password. Secrets reach `rpc` through its
environment, exported by the script on the SSH session's stdin, so they are on
no command line and in no file on the host. A failed attempt is recorded in
`status.amt.activationError` and retried after an hour; an activated host is
read hourly. `AMTActivated` reports the outcome. Turning the switch off does not
deactivate AMT. AMT checks the certificate's domain against the DHCP domain
(option 15, `management.edge.domain`) or MEBx's PKI DNS suffix. A
pre-provisioned MS-01's AMT takes no DHCP lease and ignores the host's, so a
direct activation fails with `adminsetup failed: returned 5`. The script
therefore activates client control mode first (no certificate), waits for AMT's
own lease, and then upgrades to admin control mode with the certificate; a host
left in client control mode is upgraded on the next attempt. `rpc` is a 3.0
prerelease: 2.x's transport to AMT without Intel's LMS daemon hangs on the
MS-01. Each `rpc` run is bounded by `timeout`.

Activated AMT is then configured, in the same run or the next: MEBx's factory
password is replaced with one generated and kept as `mebx-password` in the
`<host UUID>-amt` Secret (`status.amt.mebxPasswordSet`), and AMT is moved to a
static address, so it keeps one whatever happens to the host:
`spec.amt.address` (with its prefix length) and `spec.amt.gateway`, or one from
`--rack-linux-amt-address-range` with `--rack-linux-amt-gateway` (the segment's
gateway with its prefix length, which the address carries). A range address is
recorded in `status.amt.assignedAddress` and kept: the one given before, else
AMT's current one when it is in the range and free, else the lowest free one.
The operator reads a host's AMT before it asks anything of it, so a host
declared again for a box whose AMT is already activated keeps AMT's address.
Staging puts the edges' AMT on the provisioning segment outside its DHCP range.
AMT reports its old address for a while after it is given one, and none while
its link is down, so the address is given again at most every two minutes and
never while AMT reports its link down. A failed configuration is recorded in
`status.amt.configurationError` and retried after an hour; it does not take
`AMTActivated` down.

**`spec.online` is the host's power state, and `tuist.dev/reboot` a one-off
reboot** (`racklinuxhost_amt_power.go`). A host on the tailnet is on; for one
that is not, AMT is asked every ten minutes (`status.power`). A host that
should be off is shut down from its own OS while it is on the tailnet and
powered off through AMT otherwise, one that should be on and is off is powered
on, and changes are five minutes apart (`PowerMatchesOnline`). The annotation
takes `cycle` (hard power cycle), `reset`, or `pxe` (a power cycle into the
network boot: the boot order cleared, the boot settings written back,
the configuration made the next one, and Force PXE Boot chosen, which boots the
firmware's first network entry). The operator makes
the change once, records it in `status.amt.lastPowerAction` and removes the
annotation. AMT answers on the management segment, where only the active edge
(the one holding the site's floating addresses) has an address, so the operator
tries the connected edges of the host's site (other edges first, the host itself
last), takes the first whose `ip route get` puts AMT's address on a link of its
own, and sends WS-MAN with digest authentication to AMT's address (`status.amt.address`) on its TLS port, 16993, through it: an activated AMT serves WS-MAN only there, with a self-signed certificate. The first power change pins that certificate's SHA-256 as `tls-sha256` in the `<host UUID>-amt` Secret, and later ones hold AMT to it; a reactivated AMT needs the key deleted.
It needs AMT activated and the host's `<host UUID>-amt` Secret, not the host itself:
a host that is off the tailnet is powered too. The MS-01's firmware keeps a fixed
boot order, the installed disk first, and rewrites `BootOrder` at every boot, so
a power cycle boots the disk; a reinstall requested for a host off the tailnet
uses `pxe` instead, and the install is published under the machine's SMBIOS
UUID (`status.amt.uuid`, from AMT) as well as its boot MAC, so the boot server
serves it to whichever NIC netboots. That needs the host's firmware set up to
netboot (network stack on); Secure Boot can stay on.

```bash
kubectl get rlh <uuid> -o jsonpath='{.status.amt}'
kubectl annotate rlh <uuid> tuist.dev/reboot=cycle
kubectl patch rlh <uuid> --type merge -p '{"spec":{"online":false}}'   # power it off
```

**Deleting a Machine** stops the host's kubelet and removes its certificate over
SSH (bounded, best effort), then deletes the Node, the egress Service and the
host key pins. A host that is off keeps its kubelet and re-registers its Node
when it returns; reinstall it to retire it. The host controller creates the
Machine again, which joins the host afresh: that is how to force a re-join.

```bash
kubectl get rlh                     # hosts: hostname, role, state, tailnet address, power
kubectl get rlh -o wide             # plus the boot MAC, the device and a published install's key
kubectl patch rlh <uuid> --type merge -p '{"spec":{"reinstallGeneration":2}}'   # reinstall
kubectl delete rlh <uuid>           # retire a host the chart no longer declares
kubectl get rlm -o wide             # machines: node name, phase, last converge
kubectl describe rlm <name>         # HostConverged / TailnetReady / NodeReady, events
```

**Logs and exec.** The API server cannot reach a tailnet address, so each host
also gets a kubelet egress Service, `rack-linux-<host UUID>-kubelet`, outside the
ProxyGroup. The Tailscale operator runs a proxy Pod of its own for it, which
forwards every port to the host's tailnet address. The kubelet runs with
`--cloud-provider=external` and leaves the Node's addresses to the operator
(`rack_kubelet_address.go`): InternalIP is the tailnet address, ExternalIP the
proxy Pod's address while that Pod is Ready, and Hostname the host's name. The
staging API server dials ExternalIP first, so `kubectl logs`, `exec` and
`port-forward` go through the proxy, and the ExternalIP follows the Pod when it
moves. The operator also lifts `node.cloudprovider.kubernetes.io/uninitialized`
once the addresses are set, without waiting for the proxy. Until the proxy Pod
is Ready, `logs` and `exec` time out as for the Mac minis.

```bash
kubectl -n tailscale-operator get pod -l tailscale.com/parent-resource=rack-linux-<host>-kubelet -o wide
kubectl get node <host> -o jsonpath='{.status.addresses}'
```

## Host macOS updates

Host macOS updates are operator-run waves, one drained host at a time. They are
never automatic and not driven by MDM: NanoMDM cannot enforce update policy.
`bootstrap.Run` and the drift loop (`installSoftwareUpdatePolicy`, part of
`HostConfigHash`) write this into `/Library/Preferences/com.apple.SoftwareUpdate`
on every rented and rack host:

| Key | Value | Effect |
|---|---|---|
| `AutomaticCheckEnabled` | `true` | Catalog checks only. `softwareupdate --list` shows what the next wave installs |
| `AutomaticDownload` | `false` | No OS update is staged in the background |
| `AutomaticallyInstallMacOSUpdates` | `false` | No unattended OS install |
| `SplatEnabled` | `false` | Background Security Improvements wait for a wave. Each one restarts the host |
| `CriticalUpdateInstall` | `false` | Critical updates wait for a wave |
| `ConfigDataInstall` | `true` | XProtect, Gatekeeper and other data files keep installing: no restart, no OS version change |

`installSetupAssistantSuppression` writes `SkipSetupItems` (managed and local,
system-wide and for the auto-login user) plus the `DidSee*`/`LastSeen*` flags, so
the console session never opens on a Setup Assistant pane. Two panes change the
host when clicked through: "Update Mac Automatically" turns automatic installs
back on, and FileVault disables auto-login, which leaves Tart without a console.

- These are local preferences, honoured on macOS 26. `SplatEnabled` is
  undocumented (Apple's internal name for Background Security Improvements) and
  can change without notice. Re-check the table on the first macOS 27 host
  before its wave: Apple removes the `com.apple.SoftwareUpdate` MDM payload in
  27, and managed update policy moves to the
  `com.apple.configuration.softwareupdate.settings` declaration, which needs a
  DDM server beside NanoMDM.
- On an MDM-enrolled rack host ManagedClient owns `/Library/Managed Preferences`
  and can rewrite it. The durable form there is a `com.apple.SetupAssistant.managed`
  configuration profile, which NanoMDM can install.
- The `LastSeen*` flags lapse after a wave; `SkipSetupItems` does not. A pane that
  appears after a wave is missing from `setupAssistantSkipItems`: do not click
  Continue, add its key.

Check a host:

```bash
defaults read /Library/Preferences/com.apple.SoftwareUpdate
softwareupdate --history | grep -i -E 'xprotect|gatekeeper'
```

## Module layout

```
infra/cluster-api-provider-tuist/
├── api/v1alpha1/
│   ├── groupversion_info.go
│   ├── scalewayapplesiliconmachine_types.go (+ …template)
│   ├── scalewayelasticmetalmachine_types.go (+ …template)
│   ├── dediboxmachine_types.go (+ …template)
│   ├── ovhdedicatedmachine_types.go (+ …template)
│   ├── racklinuxhost_types.go / racklinuxmachine_types.go / racklinuxcandidate_types.go
│   ├── tuistcluster_types.go
│   └── zz_generated.deepcopy.go
├── controllers/
│   ├── macos/
│   │   ├── scalewayapplesiliconmachine_controller.go
│   │   ├── rackapplesiliconmachine_controller.go  # rack-owned minis
│   │   ├── rackhost_controller.go   # physical inventory: power, orphan claims
│   │   └── hostagent.go             # what both macOS kinds share once a host
│   │                                # is in hand: drift bookkeeping, terminal-
│   │                                # failure rules, sizing overlay, egress Service
│   ├── scalewayapplesiliconmachine_controller.go
│   ├── tuistcluster_controller.go
│   ├── fleetspread_controller.go
│   ├── orphan_reclaimer.go
│   └── linux/      # the Linux fleet kinds (Dedibox / OVH / Elastic Metal / rack)
│       ├── dediboxmachine_controller.go
│       ├── ovhdedicatedmachine_controller.go
│       ├── scalewayelasticmetalmachine_controller.go
│       ├── racklinuxhost_*.go       # rack hosts: install, Machine, AMT, power, retirement
│       ├── racklinuxmachine_controller.go / rack_linux_converge.go  # rack join + converge
│       ├── racklinux_candidates.go  # tidies what the rack boot servers list
│       ├── linux_cloudinit.go       # shared self-join script + kubelet config (Layers 2+3)
│       ├── kubelet_config_drift.go  # zero-downtime re-push of kubelet config to Ready nodes
│       └── kata_runtime_drift.go    # detect + repair a node that joined without the kata runtime
├── internal/
│   ├── power/        # PDU / smart-plug drivers (the rack's remote reboot)
│   ├── scaleway/     # Scaleway SDK wrapper
│   ├── rackinstall/  # a rack host's autoinstall seed, iPXE script and install stick
│   ├── rackboot/     # the rack boot server: TFTP/HTTP netboot, seeds, announcements
│   ├── racknode/     # makes a rack Linux host the node its RackNodeConfig describes
│   ├── rackseed/     # a rack host's seed, sealed to its pinned TPM; rackseedtest is a TPM in software
│   ├── tailnet/      # Tailscale API: devices and join keys
│   ├── credentials/  # fleet SSH keys + per-machine kubelet identities
│   └── bootstrap/    # SSH-driven kubelet/tart-cri install
├── cmd/manager/    # controller-manager entry point
├── cmd/rack-boot/  # the rack boot server, run on a rack's edge nodes
├── cmd/rack-node/  # applies a rack node's configuration, reads its TPM, asks for its seed
├── cmd/rack-seed/  # renders a seed for rack:write-install-usb
├── config/
│   └── rbac/       # ClusterRole for the manager
├── Dockerfile      # cross-builds the darwin/arm64 host artifacts (tart-kubelet,
│                   # tuist-log-shipper, tailscale) alongside the linux manager,
│                   # rack-boot and the signed iPXE it serves
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

## Bootstrap-time capabilities, and the once-at-bootstrap trap

The Linux self-join is rendered **once**, at bootstrap
(`renderLinuxBootstrapScript`), by whichever provider pod holds the leader lease
at that moment. Nothing re-runs it. That makes every capability the script
installs a one-shot decision, and it fails in a way that looks like anything but
a provisioning bug.

During a rolling provider upgrade the chart applies the new provider Deployment
and the fleet MachineDeployments in the same release. With `maxUnavailable: 0`
the OUTGOING pod keeps the lease until it terminates, so a Machine created in
that window is bootstrapped by the OLD build — which decodes the CR fine and
silently drops any spec field its Go struct does not have. On 2026-08-31 that
put `kataRuntime: true` boxes into production and canary bootstrapped by
`capi-scaleway@0.27.0`: Ready nodes, right pool, right taints, every DaemonSet
running, no error logged anywhere, and not one job taken — because the
`kata-qemu` RuntimeClass selects on a node label the old self-join never wrote.
It read as a scheduling bug for about an hour and was cleared by hand with
`kubectl delete machine`.

Two things follow, and both are load-bearing:

**Ordering cannot fix this inside one Helm release.** A `pre-upgrade` hook runs
before the new provider image is applied, and moving the fleet
MachineDeployments into a `post-upgrade` hook would take them out of the release
(hook resources are not tracked, and the default delete policy would reap them).
Splitting the provider into its own release ahead of the chart would work but
serializes every deploy behind a rollout that can wedge it. Convergence, not
ordering, is the answer.

**`strategy: OnDelete` means a spec change never rolls the fleet either.**
Flipping a bootstrap-time field on an existing MachineDeployment reaches exactly
zero live machines. So in-place repair is not just the nicer fix — it is the only
mechanism that converges at all.

### Adding a bootstrap-time capability

Anything the self-join installs that the node's schedulability depends on needs
all three of these, or it inherits the trap:

1. **An observable on the Node.** The check must read what actually decides the
   outcome — for kata that is the `katacontainers.io/kata-runtime` label the
   RuntimeClass selects on, not a provider version or a status flag, so a node
   that passes the check is one the scheduler will really place Pods on.
2. **A check on the Ready path**, next to `reconcileLinuxKataRuntimeDrift`, that
   reconciles that observable against the spec. Both paths render from one
   `hostOptions` builder (`ovhdedicatedmachine_controller.go`) so a new field
   reaches the bootstrap and the repair together rather than by remembering two
   call sites.
3. **A repair that is additive, never a re-bootstrap.** These boxes run live
   jobs, and the Kura cache boxes hold local state a reinstall destroys. The kata
   repair installs the runtime, registers the containerd handler, re-renders the
   kubelet unit, and restarts *containerd only* — which does not kill running
   containers, since their shims outlive it and reattach. It touches no apt
   source, no kubelet install, no `/data` mount, and never the kubelet itself, so
   it needs no drain, and it restarts unconditionally so that "the script exited
   0" always means "the running daemon loaded this config" (a restart skipped
   because the config file already looked right would let a stale daemon pass
   every file check). Order the steps so that **nothing that advertises the box
   to the scheduler runs before the proof**: here the runtime is verified first,
   the kata-labelled kubelet unit is written last, and the controller patches the
   live Node only on the script's exit status. Advertising an unrepaired box
   turns "no Pod ever schedules" into "every Pod wedged in ContainerCreating",
   which is harder to diagnose and burns the job instead of queueing it.

Note the trap is not OVH-specific. `DediboxMachine` and
`ScalewayElasticMetalMachine` share this renderer and the same once-at-bootstrap
property; only `OVHDedicatedMachine` carries a bootstrap-time capability today.

A repair that cannot complete must stay loud rather than retry quietly. The
`KataRuntimeReady` condition is marked False the moment the gap is observed,
before any SSH, and the `capt_node_kata_runtime_ready` gauge (0 = requested but
missing or unverified) is what the **Runner Box Missing Kata Runtime** rule alerts on
(Grafana Cloud, Alerts folder, `Runners` group, `for: 20m`, routed to Slack like
its siblings). `Machine.Status.Ready` is deliberately left alone: the node is a
healthy Kubernetes node, and failing it would make CAPI churn a box that needs a
two-minute in-place fix.

Kata's virtio-fs configuration backs guest RAM with files in `/dev/shm`. The
Linux default tmpfs ceiling is half of host RAM, below the runner node's
allocatable memory: concurrent guests can exhaust it while the host still has
free RAM, causing QEMU `kvm run failed Bad address` failures. The shared-memory
setup in `controllers/linux/kata_shared_memory.go` grows that ceiling to
`MemTotal`, preserves larger custom ceilings and mount flags, and verifies the
result. This changes a ceiling; it does not preallocate memory.

Bootstrap installs `tuist-kata-shared-memory.service`, ordered before containerd,
and the Ready-path repair installs and runs the same service on existing OVH
Kata hosts without restarting containerd, kubelet, or guests. Only a successful
repair stamps `tuist.dev/kata-shared-memory-config` on the Node with the script
and unit hash plus `status.nodeInfo.bootID`. A changed configuration or boot
invalidates that proof; it is not continuous detection of manual mount changes
within the same boot. Missing proof sets `KataSharedMemoryUnverified`; a failed
repair sets `KataRuntimeRepairFailed`, leaving the machine Ready and the existing
runtime label intact. Non-Kata fleets are unaffected. The Hetzner worker template
in `infra/k8s/clusters/bare-metal.yaml` installs identical files for new workers
(checked by a test); existing Hetzner workers do not use this OVH repair path.

Alerts for this operator are Grafana-managed rules, created in Grafana Cloud
rather than checked in: managed clusters run no Prometheus Operator, so there is
no `PrometheusRule` to render. Add a new one alongside the existing `capt_*`
rules in the `Runners` group and put the reasoning in the rule's own
`description` annotation, which is where its siblings keep theirs.

## Node extended resources

The Linux machine controllers patch two integer extended resources onto the
Nodes they own (`controllers/shared/node_egress.go`, `node_memory.go`), both
re-applied every reconcile so a kubelet re-registration that resets status
cannot strand them. Each exists because the scheduler's native bin-pack cannot
see the quantity in question:

- `tuist.dev/egress-mbps` — the box's public egress budget, which Kubernetes has
  no concept of. On OVH it is derived from what the box reports, seeded by the
  machine's `EgressBudgetMbps` (see below); Vultr takes the spec value directly;
  Dedibox does too but leaves the node alone when it is zero. The helper itself
  treats a zero as "withdraw the capacity", so the OVH and Vultr kinds can retire
  a budget and Dedibox cannot.

  Elastic Metal has no `EgressBudgetMbps` and is deliberately outside this path.
  It backs only the private runner-cache pool, whose tenants reach it over the
  Scaleway Private Network (10 Gbit/s on the B-series, 25 Gbit/s on the I-series)
  rather than over the 1 Gbit/s public bandwidth every offer includes. That
  public figure is the one the other kinds advertise, and on this pool it
  describes no path in use: it is the mirror of the vRack over-commit the OVH
  fleet values warn about. Arbitration on the private path is the per-tenant
  Cilium ceiling instead, so the pool also stays out of
  `egressTreeAgent.nodePools`.
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
MachineDeployment clones carries the same number — wrong the moment a region
holds mixed hardware (a box on a purchased uplink upgrade, a slower one added
later). Over-stating a box fails silently: the scheduler bin-packs floors the
wire cannot deliver and the egress-tree agent rates its HTB root to match.

The OVH reconciler therefore reads each box's public egress limitation
(`bandwidth.OvhToInternet` on `/dedicated/server/{serviceName}/specifications/network`,
`internal/ovh/client.go`) and lets it raise the node's budget. The policy is
`shared.DecideEgress` (`controllers/shared/egress_policy.go`), a pure function of
the configured budget, what the node was last set to, OVH's last usable reading
and the two annotations below; `controllers/linux/ovh_egress.go` feeds it and
patches the node. Everything the decision depends on lives in `status.egress`, so
a failed node patch or an operator restart simply retries from status.

Rules, in priority order:

1. **`spec.egressBudgetMbps` ≤ 0 — ungoverned.** The capacity key is removed from
   the node, `status.egress` is cleared and the pin is ignored. Give the machine a
   budget to bring it into egress governance.
2. **`tuist.dev/egress-mbps-override: "<mbps>"` — pinned.** The node advertises the
   pinned value in either direction, whatever OVH says and even with discovery
   disabled. The pin is temporary: remove it once spec and/or OVH's reading are
   known to be right, and the node re-derives from those (rules 3–4), never from
   the pinned number. `status.egress.source` is `manual` while pinned. A value
   that is not a positive integer is ignored.
3. **The configured budget seeds and raises.** A machine's budget starts at
   `spec.egressBudgetMbps`; raising it on a live CR raises the node. Lowering it
   alone changes nothing — nothing lowers on the controller's own authority — and
   takes effect only when the budget is next re-derived, i.e. after a pin.
4. **A reading above the budget raises it; a reading below is recorded, not
   applied.** OVH's contractual bandwidth shrinks only because someone downgraded
   the plan, whereas a wrong-low reading (a blip, a partial response, a
   throttled box) is plausible and expensive. `status.egress.reportedMbps` and
   `capt_egress_reported_mbps` carry the standing disagreement.
5. **`tuist.dev/disable-egress-discovery` (presence only) — frozen.** No reads,
   no raises; the node keeps the budget it has. Discovery resumes, with an
   immediate read, when the annotation is removed. CAPI's SSA propagation owns
   only annotation keys the MachineSet template sets, so a hand-set key survives;
   putting it in a MachineDeployment template makes it fleet-wide.

**Accepting a reduction** is pin (the node drops now), lower `spec.egressBudgetMbps`
on the machine and in the fleet values (durable, and right for the next clone),
unpin (the node lands on the reading). Unpinning before lowering the budget lands
on the configured value — the floor — which is where rule 3 puts it.

**Check what is already allocated before pinning downward.** `tuist.dev/egress-mbps`
is an integer extended resource requested with `request == limit`, so it is not
overcommittable — but lowering a node's capacity below the sum of what its pods
hold is not refused and evicts nothing. The node sits over-allocated until the
next admission decision (a kubelet restart, a pod restart, a reschedule), and then
those pods fail admission with `OutOfExtendedResource`.

```
kubectl describe node <name> | grep -A12 'Allocated resources'
```

If the number you are about to pin sits below that total, move the excess cache
pods first. The same applies to removing the budget (rule 1).

**Reading the state.** `kubectl get odm` shows `EGRESS` (what the node was set
to), `EGRESSSOURCE` (`configured` / `discovery` / `manual`) and, with `-o wide`,
`EGRESSREPORTED`. The `EgressDiscovered` condition reports the last OVH read:
`True` when a usable reading is cached; `False` with `ReadFailed` (message carries
the consecutive-failure count and the last error), `Unresolved` (OVH answered but
with no bandwidth block or a unit we do not convert — the raw unit/value is in the
message) or `Disabled`. A box whose reads keep failing or keep coming back wrong
is what the disable annotation is for.

Reads are bounded by `status.egress.attemptedAt`: one a day after any answer,
one every 10 minutes while calls fail. Neither a failed call nor an unusable
answer overwrites the last usable reading. The reading records the box it came
from, so a machine re-adopted onto a different service is read again rather than
rated from its predecessor's number, and its budget restarts from the configured
value. Events (`EgressBudgetIncreased` / `EgressBudgetReduced` /
`EgressBudgetRemoved`) fire when the node's advertised budget actually moves,
naming both numbers and what decided the new one.

Three gauges, labelled `provider`, `node` and `fleet` (`node` is what joins them
against `kube_node_status_capacity{resource="tuist_dev_egress_mbps"}`):
`capt_egress_reported_mbps` (what the provider says, plus `service` and `tier`),
`capt_egress_configured_mbps` (the spec value) and `capt_egress_advertised_mbps`
(what was patched onto the node, plus `source`). All three are republished from
status on every reconcile, so an operator restart costs at most one reconcile of
gap rather than a day. `reported < advertised` is the standing disagreement
worth a dashboard.

Three things about OVH's response are load-bearing (`internal/ovh/client.go`):
`connection` and `vrack.bandwidth` sit next to the field we read and report the
switch link (25 Gbit/s on every box we run), so keying off either over-commits
the public path; the value is a `{unit, value}` pair whose unit is a free-form
string, so the bare number would advertise 5 Mbps for a box reported as
"5 Gbps"; and every field is nullable, so an absent bandwidth block is an
ordinary answer that resolves to zero.

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
   never order). OVH ADVANCE-1 for the US cache regions, ADVANCE-2 for
   ap-southeast, RISE-L (production) or RISE-S (staging, canary) in Gravelines
   for the Linux runner pool, Dedibox for eu-west. The RISE range's
   EU-datacenter plan codes (`25risel01-v1-eu`, `25rises01-v1-eu`) are orderable
   on OVHcloud US, so a Gravelines box stays on the one `ovh-us` endpoint every
   OVH fleet shares. Stock per plan and datacenter is public and needs no token:
   `GET https://api.us.ovhcloud.com/1.0/dedicated/server/datacenter/availabilities`.
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

   **Vultr is a conversion, not an install.** Its API exposes no partitioning
   control and its installer offers only RAID 1 across both disks (one
   filesystem spanning the pair) or no RAID, so neither option yields the
   mirrored root plus separate XFS `/data` the OVH and Dedibox installs lay
   down. Order the box as RAID 1 with the fleet key attached, then convert it in
   place, which splits the mirror and hands the freed disk to `/data`:
   ```bash
   PREP_NAMESPACE=tuist-production mise run baremetal:prep-vultr 64.176.17.88
   ```
   The root keeps running on the remaining leg, so there is no reinstall, no
   reboot and no bootloader change; the cost is that the root is no longer
   mirrored. `/data` is what the cluster gates on rather than the mirror:
   `tuist.kuraVolumeQuotaProgram` leaves every cache volume unbounded without an
   XFS `/data` carrying project quotas, and the self-join refuses a box that
   cannot enforce. It lands on the disk that does not hold the ESP, so losing
   the data disk leaves a box that still boots. The task waits on any in-flight
   array rebuild, is a no-op on an already-converted box, and prints the four
   gates at the end.
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
Production today: tag `tuist-kura-production` (eu-west), displayName prefixes
`tuist-kura-ovh-production-us-east` / `-us-west` / `-ap-southeast` and
`tuist-runners-ovh-production` (OVH).

Not every `ovhFleets` entry is a cache region. `machine.nodeTaints` is what says
which it is: unset renders `tuist.dev/kura-cache=true:NoSchedule` and puts the
pool in the cache-only surfaces keyed off that map (the volume quota exporter's
node affinity in `infra/helm/tuist/templates/kura-fleet-storage.yaml`), while a
fleet that sets its own taints stays out of them. The Linux runner fleets set
`tuist.dev/runner-tier=bare-metal` plus a `tuist.dev/fleet-bringup` holdout
nothing tolerates, so their boxes join and stay empty until that second taint is
dropped.

Release (`reconcileDelete`) drops the Node + identity + TOFU pin and **reinstalls
the box back into the pool**. It stays a monthly contract (release is not a contract
termination), but the reinstall wipes the OS to a clean, claimable state — any
node-local volume is lost and the host key rotates, so the next claim re-TOFUs it.

**A reinstall already in flight is a completed release, not a failure.** All three
kinds reach the provider before dropping the finalizer, so a controller restart
between a successful install call and the finalizer patch — or two Machines on one
box — has the release ask for a second wipe of a box already being wiped. Every
provider rejects that for the whole ~30 minute install, and retrying on it holds
the Machine in `Deleting`: the MachineDeployment stays a replica above spec and a
`helm upgrade --atomic` rollback waiting on that count runs out its step ceiling
(2026-09-03, 13 minutes on `ns3048220`). Each kind therefore reads the box's own
install state and releases when a wipe is already running — OVH gates on
`Client::BadRequest::TaskAlreadyExists` plus an install-function task in the task
list, Dedibox and Elastic Metal on the install status the API reports, since
neither names the collision. A failure that is not that retries on a bounded
interval rather than controller-runtime's default backoff, which doubles to a
1000s cap and idles the Machine long after the provider frees the box.

### Disk layout, and why it is an install-time decision

Every install these kinds start lays down a redundant root plus a **separate XFS
`/data`**, and the self-join then mounts `/data` with `prjquota` and refuses to
join a box where it cannot (`dataProjectQuotaScript` in
`controllers/linux/linux_cloudinit.go`).

On a **cache box** the image store gets a reserved project of its own
(`containerdQuotaScript`, project 100). It is the only consumer of `/data` that
is not a tenant, and a per-volume quota is a ceiling rather than a reservation,
so a tenant inside its own ceiling can still be denied space something else took
first. Nothing else bounds it: the kubelet's image GC triggers on the FILESYSTEM
being nearly full, so it only reclaims once the box is already squeezing
tenants. The ceiling is deliberately generous, because containerd hitting it
means failed pulls that image GC cannot resolve, and unlike the `/data` mount
setup a failure to apply it does not fail the join.

**Only cache boxes get it** (`hostsKuraCacheVolumes`, keyed off the
`tuist.dev/kura-cache` taint). A runner box has no tenant volumes on `/data`, so
the quota protects nothing there while still being reachable: under `kata-qemu`
the runner container's writable layer is a host overlayfs snapshot inside the
image store, so ordinary CI writes land against project 100. XFS reports a blown
project quota as ENOSPC, and image GC keys on the filesystem's free space, which
on an 828 GiB `/data` never trips. A runner box that hit the ceiling therefore
failed every job it accepted, permanently, on a disk that was 94% free. Absence
of the taint means no quota: quota-ing a box with no tenants buys nothing and
costs an unclearable ceiling, while skipping one that has tenants only returns
it to the defence-in-depth it had before the quota existed.

Gating the self-join alone reaches no live box (see "strategy: OnDelete"
above), so `reconcileLinuxContainerdQuotaDrift` (`containerd_quota_drift.go`)
lifts the limit in place from any Ready non-cache box and stamps
`tuist.dev/containerd-quota-lifted` on the Node. The quota is XFS metadata with
no Kubernetes-visible observable, so like the kubelet-config hash the stamp IS
the observable, written only on the lift script's exit status. The lift is one
`xfs_quota limit -p bhard=0` plus dropping the `/etc/projects` line: no restart
of anything, effective in the kernel immediately, so a box mid-ENOSPC recovers
without a drain. `ContainerdQuotaLifted=False/ContainerdQuotaPresent` on the
Machine is the loud state before the lift, `ContainerdQuotaLiftFailed` after a
failed one.

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

### A Linux runner box is Ready but takes no jobs

The box joins Ready, lands in the right pool with the right taint, runs every
DaemonSet — and no runner Pod ever schedules on it. That is the once-at-bootstrap
trap above, almost always because the Machine was bootstrapped by a provider
build that predates the capability its spec asked for. Confirm in one read:

```bash
kubectl get ovhdedicatedmachine <name> -o jsonpath='{.status.conditions[?(@.type=="KataRuntimeReady")]}{"\n"}'
kubectl get node <name> -o jsonpath='{.metadata.labels.katacontainers\.io/kata-runtime}{"\n"}'
```

`KataRuntimeReady=False/KataRuntimeMissing` means the provider has seen it and is
repairing in place; it converges within a reconcile or two and needs no operator
action. `KataRuntimeRepairFailed` carries the reason — an unreachable box, or one
whose containerd cannot register the handler (its config predates `version = 3`,
which the self-join refuses to join around). Do NOT `kubectl delete machine` to
force a re-bootstrap: it wipes the box, and for a cache node it destroys the
local state. Fix what the condition names and let the repair land.

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
