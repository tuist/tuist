# Linux runner cache in OVH Gravelines

`ovh-gra-runners` is a private, Linux-only region on the
`kura-ovh-gra-runners` pool. Account caches use the managed two-replica lifecycle,
local XFS storage, and a 750 Mbps egress setting. The replicas share the
staging cache host, so staging does not demonstrate host redundancy.

Runner dispatch prefers the active private instance's cluster Service while its
readiness observation is fresh, and falls back to the account's public-region
Service when the heartbeat expires or the account is disabled.
Availability requires both `TUIST_KURA_AVAILABLE_REGIONS` and the default-off
account flag `kura_linux_runner_cache` in every environment. Enable it only after
both runner and cache hosts have converged and their physical path is verified.

OVH Kata hosts opt into the existing environment private-network reconciler
through `machine.vRackID`. This must match `capi.ovhPrivateNetwork.vrackID`.
The legacy RISE-S staging runner has no private NIC and must not be enrolled.
Address reservations, reciprocal routes, failure guards and membership
attestations use the existing managed private-network machinery.

## Staging rollout

1. Verify the prepared RISE-M runner and RISE-1 cache accept their fleet SSH
   keys and have healthy mirrored system and XFS data volumes.
2. Deploy the updated provider before enrolling the runner. Bring up the cache
   fleet and add the RISE-M runner alongside the legacy host. `OnDelete` keeps
   the old Machine until explicit retirement.
   Apply the template before scaling: an in-place template edit and a scale-up
   in one Helm upgrade can race, cloning the old offer into a new Machine.
   If this happens, verify the Machine has no adopted service before aligning
   its offer and vRack enrollment with the new template.
3. Wait for Ready, KataRuntimeReady and PrivateNetworkReady. Verify physical
   VXLAN traffic on both private NICs with no matching traffic on public NICs.
   The runner cache-volume agent also needs its separate bounded filesystem.
   Staging enables the existing 200 GB provisioning init container. For a host
   that already accepted jobs before provisioning was enabled, cordon it, let
   jobs finish, and move only confirmed-unused fallback directories aside
   before running the guarded provisioner. Uncordon after the agent is ready.
4. Move staging runner jobs to the new host before enabling `ovh-gra-runners`.
   Drain existing jobs normally. Verify account reconciliation and injected
   endpoint selection using a real GitHub Actions job.
5. Compare cold uploads and remote restores on the same runner against the
   colocated cache and the existing remote public-region cache. Disable local
   Gradle caching, prewarm dependency downloads and the daemon, alternate order,
   use fresh keys, verify every remote hit and restored payload checksum, and
   retain raw logs. Record the actual network path and endpoints; a cluster
   Service URL alone does not establish a physical private path.

Normal rollback disables `kura_linux_runner_cache` for enrolled accounts so new
jobs use the existing public-region fallback and the reconciler drains PN
instances. Keep the region available while it drains. Removing the region from
available regions also stops hand-out, but stops its reconciliation too and
therefore is not the normal cleanup path. Preserve in-flight jobs and instances.
Do not clear the runner's vRack enrollment or recycle reservations while the
host still owns private routes. Production activation requires its own capacity
and path qualification; this change does not enable the region there.

## Account rollout and validation gates

The flag is included in the audited Ops catalog and defaults off on staging,
canary and production, independently of the existing runners flag. It gates
both admission/provisioning and endpoint selection; an already-active private
cache cannot bypass an account opt-out. Recent Linux jobs, eligible profiles,
capacity and environment availability remain required. Existing macOS caches
retain their current admission and dispatch rules.

Disabling an account removes PN selection for subsequent dispatches once flag
invalidation reaches the serving replica. The reconciler moves active PN caches
to drain-pending. Running jobs keep their injected endpoint; the instance stays
for at least 15 minutes and while pre-drain jobs remain claimed/running, subject
to the existing six-hour bound. Re-enabling before teardown cancels the drain on
the same instance. This is not mid-job failover: a failed endpoint already
injected into a job is not dynamically replaced by the flag.

