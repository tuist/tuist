# Provider-private Kura replication

This is the private-network slice of [Atlas spec 98](https://atlas.tuist.dev/engineering/specs/98).
Spec 95 is already shipped. This change adds managed OVH attachment, persistent
private host routes and automatic runtime topology publication. It also adopts
an already-prepared staging cache host to qualify the physical path. Ingress,
BGP and host migrations remain outside this change. **All three managed
environments enable OVH reconciliation and automatic runtime topology on merge.
Their private host configuration is already installed and qualified within the
limits recorded below. Canary and production managed runtime templates will
activate through the normal deployment after matching route attestations.**
Chicago Vultr now also has a qualified private path and Kubernetes-owned network
reconciliation. Its merge activation and Santiago limitation are described in
[Vultr private networking](vultr-private-networking.md).

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
  exception. Reciprocal `canonicalPeers` approvals explicitly allow canonical
  mTLS between regional VPCs; within each VPC replication remains private-only.
  Separate ORD and SCL VPCs are provisioned. See
  [Vultr provisioning and qualification](vultr-private-networking.md) for the
  completed Chicago attachment, MTU and E2E qualification, Kubernetes ownership,
  and the remaining Santiago/cross-domain gate.
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
In managed deployments, `private_url` and `KURA_NODE_URL` use the same per-pod
DNS name. Host routes and unreachable guards enforce the physical private path;
the qualified scheduling selector keeps new pods on prepared hosts. Runtime
topology adds domain compatibility checks and private-donor preference, and
supports standalone deployments whose private endpoint differs from their
canonical endpoint. It does not create a second physical path for managed pods.
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
The managed controller can derive these fields from actual Node provider IDs and
the CAPI controller's converged private-route attestations. The environment
settings and fail-closed host routing are described in
[private-network-provisioning.md](private-network-provisioning.md). Staging
enables both host reconciliation and automatic runtime publication after its
physical qualification. Canary and production also enable both settings; their
merge deployment publishes topology after the CAPI provider verifies the prepared
hosts. Vultr Chicago follows the same publication boundary after its qualified
host routes converge; Santiago retains canonical mTLS. Other unqualified
placements retain their existing behavior. See the provider-specific guide.

Provider-only configuration is rejected at startup: opting in requires both
`private_network` and `private_url`. Different same-provider domains require
reciprocal exact-ID approval in `canonical_networks` to use canonical mTLS;
absent or unapproved domains fail visibly in replication errors and private-probe
logs. The allowlist is limited to 32 distinct remote IDs. Same-domain traffic
always uses the private URL. Failed private requests never retry
publicly. Listings, forward reads, batches and individual bodies all use the same
selector; canonical peer identities and watermarks remain unchanged. Disabling
redirects and environment proxies in topology mode prevents a selected private
request from being diverted to a public origin. Certificates still rotate through
the existing client factory. These transport restrictions apply only to peer
traffic. The analytics outbox uses the ordinary control-plane analytics client,
with its configured timeout, public trust, redirects and environment proxies.

Among equivalent healthy remote-region candidates, prefer the same provider
with a compatible private domain. The local gateway election stays deterministic
and published roles remain authoritative. Local private-probe health is separate
from the peer's advertised serving/draining state and affects only remote donor
ranking and preference. Canonical status requests retain the existing client
read timeout and discovery-observation semantics, including when topology is off.
Remote backward passes give healthy same-provider donors in remote regions a
bounded 200 ms head start to claim common bodies; local siblings never trigger
that delay. This is a best-effort timing preference, not strict donor priority:
a slow private listing can lose a claim, and a public pass can wait even when the
private donor lacks that artifact. Strict priority would require a bounded
discovery/dispatch scheduler; reordering claim waiters alone cannot establish
which peers have an artifact before they list it. All passes still run,
forward replication is never delayed, and a preferred peer
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

## Qualification record and ongoing coverage

[PR #13676](https://github.com/tuist/tuist/pull/13676) preserves the initial
staging, OVH and Chicago qualification results, tested revisions, resource
comparisons and limitations. One-off deployment fixtures and dated snapshots
are historical evidence, not maintained deployment inputs.

The maintained coverage consists of Rust routing/replication regressions, the
[ShellSpec mTLS suite](../../kura/spec/e2e/mtls_spec.sh), the
[local resource harness](../../kura/test/e2e/provider-topology/README.md), and the
[host path checker](verify-private-path.sh). Repeat the qualification sequence
above when adding a host or routing domain; store run-specific captures and
results with that rollout's record.

The initial OVH qualification covered physical staging and production paths;
canary had only one physical host, so its colocated replicas did not qualify a
host pair. Chicago qualification does not qualify Santiago or an ORD–SCL private
interconnect. Bounded tests near 200 Mbps do not establish saturation throughput
or N-1 rebuild capacity. Later code changes require their own appropriate
validation; historical captures are tied to their tested revisions.
