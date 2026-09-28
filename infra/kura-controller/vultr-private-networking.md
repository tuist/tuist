# Vultr private networking

Vultr VPCs provide a private network inside one location. They do not establish
an ORD–SCL private path. Vultr's documented cross-location solution uses
[WireGuard gateways](https://docs.vultr.com/how-to-peer-vpcs-between-vultr-locations-with-wireguard),
which encrypt public transport rather than replace it with provider-private
transport. Existing Kura mTLS already authenticates and encrypts replication.

[Direct Connect](https://docs.vultr.com/vultr-direct-connect) can attach an
external physical or partner network to a location. Its documentation also
states that private networks do not cross locations. A private interconnect
between ORD and SCL would therefore be a separate transport project, requiring
confirmed coverage, topology, redundancy, pricing and provider coordination.
Do not assume two VPCs create that connection.

## Placement and rollout

The controller deliberately prefers colocating an instance's primary and warm
standby. Different instances are isolated tenants and do not replicate to each
other merely because they occupy different hosts in the same location.
We provision a VPC in each supported location so future off-host replicas can
use it. Inspect actual per-instance placement before attaching serving hosts:
multiple physical hosts in a region alone do not establish an off-host sibling.

The [read-only feasibility evidence](../../kura/test/e2e/provider-topology/vultr-network-feasibility-2026-09-28.json)
records provider API results and a placement snapshot without publishing host
IDs, addresses or tenant inventory. It is not physical network qualification.
Re-query placement before a rollout; co-location is a preference, not a guarantee.
Do not change placement or move node-local volumes merely to make a network
provisioning exercise pass.

## Bare-metal attachment and qualification

1. Use the current VPC API, not an assumed VPC 2.0 endpoint. The official
   [Go SDK](https://github.com/vultr/govultr/blob/master/bare_metal_server.go)
   uses `GET /v2/bare-metals/{id}/vpcs` and
   `POST /v2/bare-metals/{id}/vpcs/attach`. The general guide's `instances`
   example is not sufficient evidence for a bare-metal mutation. Verify actual
   host eligibility, current attachment, provider-assigned address and MAC,
   and charges before creating or attaching a network.
2. Allocate a separate, nonoverlapping subnet per location after checking host,
   Pod, Service, tailnet and runner routes. Preserve public NICs, default routes,
   node identities, ingress and BGP. Never move an existing VPC attachment.
3. The [bare-metal guide](https://docs.vultr.com/products/compute/instances/bare-metal/networking/vpc)
   documents a restart for cloud-init to configure the interface. Establish
   whether the exact host supports safe manual configuration without a restart;
   do not infer this from the API accepting an attachment. If a restart is
   required, verify a serving off-host sibling or obtain a maintenance decision
   for that instance. Two colocated replicas and one-host-at-a-time restarts
   do not preserve regional endpoint availability.
4. Obtain a human-controlled production window explicitly scoped to Vultr
   qualification before host configuration, pod exec or fault tests. An earlier
   OVH qualification window does not authorize this separate host work. Follow
   [the production access rules](../AGENTS.md#cluster-access-for-agents).
5. Verify both private directions and source-address behavior before reusing
   the OVH route design. That design carries public node identities through
   private next hops; a provider's source filtering may reject it. Do not assume
   that success with assigned private source addresses proves this path.
6. Measure the real private MTU. Vultr's
   [interface configuration example](https://docs.vultr.com/how-to-use-the-linux-ip-command-to-manage-server-network-interfaces)
   uses 1450. An additional Cilium VXLAN header can exceed that limit; neither a
   small ping nor assigning a 1500 MTU proves support. Require unfragmented path
   checks, actual encapsulated traffic and oversized Kura body replication.
7. Prepare every peer before installing persistent routes and public-fallback
   guards. Qualify mTLS, both physical NIC captures, bounded throughput,
   fixture-only failure, cross-provider continuity and recovery. Publish topology
   only after a provider-specific controller verifies converged host state.

## Runtime policy

Automatic managed topology currently covers OVH. Vultr retains canonical mTLS
replication. This is an explicit unqualified-provider state, not private VPC
activation.

Two qualified Vultr VPCs in different locations must not be enabled under the
current strict same-provider policy: that policy rejects incompatible domains.
To support local-private plus cross-location-public routing, add an explicit
configuration of permitted canonical domain pairs. Keep same-domain failures
private-only; unknown or mistyped domains must not become public automatically.
Test private local transfer and failed-private-path behavior separately from the
intentionally canonical cross-location link. Do not disguise regions as separate
providers or label separate VPCs as one private domain.

## Provisioning and current state

Two empty VPCs were created on 2026-09-28: `tuist-kura-production-ord`
(`172.30.244.0/24`) and `tuist-kura-production-scl`
(`172.30.245.0/24`). They do not connect to each other. The subnets are separate
from the cluster Pod/Service ranges and the three OVH environment subnets;
check actual host routes before attachment. Network creation does not attest a
private path. Provider-assigned IDs stay in operational state, outside this guide.

The bootstrap command reuses the CAPI Vultr client and reads `VULTR_API_KEY`
from the environment. It plans by default; `--apply` only creates an empty
VPC. It checks all API pages, rejects duplicate descriptions, mismatched existing
networks and overlaps, and reuses an exact match. It cannot order compute, NAT
or interconnect services, attach a NIC, or reboot a host. Run serially per account:
the provider has no create idempotency key. On a failed create, inspect provider
state before retrying rather than assuming nothing was created.

From `infra/cluster-api-provider-tuist`, with credentials injected through the
existing secret tooling:

```sh
go run ./cmd/vultr-vpc --region ord --description tuist-kura-production-ord --cidr 172.30.244.0/24
go run ./cmd/vultr-vpc --region scl --description tuist-kura-production-scl --cidr 172.30.245.0/24
```

Append `--apply` to create a missing network. These names and CIDRs are desired
bootstrap configuration; they do not enable the managed Kura topology flag for
Vultr. Vultr's [published pricing comparison](https://marketing-sales-files.sjc1.vultrobjects.com/vultr-vs-do-saas-pricing.pdf)
lists VPC as free. A NAT gateway is a separate paid product and is unnecessary
for these public-plus-private hosts.

## Isolated Chicago qualification

Use an unadopted Chicago bare-metal host matching the existing
`vbm-6c-32gb-amd` plan and a temporary `vc2-1c-2gb` VM in the same ORD VPC.
Both run Ubuntu 24.04, retain their public interface and have no fleet adoption
tag. This pair establishes the bare-metal-to-VM data path without attaching or
restarting a serving node. It does not by itself qualify every bare-metal pair
or the Santiago location.

1. Record both provider-assigned private addresses/MACs, host routes, interface
   state and path MTU. Confirm the fresh host's VPC setup survives a restart
   before it has any workloads.
2. Check private reachability both ways, then the public-node-source behavior
   used by the OVH design. Test unfragmented payloads and encapsulated traffic;
   do not publish a route attestation from small private-source pings alone.
3. If the underlay rejects public source identities or the required encapsulated
   MTU, design and validate a provider-specific path before altering cluster
   networking. Do not reduce the whole production cluster MTU as a test workaround.
4. Run isolated authenticated Kura peers with a body larger than 32 MiB. Capture
   both private and public interfaces, interrupt only the test private path,
   verify zero unintended public data fallback, then recover and backfill.
5. Implement and test the explicit cross-domain canonical policy above, and
   provider-specific persistent host reconciliation, before publishing managed
   Vultr topology. Keep OVH's already-qualified behavior intact.
6. Qualify bare-metal-to-bare-metal transport and each additional location during
   the controlled fleet rollout. If an existing host needs a restart, use spare
   capacity and the controller's documented staged evacuation before the restart;
   never delete a live Machine or its local volumes to force a network change.

The independent [provisioning evidence](../../kura/test/e2e/provider-topology/vultr-network-provisioning-2026-09-28.json)
records provider readback, attachments and tests separately from the earlier
placement audit. Vultr replication remains canonical mTLS until the physical
qualification and controller/runtime work above are complete. OVH's qualified
intra-region and inter-region private rollout is unchanged.
