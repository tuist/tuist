# Linux runners: reuse regional Kura over OVH vRack

Linux runners use each account's existing regional Kura instance and internal
Service. This change lets compatible OVH runner hosts reach those instances
over the environment's vRack. It adds no Linux-specific cache region,
provisioning lifecycle, readiness probe, or account feature flag. Existing
macOS private-cache behavior is unchanged. Additional cache-host orders are
on hold.

## Selection and network control

`Kura.runner_cache_endpoint_url/3` already selects the account's active managed
EU-West instance for Linux, falling back to another active managed region when
EU-West is absent, or no override when no instance is available. The internal
URL addresses the same instance used by public clients, including its `-m`
Service after a move. Reuse preserves its storage accounting, contents, tenant
authorization and public endpoint. It does not create another account cache.
Do not assume every account has a Gravelines-local cache: verify its selected
Service and backing pods. Selection is not generalized to arbitrary runner
geographies by this PR; it retains the existing EU-West preference.

The provider enrolls Kata runner hosts only when
`OVHDedicatedMachine.spec.vRackID` is explicitly set and matches the environment's
private-network ConfigMap. Existing cache hosts remain participants. Enrolled
runners receive address reservations and reciprocal peer routes; legacy hosts
without a private NIC stay unenrolled. The Helm fleet template now exposes this
field. Existing OnDelete Machines require explicit enrollment; changing their
template does not update their specs.

This is a host-level opt-in. Eligible OVH traffic from every account on an
enrolled host takes the private routes. No account feature flag controls the
underlay. Qualify a controlled host before admitting normal jobs, then roll out
one host at a time. Do not represent the former dedicated-cache flag as a
network kill switch.

## Staging migration required before deploying this revision

The deployed staging experiment still uses the previous private Linux region.
Removing its catalog entry before retiring its instances can leave active
unknown-region rows eligible for public selection. Complete the following
transition using the previously deployed server before deploying the refactor:

1. Inventory the old `ovh-gra-runners` account rows, KuraInstances, Services,
   pods and claims, and jobs retaining their URLs. On the old release, remove
   all enrollments of `kura_linux_runner_cache` and ensure it evaluates false
   for every affected account. A global false rule alone does not override
   actor/percentage rules. Confirm new jobs use an ordinary regional Service.
2. Keep the old region available to reconciliation while its instances drain.
   Wait for every job retaining its URL to finish and for the normal lifecycle
   to remove serving instances. The previous implementation has a 15-minute
   minimum drain and up to six hours of job protection; verify state, rather
   than assuming a timer alone proves completion. Require zero non-destroyed
   old-region rows and no old-region serving CRs/pods/Services before proceeding.
   Do not relabel a live private instance into EU-West or rewrite its region
   in SQL. Retired local volumes follow the existing storage cleanup process.
3. Reuse the already prepared Gravelines RISE-1 as ordinary EU-West capacity.
   Keep its `gra-runners-cache` fleet resource name and OVH adoption prefix to
   avoid deleting/recreating the Machine or reinstalling the host. The name is
   historical; its target pool is now the existing `kura-dedibox` EU-West pool.
   After the old workloads drain, update the owning Machine/pool labels and
   live Node label consistently with the reviewed OnDelete template; confirm
   CAPI retains them. Do not delete the Machine to force a label change.
   Check local storage, egress capacity, EU-West ingress and public DNS/TLS,
   private membership, reciprocal routes and the controller's capacity view.
4. Deploy the refactored configuration only after those checks. Staging then
   advertises `scw-fr-par-runners,eu-west,ca-east`; no Linux private region is
   available. Let ordinary regional placement/activation create or reuse the
   test account's EU-West instance. Confirm both public and internal endpoints
   address that same instance. The Canadian fleet remains available as the
   controlled remote baseline. Remove the obsolete stored flag after no old
   server replica depends on it.
5. Run fresh regional-cache smoke/benchmark jobs below. Keep the RISE-S runner
   cordoned until its unrelated retained fixtures are resolved; this refactor
   does not retire it. Preserve the prepared RISE-M runner and its existing
   `pn-2023588` enrollment.

This revision prepares configuration and code, not an automatic data migration.
No live instance, Machine, volume, flag or OVH contract is changed by editing
these files. Do not deploy over the live experiment without completing the
transition. The staging cache's two replicas share one host; this is not a
host-failure availability qualification.

## Qualification with the existing instance

The manual `linux-runners-staging-smoke.yml` workflow uses normal runner dispatch
and OIDC authentication. Set `gradle_cache=true` and choose the staging profile.
`compile_project=true` requires an injected EU-West Service, compiles actual
Gradle-plugin production/test Kotlin sources with fresh inputs, deletes outputs,
and verifies both tasks restore remotely with identical class checksums.

