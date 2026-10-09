# Dedicated runner egress (design)

Status: draft for review. Nothing here is built yet.

## Goal

An account can be given a dedicated egress address. That account's runner jobs
reach the internet from that address, and no other tenant's traffic ever
does. If the dedicated path is down, the job has no internet. It never falls
back to the shared host IP. The setting is internal and managed by ops. It is
not self-serve.

Scope: macOS (Tart) runners.

## What gets routed

Everything the guest sends is routed, except our own private paths. Those are
the runner-cache carve-outs (Kura Service ClusterIPs and cluster DNS over the
tailnet, the Private Network NodePorts and the rack cache gateways), plus
private and special-use ranges. Private ranges stay blocked by `tuist.runners`
exactly as today.

A "dedicated runner IP" ends up on more than GitHub's allow list: artifact
stores, internal APIs, package mirrors. With a partial route set, those
requests would quietly leave from the shared host IP and be rejected, and the
customer would see that as our bug. Routing everything also keeps fail closed
simple: if the gateway is down, the job has no internet.

A narrower route set, such as only GitHub's `/meta` ranges, would be one more
pf table and is left out until a customer asks for it.

These stay on the host's own path:

- DNS, because the guest resolves through the host.
- The guest's connections opened before dispatch, because pf keeps existing
  states on their original route. Those connections belong to our dispatch
  code. Customer code only starts after the JIT config arrives, so every
  connection it opens is new and is routed.

## Data path

```
Tart VM 192.168.64.x
  │  bridge100
  ▼
Mac host pf, anchor com.apple/0.tuist.egress (owned by tart-kubelet)
  table <egress_exclude> const { private, special-use, runner-cache carve-outs }
  scrub on utunG all max-mss 1380
  nat on utunG inet from ! <host tailnet IP> to any -> <host tailnet IP>
  pass in quick route-to (utunG 198.18.<i>.1)
       inet from <egress_G> to ! <egress_exclude> flags any keep state
  block drop in quick inet from <egress_all> to ! <egress_exclude>   # backstop
  │  utunG = utun<100+i>, WireGuard to gateway G (index i), one per gateway,
  │  kept up permanently by a root launchd daemon
  ▼
WireGuard over the public internet to FIP_G:port_G
  (the endpoint is the dedicated address itself; Hetzner routes it to the
   active md-egress node, and it moves with the address on failover)
  ▼
runner-egress-gateway pod G, a DaemonSet on md-egress candidates
  Service externalIP FIP_G:port_G -> pod netns (kernel WireGuard, NET_ADMIN)
  peers  = darwin Nodes: tuist.dev/runner-egress-public-key annotation +
           Node InternalIP/32 (the host's tailnet IP: unique, no allocator)
  forwards wg0 -> eth0 to public destinations only (drops private and
  cluster ranges, so it is never a relay into the cluster)
  MASQUERADE to the pod IP
  ▼
CiliumEgressGatewayPolicy G: selects gateway pods G, egressIP = FIP_G,
  gateway node = the active md-egress node (the same node, so SNAT is local)
  ▼
internet, source FIP_G
```

One anchor holds every gateway's rules and the backstop, in a fixed order.
Its name sorts ahead of every other `com.apple/*` sub-anchor. That matters
because `com.apple/tuist.sshguard` has a quick `pass` for VM SSH traffic. If
that pass were evaluated first, a routed VM's `git` over SSH would leave from
the host's own address.

Why this shape:

- The tunnel ends at the dedicated address itself. Nothing needs to track
  where the gateway runs. Hosts always dial `FIP_G`, so when the address
  fails over the endpoint moves with it. The tailnet, the subnet router and
  any DERP fallback stay out of the data path, which matters now that all of
  a job's traffic goes through it.
- Per-account SNAT reuses what Cilium already does for server egress. A
  dedicated address costs one Floating IP, one DaemonSet and one policy. It
  needs no new node pool.
- The host is trusted and the guest is not. The host routes with pf
  `route-to` and holds the WireGuard key. The guest never sees a credential
  or a tunnel and can't pick its egress.
- Tunnels are per gateway and per host, not per job. They stay up and are
  monitored by handshake age per host and gateway. The only per-job work is
  updating a pf table.
- WireGuard on a public port accepts only fleet Node keys. MTU is 1420, so a
  single encapsulation over a 1500 path needs no double tunnel.

## Components

