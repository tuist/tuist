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

Attachment intent is also saved before the non-idempotent POST. A pending or
uncertain attachment is observed until its assigned NIC appears; a controller
restart never resubmits it blindly. After confirming a rejected operation in the
provider, an operator may clear that instance's `attachmentRequests` entry to
retry. Successful network and per-host attachment reads are shared across
reconciles for at most one minute; a mutation invalidates its attachment cache.
Failed reads are not cached. Out-of-band provider changes can therefore take up
to one minute to be observed.

For a qualified region, the controller attaches each cache host without a
restart, checks the provider-assigned private address and MAC, and uses its
existing pinned bootstrap connection to configure only the secondary NIC.
It reuses the OVH host-route implementation: persistent private addresses,
public-node /32 routes through private next hops, main-table unreachable guards,
a repair timer, and guards ordered before kubelet/containerd startup. Vultr
restores the qualified 1500-byte private-NIC MTU and checks full-size DF pings
before route publication/repair, including after provider configuration drift. Public
NICs, default routes, node identities, ingress and BGP stay intact. Network
errors are visible in `PrivateNetworkReady` and do not stop ordinary node
reconciliation.

Every participant must attest the same network and membership on its current
boot before the CAPI controller labels placement as qualified. The Kura
controller then renders `KURA_PEER_TOPOLOGY` and restricts scheduling to that
network. A stale boot, missing attestation or mixed placement holds publication.
An already-managed topology is never silently removed on an observation error.
Its previous topology and scheduling selector are retained while image, resource,
and scaling updates continue. Route guard ownership and retirement follow the
[shared host lifecycle](private-network-provisioning.md); provider-specific root,
MTU and DF-probe options are explicit renderer parameters.

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

## Qualification scope

The initial Chicago qualification used two existing bare-metal hosts and
verified manual attachment without reboot, bidirectional 1500-byte paths,
private Cilium VXLAN, authenticated Kura replication, failure without public data
fallback, recovery, cold backfill and mixed versions. Temporary fixture resources
and host configuration were removed afterward; provider attachments remain for
controller adoption. The [PR validation record](https://github.com/tuist/tuist/pull/13676)
contains the tested revisions, capture counts and measured results.

This qualified the Chicago path. It did not establish saturation throughput,
N-1 capacity, Santiago transport or persistence across a production reboot.
The new Vultr controller was tested locally, not deployed in that qualification
window. New hosts and controller changes still need appropriate validation.

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

Rollback is explicit: hold topology publication and runtime rollout, withdraw
runtime topology through the normal rollout, then remove the controller-owned
host services/routes/guards in a scoped operational window if public node
transport is intended. Disabling a Helm flag alone does not remove persistent
routes, clear retained state, detach a NIC or delete a VPC. Keep guards in place
until runtime policy has been rolled back; ordinary private-path failures never
select the public default automatically.
