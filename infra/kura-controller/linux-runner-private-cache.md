# Linux runners: reuse regional Kura over OVH vRack

Linux runners use each account's existing regional Kura instance and internal
Service. This change lets compatible OVH runner hosts reach those instances
over the environment's vRack. It adds no Linux-specific cache region,
provisioning lifecycle or readiness probe. The default-off account flag
`runner_linux_vrack` selects isolated runner pools on enrolled hosts. Existing
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

### Account feature flag

`runner_linux_vrack` defaults off in **every environment**, including staging
and canary, and is registered in the audited Ops flag catalog. Enable only the
Tuist account actor initially; do not create a global or percentage enrollment.
This is a new flag, deliberately independent of the retired experiment's flag.

The flag is evaluated when resolving a new Linux job's target pool. With the
flag off, dispatch keeps the ordinary pool. With it on and a Helm-declared
mapping present, dispatch uses the corresponding `-vrack-` pool with identical
CPU/memory/image. The same path is used by GitHub, GitLab and Buildkite profile
dispatch. Explicit legacy pools without a mapped counterpart remain unchanged;
internal vRack labels cannot be selected directly to bypass the account gate.
macOS routing is unchanged. No endpoint is removed from unflagged runs: both
cohorts retain the ordinary regional Kura Service.

`runnersFleetLinux.vrack.enabled` prepares the pools and server mapping; it
never enables any account. Shared managed values enable this preparation in
staging, canary and production through their normal deployments; self-hosted
installs default off. No environment-specific preparation overlay is needed.
The new pools have a zero warm floor and a different
`fleetSelector` (`runners-linux-vrack`). The existing cache-volume agent covers
both cohorts. Capacity accounting uses the existing controller's per-fleet
selection, with the same per-job resource reservation in both cohorts.

**Host separation is a prerequisite.** Ordinary pools must contain only
unenrolled hosts; vRack pools must contain only enrolled, qualified hosts.
Host routes affect every job on that host. Do not enroll an ordinary fleet or
merely gate the cache URL: that would expose unflagged runs too. Move drained
hosts through a reviewed CAPI ownership/label transition preserving their
physical identity. Cordon first, let the controller reap idle pollers and let
claimed jobs finish; require zero nonterminal runner Pods before changing
cohort labels or routes. Cordon alone does not stop an already-running poller.
The MachineDeployment/MachineSet, Machine and live Node
must agree on cohort membership across reconciliation. A one-off Node relabel
that CAPI can overwrite is not isolation. Do not delete/reinstall a live
Machine as a shortcut. Keep enough healthy ordinary capacity for other accounts.

Staging and canary target **one RISE-M each** to limit cost. One physical host
cannot serve both isolated cohorts concurrently. Qualify the ordinary path,
drain all jobs and pollers, then move that host's persistent CAPI membership
and network configuration to the vRack cohort for enrolled-account tests.
Restore the ordinary cohort after draining the vRack tests. Excluded-account
jobs must never fall through to the enrolled host; they will queue while
ordinary capacity is absent. Schedule these as controlled non-production
maintenance windows. Production keeps separate capacity for simultaneous
enrolled and excluded-account validation. The account flag alone does not
switch a host's cohort or routes.

To roll back account exposure, disable the flag for the Tuist actor and verify
new jobs select ordinary pools. No active job is migrated and no cache is
deleted; already-queued jobs may still use their recorded vRack pool. Keep the
cohort, mapping and routes until those jobs finish. Flag propagation uses the
existing bounded FunWithFlags cache/pubsub behavior, not instantaneous global
invalidation. Inspect effective flags and actual dispatched fleet names when
validating disablement. A global false alone does not override actor enables.

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
5. Before enrollment, separate the existing vRack-enrolled RISE-M from ordinary
   runner scheduling as described above. The ordinary fleet template intentionally
   has no vRack ID, so future ordinary hosts stay unenrolled. Require usable
   ordinary capacity for concurrent tests, or use the sequential single-host
   procedure above. Run fresh regional smoke jobs for both the enrolled account
   and an excluded account, verifying their actual runner Nodes and network
   paths. The legacy RISE-S fixtures were moved to the existing Gravelines
   cache host on 2026-10-26; staging now targets one RISE-M. Preserve that
   prepared runner and account for its existing `pn-2023588` enrollment before
   allowing ordinary jobs onto it.

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

## Historical validation