| Where | Change |
|---|---|
| `tuist` chart + CAPI provider | `macosFleet.runnerEgressGateways` (`name`, `index`, `endpoint`, `publicKey`) becomes `--runner-egress-gateways` on the operator, then `Config.RunnerEgressGateways` for every host. It is fleet-wide and folded into the host config hash, so adding or removing a gateway re-pushes the hosts. |
| `macos-host-bootstrap` | Installs one root LaunchDaemon per gateway, `dev.tuist.runner-egress.<G>`, running `tart-kubelet egress-tunnel` (see below). It retires daemons for removed gateways and kickstarts them when the tart-kubelet binary changes. With no gateways left, it flushes the egress anchor. It passes `--runner-egress-*` to tart-kubelet, but only when the node IP is the tailnet address. |
| `tart-kubelet` | The `egress-tunnel` subcommand. In the kubelet itself, `internal/egress` is the only writer of the egress anchor. It publishes the Node annotations `tuist.dev/runner-egress-public-key` and `tuist.dev/runner-egress-ready-gateways`, keeps the tables in step with live Pods using `pfctl -T replace` (never a flush), sets the Pod condition `tuist.dev/RunnerEgressReady`, and exports tunnel health. |
| new `infra/runner-egress-gateway/` | A Go gateway with a read-only Node watch, wgctrl peer sync, nftables forward and SNAT rules, and `/healthz` on the tunnel address. It has two SNAT modes. `masquerade` is phase 1, where Cilium owns the address. `address:<ip>` is phase 2, a direct SNAT to a routed address. |
| platform chart | `runnerEgressGateways.<G>` (`index`, `egressIP`, `floatingIpName`, `port`, `publicKey`, `privateKeySecret`) renders a DaemonSet on the egress candidates (the WireGuard key comes from ESO) and a CiliumEgressGatewayPolicy. The host-configurer and stable-egress-controller learn to carry several Floating IPs, not only the server's. The allowlist guard stays on the server FIP. The project has no Hetzner Cloud Firewall, so the UDP port needs no extra allowance. |
| server | Adds `accounts.runner_egress_gateway`, a nullable gateway name that ops set with no UI. Adds the dispatch gate (below). |
| docs | `guides/server/network.md`: correct the claim that all traffic leaves from the two server IPs, and add a Runners section. |

## Running WireGuard

### Mac host: userspace, one root daemon per gateway

`tart-kubelet egress-tunnel` embeds wireguard-go (`golang.zx2c4.com/wireguard`)
and runs as a root LaunchDaemon with `KeepAlive`. It is not part of the kubelet
process, for three reasons:

- **It needs root.** Creating a utun needs root. tart-kubelet runs as the
  console user because Virtualization.framework requires it.
- **The tunnel must outlive the kubelet.** It has to survive kubelet restarts
  and crashes.
- **The kubelet stays outside the data path.** A stuck kubelet can't stall
  packets.

It ships inside the existing tart-kubelet binary, so it uses the
`TartKubeletBinary` delivery and update path with no new artifact. When the
binary changes, the host config push kickstarts the egress daemons.

On start, the daemon for gateway G:

1. **Loads or creates the host key.** The private key is
   `/var/db/tuist-egress/private.key` (root, 0600) and is created on first run.
   The public key is written next to it (0644) for tart-kubelet to publish.
   One key per host is shared by every gateway. The private key never leaves
   the host.
2. **Creates the utun under a fixed name.** It asks for `utun<100+index>`, so
   the name survives restarts and the pf rules never point at a stale device.
   The interface is point-to-point `198.18.<i>.2 -> 198.18.<i>.1`, MTU 1420.
   Each gateway gets its own pair, so several tunnels on one host never
   install conflicting host routes. It installs no routes beyond that: only
   pf `route-to` sends traffic into it.
3. **Configures one peer through UAPI.** The peer is the gateway's public key
   with endpoint `FIP_G:port_G`, `allowed_ip=0.0.0.0/0` (an inbound filter
   only, since there are no routes) and `persistent_keepalive_interval=25`.
4. **Probes every 5s.** It records the time of the last handshake and an HTTP
   `GET 198.18.<i>.1:8080/healthz` through the tunnel. The anchor's NAT turns
   the probe's source into the host's tailnet IP, which is the only address
   the gateway accepts from this host. The result goes to
   `/var/run/tuist-egress/<G>.json` (0644): ok, handshake time, rx and tx
   bytes. tart-kubelet reads it without sudo and arms a VM only when it is
   fresh and ok.

