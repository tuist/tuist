# EU-West migration from Scaleway Dedibox to OVH

Status: all three servers verified through OVH and Ubuntu installation requested,
2026-09-25. Installation tasks are queued; completion and SSH validation are
pending. The production fleet configuration is prepared locally at zero replicas.
No cluster adoption or workload migration has been performed as part of this plan.

Fleet configuration changes go through a pull request and the normal production
deployment workflow. Do not apply the rendered fleet objects directly. Subsequent
replica increases and retirement configuration also require reviewed changes;
operational evacuation actions follow the human-granted production access policy.

## Decision and scope

Move the public `eu-west` region to OVH in France, using the existing
`OVHDedicatedMachine` integration. Keep the region ID, cluster ID `eu-west-1`,
KuraInstance identities, account hostnames, ingress class `kura-eu-west`, replica
count, and `scw-local-nvme` StorageClass unchanged. Retain the Scaleway Elastic
Metal runner cache and Mac fleet until the separate rack migration.

Temporarily give OVH EU-West nodes the existing `kura-dedibox` pool label. This
is a scheduling compatibility choice, not a claim about their provider. The
OVH fleet's CAPI ownership, adoption prefix, and credentials remain distinct.
Rename the pool in a later coordinated change, after all environments have
completed the provider migration.

Buy vRack-compatible servers, but migrate using the existing working network
path first. Enabling vRack for production traffic is a separate rollout with
its own routing, MTU, policy, shaping, and rollback validation. The current OVH
provider reads vRack bandwidth metadata but does not implement vRack membership
and interface provisioning. Moving the hardware alone will not move traffic
onto vRack.

## Evidence and capacity

Read-only production observations on 2026-09-25:

| Item | Observation |
| --- | --- |
| Dedibox nodes | Three, all Ready |
| Allocatable memory | Approximately 27.7, 87.6, and 27.7 GiB; approximately 143 GiB total |
| Allocatable CPU | 31 logical CPUs per node |
| Allocatable ephemeral storage | 900,327,118,587 bytes per node; verify actual `/data` separately |
| Advertised public egress | 1,000 Mbps per node |
| EU-West instances | 39, all reporting Ready, two replicas each |
| Declared storage across both replicas | 1,718 GiB; reserved capacity, not measured used bytes |
| Declared memory floors across both replicas | 44.5 GiB |
| Declared memory ceilings across both replicas | 178.5 GiB |
| Rendered egress floors across both replicas | 750 Mbps |
| Placement | All instances select `node.cluster.x-k8s.io/pool=kura-dedibox` |

### Purchased configuration: three Advance-1 servers

The order contains three **Advance-1 with EPYC 4244P, 32 GB RAM, two 960 GB
NVMe devices, 3 Gbit/s guaranteed public bandwidth, and 25 Gbit/s private
bandwidth**, in Gravelines. Configure mirrored storage. This is the 2024
Advance-1 offer, not the separately priced 2026 model. The supplied quote is
$147 per server per month plus $147 setup, excluding tax: **$441/month and
$441 setup**, or $882 for the first month. Three quoted Advance-2 servers
would cost $594/month; Advance-1 saves $153/month with the same quoted network
and disks. Confirm the final cart retains these exact specifications.

The scope is to move the current pods, with all three destination hosts
available. One-node recovery capacity is not a procurement requirement. The
existing Dedibox fleet also lacks full one-node recovery capacity: even before
the 85% admission margin, two nodes provide only about 1,677 GiB of allocatable
ephemeral storage against 1,718 GiB of current reservations. A fourth OVH node
is an optional future increase in resilience or growth capacity.

### Delivered servers

OVH API inventory on September 25 confirms the exact ordered specifications on
all three hosts: EPYC 4244P, 32,768 MB memory, two 960 GB NVMe drives, 3,000 Mbps
public egress, and 25,000 Mbps vRack bandwidth, in `gra04`. All were uninstalled
(`none_64`), had no installation tasks, retained their default display names,
and were absent from production's OVHDedicatedMachine inventory before prep.

