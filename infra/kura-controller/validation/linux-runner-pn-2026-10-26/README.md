# Historical staging experiment — 2026-10-26

These are measurements from the now-removed dedicated Linux runner-cache
implementation, not end-to-end validation of regional-instance reuse. Raw
artifacts retain their original endpoint names, flag operations and timestamps.
They must not be used as current deployment instructions. The previous source
and workflow can be inspected at commit `d1aad37f57d`.

The current approach and outstanding migration/validation are described in
[the runbook](../../linux-runner-private-cache.md). The old account-flag recovery
drills in `rollout-observations.txt` do not validate rollback of host vRack
routes. Both historical network paths used vRack; the remote one crossed the
Atlantic. Production already has caches in Gravelines, so these results are
not a prediction of its improvement.

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

Raw [requests](requests.csv) and
[request environment](request-environment.json)
are checked in; the workflow retains them in its `kura-request-latency` artifact.
Reproduce both tables with:

```sh
node infra/linux-runner-image/summarize-kura-request-latency.mjs \
  infra/kura-controller/validation/linux-runner-pn-2026-10-26/requests.csv
```

For new runs against ordinary regional instances, use the current runbook.
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

Raw [results](results.csv),
[environment](environment.txt),
[runner capture](runner-packets.txt),
[cache capture](cache-packets.txt), and
[latency samples](latency.txt) are checked in.
All 40 Gradle logs are retained in the comparison run's
`gradle-pn-benchmark-logs` artifact. Reproduce the table with:

```sh
node infra/linux-runner-image/summarize-gradle-pn-benchmark.mjs \
  infra/kura-controller/validation/linux-runner-pn-2026-10-26/results.csv
```

At measurement time, the legacy RISE-S was cordoned with unrelated fixtures,
and both cache replicas shared one host. These results establish neither
cache-host redundancy nor production throughput. No OVH contract was terminated.

The initial benchmark attempt used 128 MiB and correctly failed when the remote
cache rejected an artifact above its 100 MiB limit. Those incomplete samples
are excluded. Its Docker artifact-path issue was corrected before the complete
1/64 MiB run. The first deployment dispatch also used an abbreviated SHA that
checkout could not resolve; it made no deployment changes. The successful runs
above supersede those attempts.