The daemon never touches pf. tart-kubelet renders the anchor from the status
files and the node's tailnet IP. It reloads the anchor when the rendered
rules change or a check finds it missing, and then re-applies the tables.
Tables of VM addresses are referenced but never defined in the anchor, so a
reload leaves them alone.

If the daemon dies, the pf rules stay loaded. `route-to` then names a missing
interface, and the backstop catches anything that falls through. Packets are
dropped, never routed out of en0. The daemon restarts on the same utun name
and the tunnel recovers on the next handshake, which takes about one RTT.
In-flight TCP mostly survives a short restart because the gateway's
conntrack state is unaffected.

### Gateway: kernel WireGuard in the pod netns

The `runner-egress-gateway` agent runs in an ordinary (not hostNetwork) pod
with `NET_ADMIN`. Hetzner's Ubuntu kernels ship the `wireguard` module. The
agent:

1. **Creates `wg0` through netlink (wgctrl).** The private key comes from a
   Secret (1Password via ESO). It listens on `port_G` and has address
   `198.18.<i>.1/32`. It routes `100.64.0.0/10 dev wg0`; the pod netns has no
   tailnet, so the tailnet range doesn't collide.
2. **Syncs peers from a read-only watch of darwin Nodes.** Each peer is the
   Node's public key annotation with `AllowedIPs = <Node InternalIP>/32`. A
   Node that is deleted or loses its key is removed.
3. **Applies nftables.** Forward from `wg0` to `eth0` is accepted only to
   public destinations; private, special-use and cluster ranges are dropped.
   Traffic out of `eth0` is masqueraded. Input on `wg0` allows only TCP 8080
   (`/healthz`).
4. **Reports Ready** once `wg0` is up and peers are synced. The DaemonSet runs
   on every egress candidate, so a standby already holds the same key when
   the Floating IP moves.

A Service with the Floating IP as an external IP (`externalTrafficPolicy:
Local`) delivers `port_G/UDP` to the gateway pod on the active node. A
`hostPort` doesn't work: Cilium matches hostPort only against node addresses
it knew at startup, so it never sees a Floating IP the host-configurer adds
later. Staging showed exactly that, with handshakes arriving on `eth0` and
never reaching the pod. The external IP is matched by destination.

Cilium resolves a policy's egress IP to an interface when it sees the policy
or a node change, not when an address appears. A gateway added in the same
deploy as its Floating IP therefore starts with an unresolved policy that
drops the gateway's traffic (seen on staging). stable-egress-controller
stamps `tuist.dev/stable-egress-ips`, a digest of the active node's egress
addresses, once the host-configurer reports the node prepared. The label
change makes Cilium re-resolve.

Phase 2 at BER1 runs the same agent in `address:<ip>` mode on the edge box,
SNATing straight to the /24 address.

## Per-job install and teardown

1. **Before the claim.** If the account has a gateway and the polling Pod's
   Node doesn't list G in `tuist.dev/runner-egress-ready-gateways`, the
   account is skipped like `:account_busy`. Another host may serve it; if no
   host has a healthy tunnel, dispatch is held and the jobs stay queued.
   Linux fleets skip these accounts entirely until Linux support exists.
2. **The claim is won.** The server stamps `tuist.dev/runner-egress-gateway=G`
   in the same patch as the owner label, before the JIT mint.
3. **On the host.** tart-kubelet sees the label and checks that G's status
   file is fresh and ok and that the anchor is loaded. It adds the VM's IP to
   `egress_all` first, so the backstop holds from that point on. It then
   adds the IP to `egress_G` and sets `RunnerEgressReady=True` with the
   message `armed <ip>`. That condition is the durable record of what is
   routed: a restarted kubelet reads it back, and it is never withdrawn while
   the VM runs. An armed VM stays routed even if its tunnel later goes
   unhealthy, so its traffic is dropped rather than leaving from the host.
4. **Back on the server.** The server mints the JIT in parallel, then waits
   up to about 5s for the condition. The guest's dispatch curl has a 10s
   `--max-time`. Only then does it return the JIT. On timeout it releases the
   claim and the job is re-queued.
5. **A Pod with the egress label counts as committed.** If it polls again it
   gets 410 and is recycled. A VM that was armed for account A never runs
   account B's job.
6. **Teardown.** tart-kubelet stops the VM first, so a guest still running
   through a graceful stop keeps its route and backstop. It then drops the
   VM's IP from the gateway table and the backstop, kills the address's pf
   states (pf matches a state before any rule, so a recycled address could
   otherwise inherit a routed flow), and only then deletes the VM. A VM whose
   `tart run` has exited is dropped on the next sync, and a sync runs every 5s
   and after a restart. Syncs are serialized end to end, Pod snapshot
   included, so an older snapshot can never undo a newer arm.

