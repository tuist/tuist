# Linux runner cache in OVH Gravelines

`ovh-gra-runners` is a private, Linux-only region on the
`kura-ovh-gra-runners` pool. Account caches use the managed two-replica lifecycle,
local XFS storage, and a 750 Mbps egress setting. The replicas share the
staging cache host, so staging does not demonstrate host redundancy.

Runner dispatch prefers the active private instance's cluster Service and falls
back to the account's public-region Service while unavailable or disabled.
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

## Account rollout and remaining staging gates

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

Validation status: the flag change passes 230 focused local tests covering
feature helpers, Ops evaluation, regions, admission/draining and endpoint
selection. The live measurements below predate the flag change. The flag-bearing
server deployment and the live drills above are still pending; neither the
local tests nor the benchmarks are evidence that those drills passed.

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