[PR #14766](https://github.com/tuist/tuist/pull/14766) records the Gradle and
HTTP latency measurements, methodology, workflow links and limitations from
the earlier dedicated-instance experiment. Those results compare Gravelines
with Canada over vRack; they do not qualify the final regional-instance reuse,
account isolation or rollback. Production already has caches in Gravelines.
Fresh validation after the staging transition remains required. Keep new run
outputs in workflow artifacts and report their results in the PR.

## Production rollout and rollback

Refresh the production inventory and load before selecting hosts. The
inventory recorded in PR #14766 found ten RISE-L runners and six existing
ADVANCE cache hosts in Gravelines; that historical snapshot does not establish
current capacity or peak/disk/host-loss headroom. Keep the existing regional
instances and local volumes. Do not create another logical region on the same
pool: region-specific storage reservation accounting would give it a second
budget.

1. Complete staging qualification, then review/merge and deploy the provider
   through the normal main-branch pipeline. Preserve unrelated runtime pins.
2. Record the production account's existing EU-West Service, instance ID,
   backend Node, public-client health and cache performance before enrollment.
3. Obtain human production write elevation, cordon one selected runner, and let
   its jobs finish without eviction. Move it into the managed isolated CAPI
   cohort, with persistent matching Machine/Node labels, before enrolling that
   idle Machine into `pn-2024093`, using the environment's existing `172.30.243.0/24` allocation.
   Wait for KataRuntimeReady, PrivateNetworkReady and reciprocal-route
   convergence. Keep it cordoned if qualification fails.
4. Enable `runner_linux_vrack` only for the Tuist account. Run controlled jobs
   on that host plus excluded-account jobs on ordinary unenrolled hosts,
   comparing the same cache instance with the
   baseline and an unenrolled control. Require matching restored outputs,
   verified private transport, no public-client regression and adequate shared
   cache headroom before expanding account enrollment or cohort capacity.
   Preserve healthy ordinary hosts for accounts that remain off.

The shared managed configuration prepares isolated shape pools and their
dispatch mapping in all three environments. It adds no physical hosts, cache
instances or storage. It does not set vRack on the ordinary fleet template
and does not enroll accounts. The account flag remains off by default.
Enable the account flag only after the selected cohort's private route has
been qualified; leave all other accounts off.

After disabling the account flag and verifying new dispatch, network
rollback starts by stopping new jobs on the affected host and allowing current
jobs to finish. Restore the reviewed previous network state while preserving
reservations/peer guards until convergence; clearing `vRackID` alone does not
remove installed routes safely. Existing public Kura instances keep serving.
The [cluster access rules](../AGENTS.md#cluster-access-for-agents) require a human
to initiate and approve production JIT elevation.

Canary's current SYS-1 cache is in Canada. Its runner was replaced on
2026-10-26 with the user-ordered Gravelines RISE-M `ns3127017.ip-51-68-34.eu`
(`gra2`, IP `51.68.34.106`, 64 GB RAM, 2 × 512 GB NVMe, 1 Gbps private/public).
The minimal template change [#14796](https://github.com/tuist/tuist/pull/14796)
deployed through the normal main pipeline before the human-elevated cutover;
the fleet remains one replica with OnDelete. After verifying no local PVs,
cordoning the old Node, and waiting for every runner to finish or be reaped,
the old Machine was deleted through CAPI. Its provider released
`ns3269803.ip-37-187-149.eu` and submitted the normal clean reinstall. Its
Machine, OVHDedicatedMachine and Node are gone. The user subsequently confirmed
cancellation of its OVH contract.

The replacement Node `tuist-tuist-ovh-fleet-runners-linux-gnbmk-jgl25` reached
NodeReady and KataRuntimeReady, with XFS project-quota accounting/enforcement
enabled and healthy RAID1 root, boot and data arrays. Three Kata runners warmed.
A fresh [Linux acceptance job](https://github.com/tuist/tuist/actions/runs/40411336722/job/121882539963)
ran on that Node and passed dispatch, file limits, OIDC authentication and a
byte-matching 1 MiB CAS write/read through the existing Canadian Kura endpoint.
PR #14766 records the runner identity, host checks and qualification limits.

This qualified the ordinary runner path only. The final account-gated feature
refactor has not been deployed or live-qualified by this hardware replacement.
The new host has no `vRackID`; leave `runner_linux_vrack` off until its isolated
cohort and private transport are qualified. An enabled flag with no eligible
hosts would leave jobs queued. No second runner or dedicated cache-host order
is required for the single-host sequential qualification plan.
Do not bridge environments to simulate the topology. Configuration parity is
not live transport validation: each environment still needs enrolled/excluded-
account runs and path verification, sequentially with a single runner host.

## Staging fixture preservation, 2026-10-26

Before retiring `ns340020.ip-37-187-143.eu`, both remaining fixture replicas
were moved from the RISE-S to the existing Gravelines cache host:

- `kura-spec98/kura-matrix-oct22d`: planned handover verified 316,078 retained
  records, revoked the old writer, and moved serving authority to ordinal 0.
  Supported replica recovery rebuilt ordinal 1 on Gravelines and reached
  `Verified`; both replicas are Ready with initial backfill complete. A fresh
  synthetic PUT returned 204 and GET returned 200 with the expected value.
- `kura-spec98/kura-handover-oct9`: its standby exited cleanly, then its 32 MB
  volume was copied cold within staging. All 22 file checksums matched before
  restarting ordinal 1 on Gravelines with its existing `0.58.0-canary.13`
  runtime. Both replicas are Ready. The pre-existing expired epoch-3 `Fencing`
  grant remains unchanged; this migration does not repair that fixture's
  unavailable serving authority or reset its durable floor. The instance's
  template and fenced image pin now match that standby runtime; OnDelete
  preserves ordinal 0's existing runtime.

The original matrix and handover volumes, plus an older released quarantine
from `kura-spec98-final-1`, have checksum-verified archives on the Gravelines
cache host in PVC `kura-spec98/rise-s-migrate-matrix-oct22d` (PV reclaim policy
`Retain`). `rise-s-retirement-backups` in that namespace records the archive
names and SHA-256 hashes. Preserve these archives until explicitly cleaned up;
the quarantined archive retains its unclean-primary marker and is not a volume
to start as a writer. Temporary copy pods, their NetworkPolicy and the pod
finalizer used during the cold move were removed. Host release wipes local
disks, so the retained archives are the preservation copies after retirement.
Removing the Machine does not cancel the OVH monthly contract.