Use explicit account cohorts initially. For a complete rollback through the
Ops interface, clear all gates for this default-off flag, or explicitly disable
each enrolled actor. A global boolean disable alone preserves actor and
percentage enables. PubSub invalidation is best effort; cached evaluations can
last 600 seconds and storage failures can retain stale values. Verify actual
endpoint selection on every serving replica rather than treating a successful
flag write as proof of exposure.

Before production enrollment:

1. Deploy the flag-bearing server revision to staging and enable only the Tuist
   test account. Keep another account excluded and verify it gets WAN without
   provisioning a PN instance.
2. Run a real PN Gradle job, disable its account flag while it is in flight,
   and verify a new job receives WAN while the old one can still restore from
   PN. Confirm drain retention, then re-enable and verify the same instance is
   reused. Exercise completed-job cleanup with a disposable account.
3. Exercise a single cache-pod restart and verify remote hits and Service
   readiness. Separately qualify a complete endpoint outage and the time until
   new dispatch stops selecting it; do not assume transparent mid-job failover.
4. Run simultaneous Gradle jobs plus a representative real Gradle project.
   Observe cache errors, hit rate, request p95, queueing, CPU, disk and link
   usage. The synthetic single-job results below do not establish concurrency
   capacity. Investigate the measured 57 ms hostname-lookup cost separately.
5. Prepare production vRack-capable runner/cache hosts, release/pin the tested
   provider, and qualify private routing and actual negotiated/contracted link
   speeds. Two replicas on the same staging cache host do not prove host
   redundancy; production placement and host-loss behavior need qualification.

Production sequence: deploy code with the flag absent, provision and qualify
capacity, make the region available, then enroll Tuist's account. Start with
one internal account, then a few explicit customer accounts, then broaden.
A proposed minimum observation window per expansion is 24 hours and 50 finished
jobs, whichever takes longer, against a recorded WAN baseline. Require correct
endpoint/account selection, zero payload/authentication regressions, no cache
error-rate regression, better request p95 and sufficient disk/link/CPU headroom.
Preserve a WAN control cohort. Deterministic percentage-of-actors rollout can
follow explicit cohorts; percentage-of-time is unsuitable for provisioning.
Only enable globally after those gates pass; retain the flag for rollback.

Validation status: after merging main, 304 focused tests passed across feature
helpers, Ops evaluation, regions, admission/draining, endpoint selection and
placement. The subsequent readiness fix passed 206 tests across Kura, runner
cache and reconciler suites. These overlapping runs are not added together.
Live outcomes and outstanding gates are recorded below.

## Staging qualification — 2026-10-26