`compare_regional_cache=true` runs `gradle-regional-benchmark.sh`: five alternating
cold/restore pairs for each of 1 MiB and 64 MiB, with local caching disabled and
checksum verification. Dispatch must inject the existing EU-West Service;
`wan_cache_endpoint` selects the independent remote baseline. A benchmark
endpoint override is not evidence that dispatch automatically selected it.

`measure_request_latency=true` runs health, authenticated HEAD hit/miss and
1 KiB GET probes, each with ten warmups and 100 alternating samples per endpoint
for persistent and fresh HTTP/1.1 connections. Status, metadata, returned bytes
and socket reuse are checked. Credentials stay outside artifacts. `hold_seconds`
(0–900) pauses the simple smoke between upload and restore for cache restart
drills. It does not qualify removing network routes while a job is running.

The CSV labels `pn` and `wan` are retained for comparison with historical data;
Service names do not prove the physical path. Capture both public and private
NICs at runner and cache, check full-MTU reachability and reciprocal-route
attestations, and correlate the actual selected Service with its backend Node.
For before/after host enrollment, use the same account, instance and workload
on an unenrolled and an enrolled runner; retain the instance identity in the
measurement record. Confirm no extra Kura instances/volumes appear. Include
concurrent builds and monitor errors, p95, queueing, CPU, memory, disk and link
pressure. Test public-client access throughout because it shares the instance.

## Historical measurements, not validation of the final topology

[Recorded evidence and methodology](validation/linux-runner-pn-2026-10-26/README.md)
preserve the earlier dedicated-instance experiment. Forty Gradle invocations
passed, including twenty remote hits with matching checksums:

| Payload | Operation | Canadian WAN median | Nearby PN median | Paired speedup |
| --- | --- | --- | --- | --- |
| 1 MiB | Cold upload | 1.317 s | 0.570 s | 2.32× |
| 1 MiB | Remote restore | 1.110 s | 0.531 s | 2.13× |
| 64 MiB | Cold upload | 6.074 s | 3.729 s | 1.63× |
| 64 MiB | Remote restore | 4.963 s | 2.765 s | 1.80× |

Persistent metadata-hit p50/p95 was **79.541/79.897 ms WAN** versus
**0.854/1.439 ms PN**; all 1,600 measured HTTP requests passed. Fresh connections
included roughly 57 ms of hostname lookup on both paths. Packet captures
confirmed vRack on both sides; the Canadian endpoint still crossed the Atlantic.

Those results used the removed dedicated instance, with 750 Mbps configured
egress versus the Canadian cache's 500 Mbps. They do not isolate latency from
bandwidth, hardware or storage. Production's existing cache is already in
Gravelines: neither the speedups nor the former flag rollback drills establish
performance or rollback for the final reuse approach. New live validation after
the staging transition remains required.

## Production rollout and rollback

The [recorded inventory](validation/linux-runner-pn-2026-10-26/production-network-inventory.json)
identified ten RISE-L runners in Gravelines (1 Gbps private/public, no OLA)
and six existing ADVANCE cache hosts (25 Gbps private / 3 Gbps public) on
`kura-dedibox`. Cache-host CPU was 1–3% and memory 14–32% in a read-only snapshot;
that does not establish peak/disk/host-loss capacity. Keep the existing instances
and local volumes. Do not create another logical region on the same pool:
region-specific storage reservation accounting would give it a second budget.

1. Complete staging qualification, then review/merge and deploy the provider
   through the normal main-branch pipeline. Preserve unrelated runtime pins.
2. Record the production account's existing EU-West Service, instance ID,
   backend Node, public-client health and cache performance before enrollment.
3. Obtain human production write elevation, cordon one selected runner, and let
   its jobs finish without eviction. Enroll only that idle Machine into
   `pn-2024093`, using the environment's existing `172.30.243.0/24` allocation.
   Wait for KataRuntimeReady, PrivateNetworkReady and reciprocal-route
   convergence. Keep it cordoned if qualification fails.
4. Run controlled jobs on that host, comparing the same instance with the
   baseline and an unenrolled control. Require matching restored outputs,
   verified private transport, no public-client regression and adequate shared
   cache headroom before admitting normal jobs. Enroll remaining hosts serially.

The optional [production overlay](production-linux-runner-vrack.values.yaml)
sets only runner-template `vRackID`. It is outside default production values
and adds no hosts, cache instances, replicas or volumes. Production remains
unchanged until the normal deployment and explicit Machine enrollment.

Rollback starts by stopping new jobs on the affected host and allowing current
jobs to finish. Restore the reviewed previous network state while preserving
reservations/peer guards until convergence; clearing `vRackID` alone does not
remove installed routes safely. Existing public Kura instances keep serving.
The [cluster access rules](../AGENTS.md#cluster-access-for-agents) require a human
to initiate and approve production JIT elevation.

Canary's current SYS-1 cache is in Canada and its Gravelines RISE-S runner lacks
vRack. Preserve that configuration while evaluating compatible spare capacity;
no new order is planned. Do not bridge environments to simulate the topology.
