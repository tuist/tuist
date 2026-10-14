# OVH Linux runner cache over vRack

The `ovh-gra-runners` private region places one Kura instance per eligible
account on the `kura-ovh-gra-runners` pool in Gravelines, beside production's
OVH Linux runners. It uses 50 GiB local NVMe claims with the existing XFS quota
provisioner, the account's peer mesh, and a 750 Mbit/s per-account egress cap.
It is hidden from public region selection. RunnerCache provisions and removes
instances according to runner access and Linux profiles, independently of the
Scaleway macOS cache.

Linux Kata pods reach their instance through its private ClusterIP Service.
Dispatch prefers that instance when active and keeps the existing public-region
Service fallback while it is provisioning or the region is disabled.

## What makes the traffic private

An internal Service URL alone does not select a physical network. This cluster
uses Cilium VXLAN between public Node addresses. The OVH controller configures
each participating box's private NIC and adds `/32` routes to participating OVH
Node addresses through their private vRack next hops. The VXLAN packets therefore
use vRack without changing the Node addresses that Hetzner and the API server
still need to reach. Kubernetes Service discovery and network policies continue
to work as before.

The host configuration is applied after the Node joins, including on existing
Ready Machines. It installs a systemd service and a 30-second timer, without
restarting kubelet, containerd, Cilium or runner VMs. The timer checks each private
next hop before installing its route and removes that route when the next hop
fails, allowing the existing public route to serve as a fallback. Route protocol
242 is reserved for this service; it only removes routes carrying that protocol.
Changes to fleet membership update the host's peer list on the controller's
normal reconciliation interval.

`VRackReady=True` and the Node's `tuist.dev/vrack-ready=true` label mean the
private NIC has been attached and the host configuration installed. The private
Kura region requires that label to schedule. They do **not** prove that traffic
is traversing vRack or achieving a particular throughput; verify both below
before advertising the region.

## Prerequisites

The checked-in production fleet is disabled until its capacity and network exist.
Do not enable the region against an empty or unconfigured pool.

1. Prepare a dedicated OVH cache box in Gravelines, under the same `ovh-us`
   account as the Linux runners. Choose its private bandwidth and NVMe capacity
   for concurrent restores from all six runner boxes. The runner values record
   1 Gbit/s private bandwidth; verify each actual contract and measure it rather
   than treating the switch's advertised link speed as usable bandwidth.
2. Create or select a vRack dedicated to this workload cluster. Reserve an unused
   private IPv4 `/24` through `/28` for the controller. It must not overlap the
   cluster, Scaleway PN, Docker, other host networks, or manually assigned
   addresses. One vRack/CIDR belongs to one cluster's allocator. Do not change it
   after addresses have been allocated; migrate by replacing Machines.
3. Every box needs exactly one non-aggregated private NIC. For configurable
   interfaces, it must already be enabled in `vrack` mode. The controller refuses
   to modify public interfaces, configure link aggregation, or move an interface
   out of a different vRack.
4. Extend the environment's existing OVH API credential with reads on
   `/vrack/<id>/*` and writes on `/vrack/<id>/dedicatedServerInterface` (or
   `/vrack/<id>/dedicatedServer` for legacy interfaces). Existing
   `/dedicated/server/*` reads cover interface discovery. No order, network
   creation or contract termination permissions are needed.