| Service name | Public IPv4 | Installation task | OVH planned start (Europe/Berlin) |
| --- | --- | --- | --- |
| `ns3262309.ip-51-75-213.eu` | `51.75.213.141` | `569534258` | 2026-09-25 18:46:05 |
| `ns3263754.ip-51-75-213.eu` | `51.75.213.81` | `569534276` | 2026-09-25 18:46:14 |
| `ns3263776.ip-51-68-54.eu` | `51.68.54.127` | `569534289` | 2026-09-25 18:46:22 |

The existing `cmd/prep` installer was built and invoked with the production
`OVH_API` credentials and `OVH_FLEET_SSH` public key from 1Password, without the
marking step. Each API request succeeded. The first follow-up observed all three
`reinstallServer` tasks in `todo`; planned start is provider-reported, not a
completion estimate. Do not resubmit installation merely because it is queued.

Use fleet name `tuist-tuist-ovh-fleet-eu-west` and adoption prefix
`tuist-kura-ovh-production-eu-west`. Add its production values before invoking
`baremetal:prep-ovh`: the script resolves the SSH item and adoption prefix from
those values and otherwise falls back to the singular OVH fleet. Stage with
`PREP_NAMESPACE=tuist-production PREP_SKIP_MARK=1` to install Ubuntu, the fleet
key, and the mirrored root plus separate XFS `/data` without making the servers
adoptable. Marking and cluster adoption follow the rollout gates below.

### Preparation validation

- Production Helm rendering succeeds with the new fleet at zero replicas,
  the `kura-dedibox` pool, `gra` datacenter prefix, exact observed commercial
  range, and 3,000 Mbps egress budget.
- The render adds the fleet's MachineDeployment, OVHDedicatedMachineTemplate,
  and ExternalSecret. The quota exporter's affinity also gains a duplicate
  `kura-dedibox` value, with no change in matched nodes. Generated Secret values
  and their derived checksum vary between independent offline renders.
- `helm lint` reports an existing document-separator error in
  `templates/dedibox-fleet.yaml`; the same error reproduces with the EU-West
  entry removed. It is not introduced by this fleet configuration.
- Configuration is prepared for PR review and the normal deployment workflow,
  with no direct Kubernetes writes. `PREP_NAMESPACE=tuist-production` selects
  the preparation vault and values file; the workload objects themselves live
  in namespace `tuist`.

### Measured production demand

Grafana Cloud Prometheus (`grafanacloud-prom`) was queried for the seven days
ending **2026-09-25 15:35 UTC**. The three production Dedibox nodes each have
10,079 memory samples out of approximately 10,080 expected at one-minute
scrape intervals. Regional peaks below are maxima of simultaneous sums, not
sums of independently occurring per-node peaks. Legacy pod names containing
`eu-central-1` are included alongside `eu-west-1`; the private runner cache is
excluded. The current 39 instances have 78 replicas.

| Measurement | Whole-region observation |
| --- | --- |
| Public physical NIC transmit, five-minute rate | 632 Mbps peak; 250 Mbps p95 |
| Public physical NIC transmit, two-minute rate | 937 Mbps peak |
| Public physical NIC transmit, one-hour rate | 262 Mbps peak |
| Host memory used, `MemTotal - MemAvailable` | 21.8 GiB peak; 17.7 GiB p95 |
| Kura container working set | 20.6 GiB peak |
| Kura total cgroup memory charge, including file cache | 63.6 GiB peak |
| Kura anonymous memory | 5.0 GiB peak |
| CPU busy time, excluding idle/iowait/steal | 9.65 logical cores peak at five-minute averaging |
| Current `/data` used across the hosts | Approximately 1,006 GiB, including non-cache files |

Transmit is measured on `enp1s0f0` and includes replication and overlay traffic,
not only client responses. Two-minute rates still hide shorter bursts. A
14-day check gives the same host-memory, five-minute transmit, and CPU maxima,
but the fleet changed during that window, so it is not a long-term growth
forecast. The file-cache charge is useful cache capacity and can affect hit
rates/latency; it should not be mistaken for entirely unreclaimable RAM.

### Reservations and capacity