The JIT config is the only credential that lets the job run. The guest gets it
only after the host has enforced the route, so the account's job never runs
on the shared path.

## Failure modes

| Failure | Result |
|---|---|
| Gateway is down before dispatch | The account's jobs stay queued. Signals: `tuist_runners_dispatch_egress_held_count` (by account, gateway and reason), the per-host `tart_kubelet_runner_egress_tunnel_healthy` and handshake age, and the existing queue-age alerts. The held-dispatch alert rule is still to be added. |
| Tunnel is unhealthy on one host | No ack, so the claim is released and the job goes to another host. A per-host handshake-age alert fires. |
| Gateway or tunnel failure mid-job | `route-to` still forces packets into utunG, where they are dropped. In-flight connections fail. Nothing leaves from the host IP. |
| Host tunnel daemon dies or restarts | The pf rules stay loaded. Packets go to the missing utun or hit the `tuist.runners` backstop. They are dropped and never routed out of en0. The daemon comes back on the same utun name. This needs checking on staging: does a `route-to` that names a missing interface drop the packet? |
| `md-egress` node failover | stable-egress-controller moves every managed FIP together. The hosts' WireGuard re-handshakes with the standby pod, which has the same key and is already running. In-flight flows reset, the same as server egress today. |
| IPv6 | vmnet gives every guest a ULA address and NAT66es it to the host's own IPv6, and pf can't tie a ULA address to a VM. So every runner VM is IPv4-only: `tuist.runners` carries `block return in quick inet6 from fc00::/7 to 2000::/3`, matched before NAT66 rewrites the source, and clients fall back to IPv4 at once. GitHub-hosted macOS runners are IPv4-only too. |

## Phase 2: Tuist's own /24

Add gateway `G2` at the BER1 edges in `address:<ip-from-/24>` mode. It is plain
nftables SNAT on the box that announces the /24, not Cilium. Its endpoint is
that address. Other fleets reach it over the internet with the same WireGuard
tunnel.

Hosts get a second tunnel from the fleet values. The customer allowlists both
addresses. Ops flips `accounts.runner_egress_gateway` from `G` to `G2`, so new
dispatches use G2 while in-flight jobs finish on G. Then ops removes G and
releases the FIP.

Only the endpoint address and the gateway's location change. The Pod label and
condition, the pf tables, host keys, the tunnel protocol and the dispatch gate
stay the same.

## Linux (kata on OVH), not built

Linux runner Pods are ordinary cluster Pods. A per-gateway
`CiliumEgressGatewayPolicy` can select runner Pods by
`tuist.dev/runner-egress-gateway=G` (egressIP = FIP_G) without a tunnel. What's
missing is an ack, because Cilium doesn't report when a policy is applied to
a Pod. That needs a node-agent probe, or a settle delay that is weaker. Until
then, Linux dispatch skips dedicated-egress accounts.

## Cost and capacity

- Hetzner Floating IP: about €3/month per account.
- Gateway pods: 2 × (100m CPU, 64 MiB) per gateway on the existing egress
  nodes.
- Traffic: everything a job downloads is relayed from the gateway to the Mac
  host, so it counts as Hetzner egress. That's 20 TB/month included per node
  and about €1/TB beyond. At 3 GB per job and 1,000 jobs a day, that is
  roughly €70/month in overage.
- Latency: jobs at fr-par pay about 10-15 ms of extra RTT on every connection.
  BER1 is closer.
- Capacity: server egress and every dedicated gateway share the active egress
  node's NIC. Size the pool from tunnel byte metrics before onboarding a
  second account.

## Staging validation plan

1. Reserve a staging Floating IP and deploy one gateway.
2. Point a staging Tuist account at it and dispatch to staging macOS hosts.
3. Positive check: from the job, an IP-echo endpoint and `git ls-remote`
   succeed, and the echo shows `FIP_G`.
4. Negative checks: another account's job on the same host still shows the
   host IP. Stop the gateway: the dedicated job has no internet, and `tcpdump`
   on en0 shows no packets from the VM to the internet. Kill the tunnel daemon
   mid-job: same result. A recycled VM IP isn't left in a table.
5. Confirm on a real staging host:
   - pf `route-to` plus NAT through the utun
   - the missing-interface behaviour
   - throughput through the tunnel (a clone of a large repo, and a Homebrew
     bottle install)