OVH references: [vRack interface setup](https://docs.ovhcloud.com/en/guides/bare-metal-cloud/dedicated-servers/vrack-configuring-on-dedicated-server)
and [private bandwidth](https://docs.ovhcloud.com/en/guides/bare-metal-cloud/dedicated-servers/manage-bandwidth-vrack-api).

## Activation

1. Set `machine.vRackID` and `machine.vRackCIDR` to the same values on
   `ovhFleets.gra-runners-cache` and `ovhFleets.runners-linux` in
   `values-managed-production.yaml`. Keep the cache fleet disabled and the
   region absent from `TUIST_KURA_AVAILABLE_REGIONS` for the first deployment of
   the controller and generated CRDs.
2. Prepare the **new cache box**, using its actual service name:

   ```bash
   PREP_NAMESPACE=tuist-production mise run baremetal:prep-ovh \
     <cache-service-name> tuist-tuist-ovh-fleet-gra-runners-cache
   ```

   This installs Ubuntu and the mirrored root/separate XFS `/data` layout,
   then sets the dedicated adoption prefix. Do not run prep on a live runner.
3. Set `ovhFleets.gra-runners-cache.enabled: true` and its replica count to the
   number of prepared cache boxes, then deploy. Its default `kura-cache` taint
   also includes the pool in the quota exporter's affinity. Keep it out of the
   public cache egress-budget pools.
4. Existing runner Machines use `OnDelete`, so changing their template does not
   update their specs. Under a human-granted production elevation, patch the
   existing `OVHDedicatedMachine` resources belonging to the **runners-linux
   fleet only** with the same `vRackID` and `vRackCIDR`. The Ready-path repair
   applies the network without replacing their hosts. Newly created Machines
   inherit the fields from the template.
5. Wait for all participating Machines to report `VRackReady=True` and unique
   `.status.vRackAddress` values. The controller reserves addresses before using
   them and retains the reservation through deletion until the host is wiped.
   Wait another reconciliation interval for both sides' peer lists to converge.
   Addressed Machines retain their finalizer until OVH confirms the release
   reinstall completed, so scale-down/replacement also includes the install
   duration (usually 20–40 minutes) after the normal job drain.
6. Verify the physical path and throughput below. Then append
   `ovh-gra-runners` to production's `TUIST_KURA_AVAILABLE_REGIONS` and deploy.
   Eligible Linux accounts receive their private instance on reconciliation;
   dispatch starts using it once active. Staging/canary keep their current
   configuration until equivalent capacity is prepared there.

## Verify the path, then performance

### Staging Gradle smoke

The staging capacity ordered for this rollout is:

| Role | OVH service | Public address | Hardware |
| --- | --- | --- | --- |
| Replacement Linux runner | `ns3066567.ip-193-70-46.eu` | `193.70.46.18` | RISE-M, 64 GB RAM, 2 × 512 GB NVMe |
| Private Kura cache | `ns3220989.ip-162-19-86.eu` | `162.19.86.189` | RISE-1, 32 GB RAM, 2 × 512 GB NVMe |

Both hosts belong to staging vRack `pn-2023588`, with 1 Gbit/s private
bandwidth per host. The existing RISE-S runner
`ns340020.ip-37-187-143.eu` stays in service until the replacement joins and
passes the smoke job; ordering replacement capacity does not retire it.
Use staging's `OVH_FLEET_SSH` key for both new hosts. Preparation installs
Ubuntu 24.04 with mirrored system partitions and a separate XFS `/data`.
Keep the hosts out of adoption until installation and SSH/storage checks pass.

Host preparation completed on 2026-09-17. Both hosts run Ubuntu 24.04.5 LTS,
accept the staging fleet SSH key, and have healthy RAID1 arrays for `/boot`,
the 64 GiB root filesystem, and approximately 411 GiB of XFS `/data`. Project
quota accounting and enforcement are enabled on `/data` and persisted in
`/etc/fstab`. Their verified adoption display names are
`tuist-runners-ovh-staging-pn` and `tuist-kura-ovh-staging-gra-runners`,
respectively. The runner's new RISE-M offer does not match the existing
RISE-S fleet; rollout must update that fleet's adoption filter and add the
Gravelines cache fleet before these hosts can join.

Bidirectional private-interface checks passed with five packets sent and
received in each direction, zero loss, and average RTTs of 0.714 ms and
0.234 ms. The runner uses `enp7s0`; the cache uses `enp3s0f1`. The first probe
preceded the cache NIC's link negotiation completing; wait for carrier before
testing freshly enabled interfaces. Temporary diagnostic addresses
`172.30.240.1/28` and `172.30.240.14/28` were removed after verification so the
controller can allocate its own addresses. These checks establish host-level
connectivity only; Kubernetes adoption, Cilium path verification, throughput
measurement, and the Gradle smoke job remain rollout steps.

Staging needs two vRack-capable OVH hosts: a Linux runner and a separate
Gravelines cache host. The existing RISE-S staging runner has no private NIC
(confirmed through the OVH API on 2026-09-14), so it cannot validate this path.
The BHS public-region cache is not a substitute for the Gravelines private pool.
Prepare equivalent staging capacity and enable the private region only after
the physical network checks below pass.

Run `.github/workflows/linux-runner-cache-staging-smoke.yml` on the deployed
branch, supplying a staging `account/project` belonging to the account that
owns the `tuist-staging-linux` runner profile. Set the repository secret
`TUIST_STAGING_GRADLE_SMOKE_TOKEN` to a token authorized for that staging
project before dispatching it. The job uses the checked-out Tuist Gradle plugin
and the endpoint injected by runner dispatch. It rejects any endpoint outside
the `ovh-gra-runners` private service, disables Gradle's local build cache,
uploads a unique cacheable task output, deletes the output, and requires the
second build to report `FROM-CACHE` with identical contents. Gradle logs are
retained as the `linux-runner-kura-smoke` workflow artifact.

This verifies application routing and remote cache reuse. Pair it with captures
on the runner and cache hosts during the job to establish that the physical
traffic crosses vRack; a passing job alone does not establish the underlay.

### Host network verification

On a runner and the cache host, inspect `systemctl status tuist-vrack.timer`,
`journalctl -u tuist-vrack.service`, `/etc/tuist/vrack-peers`, and
`ip -4 route show proto 242`. Run `ip route get <other-node-public-ip>` in both
directions: it must select the private NIC and the other host's reserved private
next hop, retaining the public Node source address. Verify that the ordinary
default route is unchanged.

From a disposable Linux Kata runner pod, issue a cache request to the private
instance's Service URL. Capture `udp port 8472` on the runner and cache private
NICs and confirm that the request and response actually traverse them. Also
check that the same request does not traverse the public NICs. This packet check
is required: a Linux route listing alone is not proof of Cilium's effective BPF
forwarding path. If it fails, keep the region unadvertised and diagnose the Cilium
device/forwarding configuration before activation.

Use a temporary `iperf3` listener bound to the cache's **private** address to
measure each runner's private link and simultaneous runners' aggregate traffic.
Then compare cold and warm Kura restores of the same artifact set, including
concurrent jobs. The per-account 750 Mbit/s cap still bounds a single account;
raise it only against measured private capacity and concurrent-account headroom.
Remove the temporary listener when finished.

## Recovery and rollback

- Remove `ovh-gra-runners` from the available-region list to stop dispatching new
  jobs to it; the existing public-region Service fallback takes over. Do not tear
  down instances that in-flight jobs still use.
- To disable private routing on a host, stop/disable `tuist-vrack.timer` and
  `tuist-vrack.service`, then remove only its `proto 242` routes. This restores
  the existing public underlay. Coordinate this with the desired machine
  configuration so a future repair does not reinstall the routes.
- Do not clear `vRackID` on an addressed live Machine: the controller reports a
  configuration error rather than silently abandoning installed routes. Restore
  the original configuration or replace the Machine through the normal drain
  path. vRack attachments remain on release; the OS reinstall removes host
  addresses and routes, and re-adoption can reuse the already-attached NIC.
