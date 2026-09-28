# Vultr private networking

Vultr VPCs provide a private network inside one location. They do not establish
an ORD–SCL private path. Vultr's documented cross-location solution uses
[WireGuard gateways](https://docs.vultr.com/how-to-peer-vpcs-between-vultr-locations-with-wireguard),
which encrypt public transport. Existing Kura mTLS already authenticates and
encrypts that replication. [Direct Connect](https://docs.vultr.com/vultr-direct-connect)
would be a separate transport project requiring confirmed coverage, redundancy,
pricing and provider coordination.

## Kubernetes ownership and merge activation

`capi.vultrPrivateNetwork` declares each region's VPC description, CIDR and
physical qualification in Helm. Production declares `tuist-kura-production-ord`
(`172.30.244.0/24`, qualified) and `tuist-kura-production-scl`
(`172.30.245.0/24`, unqualified). Self-hosting defaults to disabled.

`VultrMachineReconciler` manages networks for enrolled cache fleets in its
configured namespace. It adopts an exact existing VPC or creates the missing
empty VPC, checks the full provider inventory for conflicts, and retains the
provider identity in a separate controller-owned `<config>-state` ConfigMap.
It records creation intent before the provider POST. A timed-out create is
recovered by observing the exact network; an empty subsequent inventory never
causes a blind retry. Missing retained networks, changed definitions and
ambiguous inventories require explicit recovery. Neither Helm removal nor
Machine deletion deletes a VPC or its retained state.

For a qualified region, the controller attaches each cache host without a
restart, checks the provider-assigned private address and MAC, and uses its
existing pinned bootstrap connection to configure only the secondary NIC.
It reuses the OVH host-route implementation: persistent private addresses,
public-node /32 routes through private next hops, main-table unreachable guards,
a repair timer, and guards ordered before kubelet/containerd startup. Public
NICs, default routes, node identities, ingress and BGP stay intact. Network
errors are visible in `PrivateNetworkReady` and do not stop ordinary node
reconciliation.

Every participant must attest the same network and membership on its current
boot before the CAPI controller labels placement as qualified. The Kura
controller then renders `KURA_PEER_TOPOLOGY` and restricts scheduling to that
network. A stale boot, missing attestation or mixed placement holds publication.
An already-managed topology is never silently removed on an observation error.

The merge deployment therefore enables Chicago private replication after this
convergence gate. Normal managed rollout and existing OnDelete holds still
apply; merge does not instantly restart every runtime. Santiago's VPC is managed,
but its host attachment and runtime topology remain disabled pending regional
qualification. The existing Santiago canonical mTLS link remains compatible
with Chicago's enabled topology because Santiago advertises no topology.

Do not qualify a second Vultr region under the current strict same-provider
policy. It rejects incompatible private domains. The controller rejects multiple
qualified regions until an explicit allowed-canonical-domain policy is added
and tested. Unknown or mistyped domains must never become public automatically.
An ORD–SCL private interconnect is not provisioned by this PR.

## Physical qualification

The [Chicago evidence](../../kura/test/e2e/provider-topology/vultr-chicago-qualification-2026-09-28.json)
records qualification on the two existing bare-metal hosts under a scoped human
production window. Both VPC attachments and manual secondary-NIC configuration
worked without rebooting. Both directions passed unfragmented 1500-byte traffic
with assigned private addresses and with existing public node identities.
Actual Cilium VXLAN carried an isolated four-peer Kura fixture between the hosts.

All 12 runtime checks passed, including a 33 MiB exact-byte transfer, mTLS
rejection, observed fixture-only private failure without canonical data fallback,
recovery, cold backfill, mixed versions and tombstones. A second 33 MiB transfer
used immediate captures filtered to the fixture PodIPs: both private NICs saw
thousands of matching packets and both public NICs saw zero. The earlier broad
node capture had two unconsumed public-filter counter hits and is not used to
claim zero public traffic across the entire host. Bounded ten-second TCP tests
reached approximately 200 Mbps in both directions with zero retransmits.

Temporary fixture resources, peer routes and secondary-interface configuration
were removed after qualification. Provider attachments are retained for the
controller to adopt on merge. No production runtime was deliberately restarted.
The evidence separates endpoint/pod snapshots from continuous availability
monitoring. This test does not prove saturation throughput, N-1 capacity,
Santiago transport or persistence across a production reboot. Persistence uses
the shared host service already exercised by the OVH rollout; Chicago was not
restarted solely to test it. Controller reconciliation is tested locally; the
new controller image was not deployed during this qualification window.

## Repeating qualification

1. Re-query actual host placement, provider attachments and routes. Replicas are
   preferably colocated; multiple tenants on different hosts do not create a
   replication pair. Do not move serving volumes just to exercise a VPC.
2. Use the current bare-metal API. The official
   [Go SDK](https://github.com/vultr/govultr/blob/master/bare_metal_server.go)
   uses `GET /v2/bare-metals/{id}/vpcs` and
   `POST /v2/bare-metals/{id}/vpcs/attach`. Refuse a foreign attachment; never
   detach it to make this configuration fit.
3. Allocate a separate nonoverlapping private CIDR after checking host, Pod,
   Service, tailnet and runner routes. Verify assigned addresses and physical
   MACs. Keep host IDs, public addresses and tenant inventory in private records.
4. Obtain a scoped human-controlled production window before host changes,
   exec or fault tests. Follow [the access rules](../AGENTS.md#cluster-access-for-agents).
   The [bare-metal guide](https://docs.vultr.com/products/compute/instances/bare-metal/networking/vpc)
   describes a restart for Cloud-Init configuration; the authenticated console
   offers manual IP configuration as its alternative. Use the manual path and
   verify boot continuity. Do not reboot serving hosts merely to run Cloud-Init.
5. Check private reachability both ways, source-address acceptance and real path
   MTU before routing node identities through private next hops. Vultr examples
   using 1450 do not establish a maximum for every bare-metal fabric. Require
   unfragmented packets and actual encapsulated traffic; do not lower the entire
   cluster MTU to make an unqualified path pass.
6. Prepare all peers, then test isolated authenticated Kura replication, a body
   larger than 32 MiB, both physical NICs, fixture-only failure and recovery.
   Preserve canonical cross-provider links. Synthetic provider roles in a
   Chicago-only fixture test policy, not a new physical cross-provider edge.
7. Publish qualification only for the tested routing domain. Validate persistence
   during an approved maintenance restart or on isolated capacity; extra paid
   hardware is optional, not required for the manual attach path.

## Bootstrap and recovery tooling

`cmd/vultr-vpc` remains a read-only planner by default. `--apply` creates only an
empty VPC; it cannot attach hosts, reboot, or order compute, NAT or interconnects.
An exact network is reused; duplicate descriptions, changed location/subnet,
overlap and malformed inventories are rejected. Serialize CLI creates with the
controller and inspect uncertain outcomes before clearing retained intent.

From `infra/cluster-api-provider-tuist`, with credentials supplied through the
existing secret tooling:

```sh
go run ./cmd/vultr-vpc --region ord --description tuist-kura-production-ord --cidr 172.30.244.0/24
go run ./cmd/vultr-vpc --region scl --description tuist-kura-production-scl --cidr 172.30.245.0/24
```

Vultr's [published pricing comparison](https://marketing-sales-files.sjc1.vultrobjects.com/vultr-vs-do-saas-pricing.pdf)
lists VPC as free. NAT gateways are paid and unnecessary for these hosts.
The [provisioning evidence](../../kura/test/e2e/provider-topology/vultr-network-provisioning-2026-09-28.json)
and [initial investigation](../../kura/test/e2e/provider-topology/vultr-attachment-investigation-2026-09-28.json)
are historical observations preceding physical qualification.

Rollback is explicit: hold topology publication and runtime rollout, withdraw
runtime topology through the normal rollout, then remove the controller-owned
host services/routes/guards in a scoped operational window if public node
transport is intended. Disabling a Helm flag alone does not remove persistent
routes, clear retained state, detach a NIC or delete a VPC. Keep guards in place
until runtime policy has been rolled back; ordinary private-path failures never
select the public default automatically.