Current rendered Kura pod requests total **25.75 CPU cores, 44.5 GiB memory,
1,718 GiB ephemeral storage, and 750 Mbps egress floors**. The memory-ceiling
extended resource totals 178.5 GiB, but is scheduled with a factor of four
oversubscription; it is not a request for that much physical RAM. Current
platform overhead is approximately 0.44 CPU and 1.11 GiB of memory per node.

The already deployed US-East Advance-1 nodes provide a concrete comparison:
each has 11 allocatable logical CPUs and at least 27.41 GiB allocatable RAM.
Use the lowest observed allocatable ephemeral storage, **745.4 GiB per node**,
rather than raw disk capacity. Apply the existing 85% storage admission limit.
Verify these figures on the newly installed machines before migration.

| Capacity | Three Advance-1 nodes available | Two Advance-1 nodes available |
| --- | --- | --- |
| CPU available to Kura after platform requests | 31.68 cores: fits | 21.12 cores: below 25.75 requested |
| Memory available to Kura after platform requests | 78.9 GiB | 52.6 GiB |
| Storage reservations allowed at 85% | 1,901 GiB: fits | 1,267 GiB: below 1,718 requested |
| Aggregate nominal public bandwidth | 9 Gbit/s | 6 Gbit/s |

A capacity packing calculation assigned all 39 account pairs to three
Advance-1 nodes, conservatively keeping each account's two replicas together.
Each simulated node holds 26 pods. CPU requests including platform overhead
are 9.09, 9.24, and 8.74 cores; memory requests including overhead are 15.6,
16.1, and 16.1 GiB; storage reservations are 580, 574, and 564 GiB. Egress and
memory-ceiling extended resources also fit. This is a feasibility calculation,
not an actual scheduler or hardware performance test; fragmented placement
can require a controlled rebalance.

Three servers fit the current workload, with about 183 GiB of additional
storage reservations before the 85% admission line. Plan another node or
larger disks as reservations approach that threshold. Keep Scaleway nodes
available throughout migration and validation, and recheck rendered requests,
storage, growth, and serving-plus-backfill performance before evacuation.
After retiring Scaleway, the three-node fleet cannot reschedule every replica
onto two nodes during an outage. A fourth server would provide that capacity
at current reservations, but would not itself guarantee immediate warm
host-failure recovery: current replica co-location is preferred, and both
copies can occupy one host.

### Memory incident to resolve before cutover

The 96 GB Dedibox (`...-97jqh`) recorded approximately 141 kernel OOM-kill
counter increments on September 24. Historical Kubernetes metrics identify
`kura-wise-eu-west-1-1` as OOMKilled, and both Wise replicas reached almost
their 4 GiB cgroup limit. This points toward a per-pod limit issue rather than
regional host-memory exhaustion, but does not establish that every OOM event
has the same cause. The last 20 hours of the measured window contain no new
host OOM-kill increments; that alone does not establish resolution. Investigate
the pod's limit, workload, and runtime memory controls before cutover. Buying
64 GB hosts would not automatically change a 4 GiB pod limit.

### Reproducing the sizing checks

Evaluate these instant PromQL queries at `2026-09-25T15:35:00Z` in
`grafanacloud-prom` to reproduce the host-memory and public-transmit peaks and
the pod request inventory. For a refresh, also verify that the node selector
still identifies precisely the public EU-West fleet; it will no longer do so
after moving that fleet to OVH.

```promql
# Simultaneous regional host-memory peak, GiB.
max_over_time((sum(
  node_memory_MemTotal_bytes{cluster="tuist-production",instance=~"tuist-tuist-dedibox-fleet-.*"}
  - node_memory_MemAvailable_bytes{cluster="tuist-production",instance=~"tuist-tuist-dedibox-fleet-.*"}
))[7d:1m]) / 1073741824

# Simultaneous regional public-NIC transmit peak, Mbps.
max_over_time((sum(rate(node_network_transmit_bytes_total{
  cluster="tuist-production",instance=~"tuist-tuist-dedibox-fleet-.*",device="enp1s0f0"
}[5m])))[7d:1m]) * 8 / 1000000

# Separate Kura requests from platform overhead using the pod names.
sum by (pod, container, resource) (kube_pod_container_resource_requests{
  cluster="tuist-production",node=~"tuist-tuist-dedibox-fleet-.*",
  resource=~"cpu|memory|ephemeral_storage|tuist_dev_egress_mbps|tuist_dev_memory_ceiling_mib"
})
```