The [application deployment](https://github.com/tuist/tuist/actions/runs/40324015686)
and [final chart deployment](https://github.com/tuist/tuist/actions/runs/40327447163)
completed successfully. The latter deploys chart revision `2f060b164e1`, server
and Kura runtime `sha-eea9626bab67`, and CAPI provider `59c4a6d2`.
The [baseline smoke](https://github.com/tuist/tuist/actions/runs/40325867171)
used the existing Canadian cache. The
[controlled comparison](https://github.com/tuist/tuist/actions/runs/40327404453)
verified automatic PN endpoint injection and passed all 40 measured builds,
including 20 remote restores and payload checksum checks.
The [post-deployment smoke](https://github.com/tuist/tuist/actions/runs/40328261140)
also passed with the injected PN endpoint after the final chart rollout.

### Measured before/after

“Before” is the existing remote Canadian cache selected explicitly on the same
new runner; “after” is the new nearby Gravelines PN cache. Both use the same
Kura runtime and Gradle protocol. Both paths now traverse OVH vRack: the
Canadian baseline crosses the transatlantic WAN. These measurements do not
compare public-internet transit with private transit, or the old runner CPU
with the new runner CPU.

| Payload | Phase | WAN wall median (range) | PN wall median (range) | Paired wall speedup | WAN / PN task medians |
| --- | --- | --- | --- | --- | --- |
| 1 MiB | Cold upload | 1.317 s (1.286–1.972) | 0.570 s (0.549–0.740) | 2.32× | 0.808 / 0.084 s |
| 1 MiB | Remote restore | 1.110 s (1.053–1.202) | 0.531 s (0.506–0.560) | 2.13× | 0.615 / 0.039 s |
| 64 MiB | Cold upload | 6.074 s (5.978–6.239) | 3.729 s (3.556–3.857) | 1.63× | 5.420 / 3.194 s |
| 64 MiB | Remote restore | 4.963 s (4.636–5.214) | 2.765 s (2.501–2.805) | 1.80× | 4.376 / 2.243 s |

Wall time includes the full Gradle invocation, including task execution or
restore, archive work and plugin reporting. Task time is measured around
Gradle's task execution callbacks; it includes cache handling and file I/O.
Paired speedup is the median of five WAN/PN ratios matched by round, which can
differ slightly from the ratio of the two medians. These are synthetic cache
operations, not an Android application's compile-time speedup.

### Method and environment

- One GitHub Actions Docker job on a Kata runner, 2 vCPU / 8 GiB, image
  `ghcr.io/tuist/tuist-linux-runner:0.25.0`; Temurin 21.0.12.1, Gradle 9.2.1,
  released Tuist plugin 0.10.0.
- Five cold/upload and warm/restore pairs per endpoint and payload size.
  Endpoint order alternates each round. Plugin/dependency downloads and the
  shared Gradle daemon are warmed before timing; configuration caching and the
  local build cache are disabled. Outputs are deleted before every invocation.
- Fresh keys per endpoint/size/round prevent earlier runs and mesh replication
  from turning the cold measurement into a hit. Deterministic random payloads
  are incompressible; every restored payload has the same SHA-256 as its cold
  output, including across endpoints. The 64 MiB case stays under Kura's
  100 MiB Gradle artifact limit including archive overhead.
- PN endpoint: `http://kura-tuist-ovh-gra-runners.kura.svc.cluster.local:4000`.
  Remote baseline: `http://kura-tuist-ca-east-1.kura.svc.cluster.local:4000`.
- Each cache has two replicas, an 8 GiB volume per replica for this account,
  1 CPU ceiling, and 256/768 MiB memory floor/ceiling. Actual configured egress
  ceilings differ: PN 750 Mbps, Canadian baseline 500 Mbps. The experiment
  compares deployed configurations; it does not isolate latency from bandwidth,
  hardware, storage, page-cache warmth or background mesh activity.
- Runner: RISE-M `ns3066567.ip-193-70-46.eu` in gra1.
  Nearby cache: RISE-1 `ns3220989.ip-162-19-86.eu` in gra3.
  Baseline cache: `ns543284.ip-144-217-252.net` in Canada.
  The Gravelines pair has 1 Gbps contracted vRack links.

### Direct HTTP request latency

The request probe isolates small HTTP operations from Gradle startup, archive
handling and bulk transfer. It uses the same injected PN Service and explicit
Canadian baseline as the Gradle comparison, from a fresh 2-vCPU/8-GiB staging
Linux runner. Both caches still run `kura:sha-eea9626bab67`.

For each endpoint, request type and connection mode, ten warm-ups precede 100
recorded samples, alternating endpoint order. The 1,600 measured requests are
serial and use HTTP/1.1 without TLS. Persistent samples must reuse their socket;
fresh samples must open a new connection. Timing spans request creation through
response completion. Median averages the middle two samples; p95 is the
nearest-rank 95th sample. Raw data also retain time to response headers and
lookup/connect milestones.

- Health is unauthenticated `GET /up`.
- Metadata hits are authenticated `HEAD /api/cache/gradle/<key>` requests,
  checking status 200, ETag, Content-Length and an empty response body.
- Metadata misses use a separate absent key and require status 404 and no body.
- Tiny reads request a seeded 1 KiB artifact and compare the full returned bytes.

Each endpoint gets a unique seeded key. The probe resolves the workflow's OIDC
credential in memory; neither credentials nor authorization headers enter the
artifacts. These are warmed key/authentication paths, including repeated misses,
not cold metadata/storage lookups. Persistent connections sample whichever
replica accepts that connection; fresh connections can select other replicas.
The Node client timings do not measure Gradle's own connection-pool behavior.
This is a low-load latency sample, not a concurrency or saturation test, and
contains no TLS handshake cost. Both physical paths use vRack; the baseline
still crosses the Atlantic.

[Successful phase-instrumented run](https://github.com/tuist/tuist/actions/runs/40333263154):
**1,600 measured requests passed**, including all status, metadata, payload and
connection-reuse checks. The earlier
[unsegmented run](https://github.com/tuist/tuist/actions/runs/40332566153) also
passed all 1,600 requests and showed comparable latency (metadata-hit medians
0.825 ms PN / 79.527 ms WAN). The table uses only the phase-instrumented run;
it does not pool the two runs.

| Connection | Request | WAN p50 / p95 | PN p50 / p95 |
| --- | --- | --- | --- |
| persistent | health | 79.366 / 79.676 ms | 0.837 / 1.293 ms |
| persistent | metadata_hit | 79.541 / 79.897 ms | 0.854 / 1.439 ms |
| persistent | metadata_miss | 79.481 / 79.717 ms | 0.870 / 1.373 ms |
| persistent | read_1k | 79.825 / 80.169 ms | 1.041 / 1.642 ms |
| fresh | health | 214.956 / 218.423 ms | 58.742 / 60.498 ms |
| fresh | metadata_hit | 215.267 / 218.679 ms | 58.981 / 60.777 ms |
| fresh | metadata_miss | 215.252 / 218.465 ms | 58.828 / 60.140 ms |
| fresh | read_1k | 215.060 / 218.607 ms | 59.098 / 60.619 ms |

| Fresh-connection phase | WAN median | PN median |
| --- | --- | --- |
| lookup | 57.169 ms | 57.180 ms |
| tcp | 78.609 ms | 0.666 ms |
| response | 79.421 ms | 1.110 ms |

Fresh-connection phases pool the four request types (400 samples per endpoint).
Lookup is elapsed time from request creation until Node's hostname-lookup event,
TCP is lookup completion to connect, and response is connect to body completion.
Phase medians need not sum to the median of a particular request type.
The roughly 57 ms hostname-lookup phase is shared by both paths and dominates
fresh PN requests. Its resolver-level cause is not diagnosed here. Reusing a
connection avoids that phase. With reused connections, PN metadata hits take
0.854 ms median versus 79.541 ms on WAN (about 93× faster). These findings support investigating runner DNS
latency separately, not attributing the fresh-request delay to Kura processing.

Raw [requests](validation/linux-runner-pn-2026-10-26/requests.csv) and
[request environment](validation/linux-runner-pn-2026-10-26/request-environment.json)
are checked in; the workflow retains them in its `kura-request-latency` artifact.
Reproduce both tables with:

```sh
node infra/linux-runner-image/summarize-kura-request-latency.mjs \
  infra/kura-controller/validation/linux-runner-pn-2026-10-26/requests.csv
```

For a live rerun, dispatch `linux-runners-staging-smoke.yml` with
`gradle_cache=true` and `measure_request_latency=true`; leave
`compare_private_cache` and `stable_cache_dns` disabled.
The first probe attempt stopped before measuring because the shared workflow's
empty optional `TUIST_TOKEN` shadowed its valid OIDC credential. The probe now
omits that empty override when asking the CLI to resolve the credential. That
failed attempt contributes no samples.

### Physical path evidence

The runner and both OVH cache Machines reported `PrivateNetworkReady=True`.
The controller reserved `172.30.241.4` for the runner and retained cache
addresses `.2` (Gravelines) and `.3` (Canada) on `pn-2023588`.
Reciprocal public-node /32 routes use these private next hops; unreachable
fallback guards remain installed. Ten underlay pings had zero loss and averaged
**0.425 ms nearby versus 79.469 ms to Canada**.

During the Gradle comparison, bounded 55-second header-only captures observed
308,180 VXLAN packets on runner `enp7s0` and 402,728 on cache `enp3s0f1`,
with **zero matching packets on public NICs `enp6s0` / `enp3s0f0`**.
Capture windows began three seconds apart, so totals are not intended to match.
Both directions are visible and neither capture reported kernel drops.
This establishes the path during this run, not sustained link saturation or
failover behavior under injected network faults.

### Evidence and operational state

Raw [results](validation/linux-runner-pn-2026-10-26/results.csv),
[environment](validation/linux-runner-pn-2026-10-26/environment.txt),
[runner capture](validation/linux-runner-pn-2026-10-26/runner-packets.txt),
[cache capture](validation/linux-runner-pn-2026-10-26/cache-packets.txt), and
[latency samples](validation/linux-runner-pn-2026-10-26/latency.txt) are checked in.
All 40 Gradle logs are retained in the comparison run's
`gradle-pn-benchmark-logs` artifact. Reproduce the table with:

```sh
node infra/linux-runner-image/summarize-gradle-pn-benchmark.mjs \
  infra/kura-controller/validation/linux-runner-pn-2026-10-26/results.csv
```

The legacy RISE-S Machine remains allocated and cordoned because unrelated
`kura-spec98` fixtures still run there. The two-Machine replica count is
transitional. Do not uncordon the legacy host while PN dispatch is enabled;
move those fixtures before explicitly retiring it and reducing replicas to one.
No OVH contract was terminated. Production does not enable this region.

Both cache replicas share one staging host, so this proves neither cache-host
redundancy nor production throughput. Production needs its own vRack-capable
runner/cache capacity, provider release and physical-path qualification.

The initial benchmark attempt used 128 MiB and correctly failed when the remote
cache rejected an artifact above its 100 MiB limit. Those incomplete samples
are excluded. Its Docker artifact-path issue was corrected before the complete
1/64 MiB run. The first deployment dispatch also used an abbreviated SHA that
checkout could not resolve; it made no deployment changes. The successful runs
above supersede those attempts.

## Flag and recovery validation — 2026-10-26

The [flag deployment](https://github.com/tuist/tuist/actions/runs/40340462391)
succeeded with server `sha-7045388cc80e`. With no flag enrollment, the
[default-off smoke](https://github.com/tuist/tuist/actions/runs/40342376133)
received the Canadian public-region Service and passed remote upload/restore.
Only the Tuist staging account (actor `account:2`) was then enabled.

Four real GitHub jobs overlapped on the staging runner:

| Run | Workload | Outcome |
| --- | --- | --- |
| [40343466491](https://github.com/tuist/tuist/actions/runs/40343466491) | Upload, hold 900 seconds, delete outputs and restore | PN remote hit after flag disable and a cache-pod restart |
| [40343471476](https://github.com/tuist/tuist/actions/runs/40343471476) | Actual Tuist Gradle plugin production and test Kotlin sources | Cold compilation 54 seconds; restore 4 seconds; both compile tasks FROM-CACHE, all class checksums match |
| [40343476526](https://github.com/tuist/tuist/actions/runs/40343476526) | Synthetic upload/restore with 60-second hold | Passed |
| [40343482053](https://github.com/tuist/tuist/actions/runs/40343482053) | Synthetic upload/restore with 60-second hold | Passed |

The actor was disabled at 14:52:39 UTC. The PN instance entered drain-pending at
15:00:01 while the held job remained running. One replica was deleted and
recreated Ready (pod UID changed from `0c7a29b8-1397-4c09-9d5d-53362cd82ee9`
to `cf1deb7b-6a9c-4632-acd6-13eb86e1da36`); the sibling stayed up. The held
job restored FROM-CACHE at 15:06:47 while the flag was still false. Re-enabling
at 15:07:45 returned the same server row
`d0dd2529-fe27-48ef-ad5c-7a46b08e0b92` to active with its drain clock cleared
by 15:10:30. No cache row or volume was recreated for re-enrollment.

Flag writes used a scoped staging release-eval process. It does not share the
web process's local PubSub/cache, so this drill exercises persisted values plus
the existing 600-second cache TTL, not instantaneous Ops API invalidation.
A new-job check dispatched while disabled
([40344982864](https://github.com/tuist/tuist/actions/runs/40344982864)) spent
about 13 minutes queued at GitHub and started after re-enrollment. It passed on
PN and is recovery evidence, not evidence of WAN dispatch during the off window.

The controlled repeat on the readiness-fixed server paired
[held PN job 40348815088](https://github.com/tuist/tuist/actions/runs/40348815088)
with [new WAN job 40349172332](https://github.com/tuist/tuist/actions/runs/40349172332).
After the held job uploaded, the actor was disabled at 15:24:57. A rolling
server restart cleared its process-local flag cache. The same PN row entered
drain-pending at 15:25:18; at 15:25:34 selection returned the Canadian WAN URL
while the PN Service still returned readiness 200. The new job received WAN
and restored FROM-CACHE at 15:26:27, while the held job remained running on PN.
The held job then restored FROM-CACHE at 15:29:09, still with the flag off.
The actor was re-enabled at 15:29:45 followed by another rolling server restart.
This proves both routing outcomes and in-flight retention on the deployed code;
the deliberate cache refresh does not measure Ops invalidation latency.
At 15:31:02 the same PN row was active, `/ready` was 200 and dispatch selected PN
with a 15:31:01 heartbeat. The staging cohort remains only `account:2`.
The [rollout observations](validation/linux-runner-pn-2026-10-26/rollout-observations.txt)
retain flag/instance snapshots and the two jobs' endpoint/result log lines.

The real Kotlin test was also rerun successfully on this server in
[40348670426](https://github.com/tuist/tuist/actions/runs/40348670426).

Code review during the outage drill found a real selection gap: cluster-DNS
private endpoints were exempt from readiness expiry. A Service with no healthy
backends could still be selected indefinitely. The fix probes `/ready` on
activation and reconciliation, with two-second connect/receive timeouts, no
retries and no redirects. Only HTTP 200 refreshes `last_ready_at`; dispatch
uses the existing 120-second freshness window without a network call. Failed
probes preserve the old URL and timestamp so recovery reuses the same row.
Running jobs retain the endpoint injected at dispatch; this is not mid-job
failover. A path failure unique to a runner can still escape a server-side probe.

[Readiness deployment 40347228312](https://github.com/tuist/tuist/actions/runs/40347228312)
succeeded with server `sha-1d731b801361` and provider `61cf6144`, retaining
Kura runtime `sha-eea9626bab67`. At 15:21:45, `/ready` returned 200,
`last_ready_at` was 15:21:13, and dispatch selected the same PN instance.
The previous implementation had retained a 12:55:52 timestamp while still
selecting it. Regression tests cover failed activation, HTTP 503, transport
failure, missing/stale heartbeat fallback and recovery.

The bounded full-endpoint network fault could not run: the staging identity
received Kubernetes RBAC `403 Forbidden` when creating a CiliumNetworkPolicy
scoped only to this account's PN pods and ports 4000/4001. No policy was created.
Live automatic outage fallback therefore remains unqualified despite the
regression tests. It needs an approved fault-injection path with guaranteed
cleanup. Eventual teardown on a disposable account and a second excluded
account's live job also remain untested; local tests cover those state paths.
These four overlapping jobs establish functional concurrency, not saturation,
production capacity, Android application performance or cache-host redundancy.

## Production preparation — 2026-10-26

The read-only [OVH inventory](validation/linux-runner-pn-2026-10-26/production-network-inventory.json)
confirms ten existing RISE-L Linux runner hosts in Gravelines, each with a
**1 Gbps private contract**, 1 Gbps public contract and no OLA support. None of
those ten live `OVHDedicatedMachine` objects is enrolled through `spec.vRackID`
yet. The six existing public-cache ADVANCE hosts have **25 Gbps private / 3 Gbps
public** contracts and report private networking ready. They remain in the
public region's historical `kura-dedibox` pool; assigning that capacity to a
second independently accounted region is not part of this rollout.

The initial preparation assumes reuse of the existing runner fleet. Their
1 Gbps host-wide limit remains the throughput ceiling shared by concurrent
jobs. Faster cache NICs do not raise that ceiling. The proposed cache hosts
are additional private-region capacity, not replacements for the runners.

A [catalog quote](validation/linux-runner-pn-2026-10-26/production-capacity-quote.json)
for **two ADVANCE-1 hosts** (`26adv01-v7-eu`, AMD EPYC 4245P,
32 GB DDR5 On-Die ECC, 2×960 GB datacenter NVMe with software RAID) is
**$408/month total plus $408 setup**, before tax, on a month-to-month term.
The included network contracts are 25 Gbps private and 3 Gbps public per host.
The OVH US [bare-metal catalog](https://api.us.ovhcloud.com/1.0/order/catalog/public/baremetalServers?ovhSubsidiary=US)
and [availability endpoint](https://api.us.ovhcloud.com/1.0/dedicated/server/datacenter/availabilities?planCode=26adv01-v7-eu)
reported 72-hour Gravelines availability for that configuration on October 26.
This is a non-binding catalog quote, not reserved stock or an order. No paid
order or production provisioning mutation has been made. Recheck the exact
cart total and availability before purchase.

The optional [production overlay](production-linux-runner-private-cache.values.yaml)
prepares a two-host `kura-ovh-gra-runners` fleet using adoption prefix
`tuist-kura-ovh-production-gra-runners` and enrolls the runner template in
`pn-2024093` (`172.30.243.0/24`). It is deliberately outside the default managed
production values. Rendering with managed-common, managed-production and CI
values succeeds and produces two cache Machines plus the runner vRack field.
Its initial 3 Gbps aggregate shaping budget and the region's 750 Mbps
per-instance egress setting are conservative software limits, not measurements
of a 25 Gbps path. Two physical hosts provide pool capacity; the current
preferred co-location policy does not promise that each account's two replicas
occupy different hosts or survive a host loss without recovery.

Apply in this order, keeping `kura_linux_runner_cache` absent/off throughout:

1. Finish the staging gates, review and merge the draft PR. Production deployment
   requires `refs/heads/main`; do not route a draft through an alternate workflow
   ref to bypass that guard. Promote the reviewed server and compatible provider
   through the normal deployment path. Provider build
   [40343993520](https://github.com/tuist/tuist/actions/runs/40343993520) passed
   from `61cf6144094`, including the main-branch BMC hardening; its image tag is
   `61cf6144`. Keep unrelated runtime/controller versions at the reviewed pins.
2. Approve/order the two cache hosts, install and verify mirrored system storage
   and local XFS cache storage, then apply the optional overlay. Verify the
   adopted service IDs, pool labels, taints, private address reservations and
   Ready/PrivateNetworkReady conditions before exposing the region.
3. Obtain human production write elevation covering vRack enrollment and
   runner draining. Check the live template against the reviewed values. Cordon
   one runner, let its jobs finish, patch only that idle Machine's `spec.vRackID`
   to `pn-2024093`, verify KataRuntimeReady and PrivateNetworkReady, and uncordon
   it after qualification. Repeat one at a time. `OnDelete` does not propagate a
   template field onto existing Machines; do not delete hosts to force it.
4. Qualify reciprocal full-MTU private paths and fail-closed public route guards,
   then capture both private and public NICs during a checksum-verified cache
   transfer. Record contracted and negotiated link rates separately. Measure
   actual throughput and concurrent-job headroom before changing software caps.
5. Make the region available only after all eligible runner hosts are qualified,
   leaving the account flag off. Enroll only the internal account after explicit
   rollout approval and retain a WAN control cohort.

Production's existing public cache is already in Gravelines. The staging
comparison against Canada measures a transatlantic baseline, so its 1.6–2.3×
Gradle improvements are **not a production forecast**. Production qualification
must compare PN with its actual nearby public-region baseline on the same
runner and account before broadening enrollment.

The production identity currently lacks Machine patch access (`auth can-i`
returns `no`); no production deployment,
flag enrollment, runner network mutation or purchase was performed. Human JIT
access is required by [the cluster access rules](../AGENTS.md#cluster-access-for-agents).
