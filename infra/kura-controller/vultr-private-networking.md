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
qualification gate in Helm. Production declares `tuist-kura-production-ord`
(`172.30.244.0/24`, qualified) and `tuist-kura-production-scl`
(`172.30.245.0/24`, qualified across two enrolled hosts). Self-hosting
defaults to disabled.

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
apply; merge does not instantly restart every runtime. Santiago also enables
managed host configuration and runtime topology. Its two enrolled hosts passed
bidirectional physical path/MTU and isolated replication checks after controller
route convergence. See the qualification scope below. Chicago–Santiago traffic
uses the reciprocal canonical mTLS policy below.

## Regional replication policy

Each region uses its own VPC for private replication between hosts. Declare
`canonicalPeers: [scl]` for `ord` and `canonicalPeers: [ord]` for `scl` to approve
canonical mTLS between those regions. Approval must be reciprocal and name
configured regions; all qualified regional pairs must be approved before the
controller makes provider changes. This is an explicit public inter-region path,
not an ORD–SCL private interconnect.

After local attachment and route convergence, the CAPI controller resolves
those names read-only: each region must already have a retained VPC ID matching
provider inventory (cached for at most one minute). Approval does not create a
remote VPC. Missing state or inventory errors preserve the published policy and
report `PrivateNetworkReady=False`, retried after 20 seconds; local attachment
and route repair still run. New topology publication waits for resolution. On
success it publishes the sorted remote IDs in the Node annotation
`tuist.dev/private-network-canonical-peers`. The Kura controller requires all
candidate Nodes to agree before adding `canonical_networks` to runtime topology.
The runtime accepts a different same-provider domain over canonical mTLS only
when both peers explicitly approve each other's exact VPC ID. Missing approval,
unknown IDs and typos fail closed. Within one VPC it always uses the private URL;
a private failure never triggers a public retry. Only same-VPC peers receive
private donor preference. Cross-provider and topology-free compatibility are
unchanged.

When adding another regional domain, deploy the policy-capable runtime and both
controllers first, with that region still `qualified: false`. Publishing the new
Node policy changes `KURA_PEER_TOPOLOGY` and triggers the normal StatefulSet rollout, even
if the runtime image is unchanged. Node patches are not atomic across hosts:
the Kura controller preserves existing topology until every candidate agrees.
Ready Vultr Machines normally reconcile every ten minutes (20 seconds on
private-network errors); Kura instances normally requeue every 30 seconds. A
values-only update can therefore take a full resync interval plus queue time to
converge. Observe the Node annotations and rollout completion instead of assuming
simultaneous patches. Verify all existing runtimes advertise the new region's VPC
ID before qualifying it: older runtimes ignore the additive policy field
and would reject the second advertised domain. Production has completed
this policy-capable runtime prerequisite and enables `qualified: true` for both
regions. For another region, qualify its host through the procedure below before
enabling it. A single host can validate attachment and runtime behavior, but
physical host-to-host private replication must be tested when a second host
arrives. Additional hosts join the same region's membership/route convergence
gate automatically.

For rollback, withdraw Santiago topology before rolling back to a runtime that
does not support regional policy. Preserve the host routes and network; do not
detach a live network. Removing approvals while both domains advertise topology
deliberately blocks their inter-region link.

## Qualification scope

The initial Chicago qualification used two existing bare-metal hosts and
verified manual attachment without reboot, bidirectional 1500-byte paths,
private Cilium VXLAN, authenticated Kura replication, failure without public data
fallback, recovery, cold backfill and mixed versions. Temporary fixture resources
and host configuration were removed afterward; provider attachments remain for
controller adoption. The [PR validation record](https://github.com/tuist/tuist/pull/13676)
contains the tested revisions, capture counts and measured results.

That initial window qualified Chicago; the new Vultr controller was tested
locally rather than deployed during that window.

Santiago subsequently passed physical validation on two controller-enrolled
hosts. Both reported `PrivateNetworkReady=True` with matching membership and
current-boot attestations. Each direction passed 1472-byte DF ICMP payloads
(1500-byte IP packets) without loss. Two isolated Kura peers, pinned one per
host and running the deployed runtime with their own mTLS CA, each originated
a 33 MiB + 1 byte object. Reads from the opposite peer matched SHA-256 and
length, and both sibling feeds settled at zero lag. Header captures filtered
to the fixture's inner Pod IP pair showed bidirectional Cilium VXLAN traffic
on both private NICs and no matching packets on either public NIC. Temporary
pods, services, test certificates and host capture files were removed.

The Santiago checks establish the healthy physical replication path; they do
not repeat Chicago's failure/recovery, cold-backfill or mixed-version tests.
Neither qualification establishes saturation throughput, N-1 capacity or
persistence across a production reboot. Existing serving volumes were not
moved; two enrolled hosts do not imply that an existing instance's replicas
are distributed between them. New hosts and controller changes still need
appropriate validation.

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
