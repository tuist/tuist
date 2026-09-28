# Provider-private Kura replication

This is the private-network slice of [Atlas spec 98](https://atlas.tuist.dev/engineering/specs/98).
Spec 95 is already shipped. Ingress, BGP, physical-host placement and host
migrations are outside this change. **No production network or workload has
been changed by this work. Private routing is disabled until the gates below
are satisfied.**

## Operational inventory

Re-query host IDs, addresses, attachment state and permissions from the provider
and cluster before each cutover. Keep operational inventory in private records;
this guide defines routing semantics and qualification gates. A private PodIP
does not prove a private physical underlay. Account-scoped peer mTLS remains
required on every path.

## Supported topology and unresolved provider gates

- OVH: qualify one common vRack/VLAN for each supported routing domain. Ask the
  account API/provider to establish whether the US-entity account can attach the
  exact GRA/WAW/VIN/HIL/SGP services to one private fabric. Global marketing
  coverage is not evidence of reachability between those entities/locations.
  Start with GRA–GRA, VIN–VIN and HIL–HIL, then test every proposed cross-location
  edge. Keep unverified edges unsupported. Do not change OLA mode: `private(4)`
  would remove the public interfaces and is not required here.
- Vultr: use its current bare-metal VPC product in ORD, and separately in SCL.
  [VPCs are location-scoped](https://docs.vultr.com/how-to-peer-vpcs-between-vultr-locations-with-wireguard).
  ORD–SCL has **no established provider-private path**. A WireGuard tunnel over
  public addresses encrypts traffic but does not satisfy the private-underlay
  requirement. Do not label both locations as one domain or enable a silent WAN
  exception. Resolve that policy/topology gap before enabling strict routing
  across a mesh containing both locations.
- Cross-provider: retain the existing reachable peer gateway and account mTLS.
  Provider preference never removes the remote origin-region links, published
  gateways, or same-region sibling feeds.
- Legacy/self-hosted peers with no topology remain reachable over their existing
  authenticated HTTPS endpoint. They receive no provider preference. This is
  version compatibility, not proof of a private route. Upgrade and inventory all
  managed members before claiming all same-provider transfers are private.

## Reviewable provisioning sequence

1. Obtain a scoped OVH vRack **read** grant first: list `/vrack`, inspect each
   candidate, its allowed services, and its existing dedicated-server/interface
   membership. Retain the current per-server read grant. Confirm the actual
   attachment API for each server's private NIC/OLA shape and record the private
   MACs. If a vRack must be ordered, obtain its exact quote and approval before
   checkout; no service charges are assumed approved.
2. Confirm the current Vultr bare-metal VPC endpoint and ORD/SCL eligibility
   through the account or support. Obtain the current network price, bandwidth
   limits and restart requirements. Plan a single ORD network containing the
   eligible hosts and a separate SCL network. No NAT gateway, VPN gateway or extra
   machine is needed for the local private paths; none is authorized here.
3. Allocate nonoverlapping CIDRs from the live host, Pod, Service, tailnet and
   runner network inventories. Record network IDs, VLAN IDs, interface MACs,
   private host addresses, effective MTU and enabled private service capacity.
   These cannot be filled safely from an unattached NIC's speed. Do not invent
   network IDs or advertise topology before allocation and verification.
4. Attach networks without replacing public NICs, default routes, DNS or OLA
   mode. Keep out-of-band console access and a saved host network configuration.
   Treat a required restart as disruptive: retain a serving, caught-up sibling
   on another physical host. A location with one physical host needs an explicitly
   accepted maintenance window or separately approved capacity. Two colocated
   process replicas do not solve host downtime.
5. Configure persistent private host addresses and explicit bidirectional routes.
   The node underlay must be reachable by the cluster's other providers and the
   API server too. Do **not** simply replace all kubelet InternalIPs with isolated
   VPC addresses. A reviewed per-peer route/encapsulation design may keep the
   current Kubernetes identities while carrying same-domain VXLAN on private
   NICs. Prove the outer VXLAN path, reverse routing, policy and MTU. Install a
   persistent prohibit/blackhole guard for private-only destinations so loss of
   an interface cannot select the public default route. This design/configuration
   remains a rollout gate; no cluster-wide Cilium change is bundled here.
6. Preserve peer mTLS, certificate SAN checks and per-account network policies.
   Keep cross-provider public peer endpoints reachable. Validate a wrong-CA
   client and missing client certificate are rejected on both entrances.

Production host configuration, captures and pod exec need the human-controlled
JIT access described in [infra/AGENTS.md](../AGENTS.md#cluster-access-for-agents).
Do not fetch admin kubeconfigs, invoke `/elevate`, or bypass that boundary with
host credentials. Request a scoped window only once the concrete provider
attachments, IP plan and one-host-at-a-time change are ready for review.

## Runtime configuration

`KURA_PEER_TOPOLOGY` is optional JSON:

```json
{"provider":"ovh","private_network":"verified-vrack-id/vlan-id","private_url":"https://pod.headless.namespace.svc.cluster.local:7443"}
```

Use provider identity from the real Node providerID. `private_network` is a
verified routing domain, not a provider or region alias. `private_url` must reach
this process, with its existing account mTLS and a matching certificate SAN.
The deployment attests the underlay; the runtime cannot inspect provider NICs.
Do not put a shared primary Service in every sibling's `private_url`, which
would send sibling feeds to the same process. Global discovery advertises the
responding gateway process's private URL and refreshes it at membership cadence.
Small status discovery calls still use the canonical gateway to observe changes
of primary. Bulk replication uses the private URL. Public gateway discovery
availability remains a dependency, as before this change.

The standalone chart exposes `peerTopology` and rejects it without peer TLS.
For managed instances use `spec.extraEnv` with the same JSON and Kubernetes
`$(POD_NAME)`/`$(POD_NAMESPACE)` expansion. Enable only on a homogeneous,
verified node selector: a pool name is insufficient during a provider migration.
The controller/server do not yet derive these fields from live node networking;
automatic publication is pending the provider/underlay model. Production chart
values intentionally do not enable the feature.

Provider-only configuration is rejected at startup: opting in requires both
`private_network` and `private_url`. Same-provider peers advertising absent or
different private domains fail visibly in
replication errors and private-probe logs. Failed private requests never retry
publicly. Listings, forward reads, batches and individual bodies all use the same
selector; canonical peer identities and watermarks remain unchanged. Disabling
redirects and environment proxies in topology mode prevents a selected private
request from being diverted to a public origin. Certificates still rotate through
the existing client factory.

Among equivalent healthy remote-region candidates, prefer the same provider
with a compatible private domain. The local gateway election stays deterministic
and published roles remain authoritative. Local private-probe health is separate
from the peer's advertised serving/draining state and affects only remote donor
ranking and preference. Canonical status requests retain the existing client
read timeout and discovery-observation semantics, including when topology is off.
Remote backward passes give healthy same-provider donors in remote regions a
bounded 200 ms head start to claim common bodies; local siblings never trigger
that delay. All
passes still run, forward replication is never delayed, and a preferred peer
cannot hold other providers behind an exclusive admission slot. Existing claim
release, retry and backfill failure budgets are retained.

## Verification, rollout and rollback

1. Deploy software with topology unset. Validate old/new runtime overlap and
   existing mTLS replication. Record the previous image and StatefulSet strategy.
2. On an isolated test account, configure a verified same-domain pair and a
   cross-provider third peer. Require writes made on **each** process to arrive
   at the others, including an individual oversized body, batched bodies,
   tombstones, a restarted replica and its backfill. Verify the selected primary
   changes do not change canonical watermarks or retain a departed private URL.
3. On both authorized hosts run `verify-private-path.sh PRIVATE_IF PUBLIC_IF
   PEER_UNDERLAY_IP PEER_PUBLIC_IP -- WORKLOAD ARG...`, reversing hosts for the second run.
   Supply a bounded workload that writes fresh data and waits for authenticated,
   checksum-verified replication. The script records routes, interface counters
   and short packet captures for both peer addresses, including overlays and
   HTTPS gateways, refusing a route on the public interface. It requires private
   packets in both directions and no matching public packets. Public discovery
   traffic to that host also fails this conservative check; use an isolated
   pair with private discovery for the underlay proof, and separately capture
   every public gateway address during the runtime failure test. Do not exclude
   unexplained public traffic as presumed control traffic. Keep both hosts'
   evidence. Also measure sustained private
   throughput, MTU without fragmentation and N-1 rebuild headroom; the script's
   packet check alone is not a throughput measurement.
4. Fail only the private test path. Same-provider replication must report a
   failed link with zero public data fallback. Cross-provider links must continue
   advancing; restore the private path and verify catch-up without manual cursor
   edits. Check missing/expired certificates and wrong-account peer rejection.
5. Run the same sustained harness on `main` and this revision, sequentially on
   the same host/configuration. Scrape runtime memory/pressure, CPU work, retained
   disk/write volume and client/peer egress throughout load and cooldown. Respect
   the doubled `_total_total` counter names. Publish four-axis results before
   production rollout; unit tests and loopback TLS are not this measurement.
6. Expand one verified domain/account at a time, preserving OnDelete holds and
   observing link failures, backfill completion and cross-region watermark age.
   Unknown or unsupported domains block expansion, not the rest of the fleet.

Rollback software/configuration first to the recorded runtime/template if the
test fails; leave the verified private fabric intact. Disabling topology restores
legacy routing and may use public bandwidth, so that is an explicit operational
rollback, not automatic failover. Restore host routes/addresses from the saved
configuration one host at a time only if necessary, with the public fallback
budget understood. Do not detach a network carrying live replication, delete a
Machine/PVC, reinstall a host, or retire an attached paid service as rollback.

### Initial local validation, 2026-09-28

The topology, sync and TLS/configuration suites passed (6, 40 and 4 tests).
The backfill and discovery/body suites passed another 53 and 3 tests (106
focused native tests total). A sandboxed backfill attempt could not bind local
listeners; it passed after rerunning with local networking permission.
The Docker ShellSpec mTLS suite passed both examples, including writes from
all three origin regions reaching every peer. The release Docker image built,
Clippy passed with warnings denied, and the standalone Helm chart rendered
with topology disabled and enabled; topology without peer TLS was rejected.
Bazel was attempted first but stopped in the lz4 dependency because the installed
Xcode 27 SDK exposed an undeclared absolute `SDKSettings.json` header. Cargo was
used for native checks after that toolchain failure.

The [resource harness](../../kura/test/e2e/provider-topology/README.md) ran
sequentially against merge base `5ae561d04bf2b3580d96b5ab675ab0c98dd47afa`
and the changed release image on the same Docker Linux host. Both completed
320 × 1 MiB writes, 768 verified load reads, and 192 seed verification reads,
with no read failures. Each replicated the entire corpus to both other nodes.
Load lasted 63.79 / 63.95 seconds, followed by 30 seconds of cooldown. Values
below aggregate three nodes; memory peaks sum simultaneous two-second samples.

| Measurement | Merge base | Change |
| --- | ---: | ---: |
| Process CPU seconds | 35.38 | 34.82 |
| CPU seconds / client GiB | 28.304 | 27.856 |
| Anonymous memory peak / cooldown, MiB | 594.35 / 376.03 | 495.18 / 331.85 |
| Allocator allocated peak / cooldown, MiB | 80.48 / 28.42 | 66.12 / 28.24 |
| Allocator resident peak / cooldown, MiB | 257.24 / 75.60 | 196.75 / 69.29 |
| Highest pressure tier / capacity sheds | normal / 0 | normal / 0 |
| Transient reservation peak, MiB | 5.50 | 10.00 |
| Data-volume bytes | 1,008,069,421 | 1,008,070,281 |
| Segment refresh bytes | 0 | 0 |
| Client egress / peer applied payload, MiB | 960 / 640 | 960 / 640 |
| Interface transmit bytes, MiB | 1,624.66 | 1,624.16 |

The higher instantaneous transient reservation remained below 1% of the aggregate
1,152 MiB reservation capacity, with no pressure or shedding. Disk differed by
860 bytes of metadata; payload retention and transfer counts were equal. This
single bounded run found no CPU, retained-memory, disk or egress regression; it
does not establish a statistically significant improvement or long-term behavior.
An earlier 8 MiB warm-up overlapped compilation and was discarded. Raw final
samples and process/cgroup snapshots are retained locally in
`/tmp/kura-private-resource-{before,after}-final/`.

### Review corrections: local validation, 2026-09-28

All 54 focused tests passed: 42 sync, 6 membership/body/discovery, and 6
configuration/topology tests. New regressions exercise forward pages without a
head start, local siblings excluded from donor preference, cancellation,
asymmetric private probes with stable local gateway election, failed route probes
preserving advertised traffic state, a real six-second canonical status response,
and wrong-tenant responses completing discovery without adding peers. Provider-only
configuration fails at startup. Clippy with warnings denied, formatting, and
whitespace checks passed. The corrected release Docker build and local three-node
mTLS ShellSpec suite passed (2 examples, 0 failures).

The resource harness ran sequentially again after compilation finished. The
baseline image's source, Cargo manifests/lockfile and Dockerfile were compared
byte-for-byte with current merge base `9abf2c87f8da51ae566d7f80f203d424e4b6b970`.
The corrected image was `sha256:d786e802c2027ce9eff3da501fdcccb21e8de1865a4d0a5a4d4bc2a3b569ac92`.
Both runs completed the same 320 one-MiB writes, 768 load reads, 192 seed
verification reads and full replication, with zero failures. Load lasted
63.784 / 63.783 seconds, followed by the same 30-second cooldown.

| Measurement | Main baseline | Review corrections |
| --- | ---: | ---: |
| Process CPU seconds | 22.03 | 20.29 |
| CPU seconds / client GiB | 17.624 | 16.232 |
| Anonymous memory peak / cooldown, MiB | 441.73 / 290.55 | 359.16 / 273.05 |
| Allocator allocated peak / cooldown, MiB | 55.93 / 28.34 | 50.56 / 28.28 |
| Allocator resident peak / cooldown, MiB | 194.72 / 65.93 | 154.60 / 65.57 |
| Highest pressure / capacity sheds | normal / 0 | normal / 0 |
| Transient reservation peak, MiB | 3.00 | 3.00 |
| Data-volume bytes | 1,008,069,282 | 1,008,070,811 |
| Segment refresh bytes | 0 | 0 |
| Client egress / peer applied payload, MiB | 960 / 640 | 960 / 640 |
| Interface transmit, MiB | 1623.98 | 1624.14 |

Disk differed by 1,529 metadata bytes and network transmit by 168,924 bytes
(about 0.01%); payload retention/transfer totals were identical. No pressure,
shedding or segment refresh occurred. No material regression appeared in this
bounded run; lower CPU/memory is not a statistically established improvement.
Raw samples are local in `/tmp/kura-review-resource-{before,after}/`.
The earlier staging validation covers the pre-review image only. No staging
retest or persistent staging pin is planned; ordinary deployments may replace it.

### Evidence still required

No private reachability, interface capture, sustained bandwidth, MTU, N-1 headroom,
or production deployment has been completed yet.
Provider permissions/product confirmation and the reviewed host cutover above
are required before those observations can be made. The current change provides
the opt-in runtime policy, tests and verification procedure; it does not claim
that the requested provider networking has already been provisioned.

### Staging deployment and E2E validation, 2026-09-28

The [Linux Bazel image build](https://github.com/tuist/tuist/actions/runs/36412698258)
succeeded for commit `dcb6a17aad0f`, publishing
`ghcr.io/tuist/kura:sha-dcb6a17aad0f`. The isolated staging test mesh ran that
image on the existing Dedibox, OVH BHS and Scaleway cache hosts. Synthetic
`test-provider-a` / `test-provider-b` metadata exercised policy decisions;
these hosts are **not** being claimed as one verified private routing domain.
Staging has no Vultr host and no qualified OVH vRack pair.

The [reusable fixture and validation instructions](../../kura/test/e2e/provider-topology/staging/README.md)
and [recorded results](../../kura/test/e2e/provider-topology/staging/validation-2026-09-28.json)
cover:

- Four nodes / three origins, with same-region siblings and all-origin writes
  arriving byte-for-byte at every node.
- Batched bodies and a 33 MiB individual body; both canonical and private
  entrances reject missing client certificates.
- A NetworkPolicy blackhole of replica B's private port, while its canonical
  endpoint remains reachable. Private probes reported failure, cross-provider
  replication continued, and canonical audit logs contained **zero**
  same-provider data requests. The audit observed 1,058 same-provider discovery
  requests and 796 cross-provider data requests across the fixture run.
- Recovery after lifting the blackhole; cold sibling restart and full backfill;
  bidirectional overlap with previous staging image `sha-c07fa5b26287`; upgrading
  that peer again and restoring all eight retained test objects.
- Namespace deletion markers reaching every node. All four final reports were
  ready, serving, initial catch-up complete, and at normal memory pressure.

The initial Service-port fault was rejected by the test because pooled
connections survived it. The policy blackhole replaced that ineffective
injection; a successful data test without an observed failure was not counted.
All disposable fixture resources were removed after retaining the evidence.

The recorded staging results apply to image `sha-dcb6a17aad0f`, before the review
corrections to scheduling, probe-health isolation, configuration and legacy
discovery. Those corrections receive local regression validation; another staging
run is not planned. Normal staging deployments may replace the temporary runtime
pin. No persistent chart pin is introduced. Historical deployment observations
belong in the private operational record; check live state before any rollback.