Vendor references, checked 2026-09-25:
- [OVH US regional availability](https://us.ovhcloud.com/bare-metal/regions-availability/)
- [OVH Advance range](https://us.ovhcloud.com/bare-metal/advance/)
- [OVH vRack configuration](https://support.us.ovhcloud.com/hc/en-us/articles/360001410984-Configuring-the-vRack-on-your-dedicated-servers)

## Why retain the pool and StorageClass during the move?

`server/lib/tuist/kura/regions.ex` pins EU-West to `kura-dedibox` in every
environment. The regional ingress DaemonSet selects that pool, and the peer
demux takes one node selector from the region's instances. A per-account switch
to a disjoint OVH pool would therefore need more than an instance selector edit.
The evacuation controller also requires a Ready, schedulable destination that
matches the instance's existing selector.

The local-path StorageClass already serves OVH regions despite its historical
`scw-` name. Existing PVs remain host-bound; they cannot be reattached on OVH.
Evacuation deletes one replica's local claim and rebuilds it from peers. Keeping
the class and selector lets that existing sequence work across providers without
changing StatefulSet volume templates or forcing an unrelated region-wide roll.

## Delivery phases and gates

### 1. Rehearse the mixed-provider topology

Use an isolated staging rehearsal with an old node, an OVH destination, and a
two-replica test instance. Match production's shared pool, local storage, ingress,
peer demux, and Cilium policies. Keep real staging workloads outside destructive
rehearsal steps. Verify:

- A new local volume receives XFS project quotas and the expected capacity.
- Replication and Service routing work in both directions across providers.
- HTTPS, gRPC, peer mTLS, regional DNS, and any enabled stable hostname work with
  replicas split across hosts.
- Cordon plus `tuist.dev/kura-evacuate` moves the standby, waits for
  `backfill_initial_cycle: complete`, moves serving roles, and only then releases
  the old primary's volume. Readiness alone is insufficient.
- Requests using cached old DNS addresses still reach the selected primary
  through the old ingress and peer gateways during handover.
- Pausing and reversing a partially completed evacuation works without deleting
  the only warm copy.

The existing landing-node check examines readiness and selectors, not available
CPU, storage, taint compatibility, or extended-resource headroom. Demonstrate
actual scheduling and backfill capacity before treating its success as a gate.

### 2. Add OVH capacity without removing Dedibox

Deploy the reviewed `ovhFleets.eu-west` entry through the normal workflow:

- Dedicated fleet/adoption identity, e.g. `tuist-kura-ovh-production-eu-west`.
- `nodePool: kura-dedibox` for migration compatibility.
- Existing OVH API endpoint and SSH secret conventions; no separate account or
  new provider integration is required by this plan.
- Confirmed datacenter, offer match, public egress budget, and cache taint.
- Start at `replicas: 0`, which the map template supports. Prepare purchased
  hosts using `baremetal:prep-ovh`; increase replicas only once hosts are
  installed and adoptable, avoiding a fleet that wedges Helm readiness.

Preserve the regional ingress selector and egress-agent pool list. Verify that
local storage, quota exporter, ingress, peer demux, Cilium, and observability
DaemonSets land on both providers. Render charts to check shared-pool entries
and ensure nothing unintentionally changes the runner cache or other regions.

New uncordoned nodes in the shared pool can receive ordinary new/restarted
instances before evacuation starts. Treat the first node join as a production
serving change: the rehearsed image and network configuration must already be
ready. Do not rely on a later manual cordon to make that initial join inert.

Rehearse first, then migrate staging and canary in separate controlled steps
before production. If their procurement must happen later, explicitly retain
their Dedibox configuration and credentials; a production-only move is not a
complete Scaleway exit.

### 3. Evacuate production one source node at a time

Choose the first node from current instance placement and measured used bytes,
favoring the smallest backfill and lowest traffic. Before beginning, retain
enough OVH-only capacity for the eventual full region plus the agreed headroom.
Cordon the old Dedibox nodes to prevent replacement replicas landing on another
node that will also be retired; cordoning alone does not evict existing pods.
Annotate only the selected source node for evacuation.

One node annotation can move replicas for multiple instances concurrently: the
controller serializes each instance, not the entire node. Establish an acceptable
backfill bandwidth and concurrency envelope in rehearsal. If one node's fan-out
cannot fit that envelope, add a bounded evacuation control as a prerequisite;
do not assume the current controller already provides a per-account batch knob.

For each node, require:

1. Every affected instance retains a serving endpoint throughout the move.
2. Rebuilt replicas report completed backfill; peer errors and lag settle.
3. No unexpected Pending pods, quota errors, OOMs, CPU throttling, or sustained
   latency/error regression against the recorded baseline.
4. Regional and enabled stable DNS point to healthy gateways; old cached targets
   remain functional while still in use. Check client and peer paths separately.
5. All cache pods and live claims have left the source, and the next batch has
   adequate destination capacity.

Stop before the next node if any gate fails. Keep source machines, ingress, and
peer gateways alive through DNS TTLs, observed resolver behavior, long-lived
connections, and a proposed 48-hour soak including a representative busy period.
The soak starts after the last successful handover, not after provisioning.

### 4. Retire and clean up

Only after the soak, reduce the Dedibox fleet through its owning CAPI resources
and the declarative deployment path. Confirm the chosen Machine deletions target
evacuated hosts. Do not use a generic drain or delete a live cache Machine as the
migration mechanism. Provider release may reinstall/wipe a box; this is the
boundary after which its old disks are no longer a recovery option.

Confirm release and provider billing cancellation separately. Retain Dedibox
credentials/controllers until staging and canary no longer need them. Keep all
Scaleway Elastic Metal and Apple Silicon resources needed by runners.

Update region/provider documentation and location metadata for the selected
datacenter. `FR-IDF` currently describes Paris and is incorrect for Gravelines;
audit the metadata's consumers and introduce any per-environment handling needed
while environments differ. Preserve the product region ID and review its
Route53 latency-region mapping separately from the physical-site description.

## Rollback

Before evacuation, leave the source fleet serving and stop introducing new
capacity. Once evacuation has started, remove evacuation intent from affected
source nodes and uncordon only healthy sources when needed. Already-deleted
claims are not restored by removing an annotation or reverting Helm values.
Inspect in-flight deletes before changing intent and preserve healthy serving
replicas on both providers.

If workloads must return to Dedibox, verify capacity, then reverse the same
controlled evacuation from OVH toward healthy Dedibox nodes, including backfill,
Service handover, DNS convergence, and connection drain. Do not flip DNS to an
empty cache or delete OVH capacity while it holds the surviving warm replica.
Retaining old hardware preserves a destination, not an untouched disk snapshot.

## Implementation boundaries and remaining decisions

Prepare separate reviewable changes for (1) fleet addition and rehearsal,
(2) staged evacuation/retirement configuration, and (3) naming cleanup and vRack
enablement. Re-run relevant fleet/chart tests and the controller's evacuation,
DNS, peer-demux, and storage tests when changing those paths. Record actual
staging and production observations alongside the eventual rollout, not merely
unit-test results.

Procurement is complete. Before cutover, validate the installed machines,
finalize measured backfill limits and latency/error stop thresholds, verify
old-IP forwarding, and secure the normal human-driven production write elevation
for operational actions. Fleet changes deploy through reviewed pull requests.
This document does not itself authorize migration or contract cancellation.

Planning validation: inspected fleet templates, region mapping, local-storage
provisioning, ingress selectors, peer-demux selection, and evacuation code;
queried production nodes, instance specs/status, and pod placement read-only.
No workload tests or benchmarks were performed. The user ordered the servers;
the installation requests and their provider task IDs are recorded above.
No Kubernetes writes or workload migrations have been performed.
