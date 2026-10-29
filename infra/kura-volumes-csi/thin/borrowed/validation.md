# Borrowed-volume prototype qualification

This record concerns the disposable prototype in this directory. It is not
approval to enroll hosted nodes, ship the experimental segment layout, remove
per-device backing, or declare the production sharing backend implemented.

## Corrected encryption versus shared XFS — matched Paris comparison, October 29

This closes the missing direct comparison between the corrected encrypted
configuration and the current shared-XFS storage approach. It is a **storage-layout
comparison on staging**, not a measurement of live production traffic or of AES
alone. Both sides use the same pinned runtime with borrowed-unit mode disabled;
this section does not qualify the later multi-volume sharing layout.

### Results and interpretation

All **137,280 authenticated requests passed with zero failures and zero runtime
OOM kills**. These are six samples per layout, with no discarded runs.

| Metric | Shared XFS median (range) | Corrected thin median (range) | Median change |
|---|---:|---:|---:|
| Eviction upload MiB/s | 162.74 (161.02–166.35) | 156.27 (154.79–162.31) | -3.98% |
| Fresh 16KiB PUT p95 ms | 30.80 (29.84–31.87) | 31.34 (30.72–33.68) | +1.73% |
| Warm 16KiB PUT p95 ms | 28.64 (26.30–29.26) | 30.40 (29.83–31.04) | +6.14% |
| Warm 16KiB PUT p99 ms | 36.06 (35.46–36.41) | 38.52 (38.05–39.67) | +6.83% |
| 4MiB PUT p95 ms | 259.06 (230.99–279.77) | 268.17 (225.91–273.16) | +3.51% |
| Working-set GET MiB/s | 470.33 (453.30–500.22) | 499.09 (481.61–519.11) | +6.12% |
| Working-set GET p95 ms | 118.46 (108.85–126.51) | 104.44 (101.17–107.30) | -11.83% |
| Warm 16KiB GET p95 ms | 1.67 (1.42–1.80) | 1.80 (1.53–1.94) | +7.62% |
| Full workload CPU s | 42.16 (41.67–42.40) | 42.68 (41.65–43.12) | +1.24% |
| Full workload throttled s | 59.72 (43.03–75.42) | 33.05 (31.57–55.01) | -44.65% |

The useful planning estimate for this tested workload is **about 4% less upload
throughput during eviction**, **1.76 ms higher warmed small-upload p95**, and
**about 1.2% more runtime CPU**. It is not a blanket 1% encryption cost.
The previous 1.3% figure compared two encrypted formats; it was not a comparison
against the shared-XFS baseline.

The median throughput comparison is a 3.98% loss; the mean of the six adjacent
pair changes is a 3.65% loss. Five of six pairs were slower on thin encryption,
with changes from **−5.69% to +0.80%**. Every pair had higher warmed small-upload
p95 on encryption, by **0.94–4.00 ms**. Fresh-cache small-PUT p95 was closer
(30.80 versus 31.34 ms); these short fresh-cache and extended post-churn phases
should not be conflated. Warmed PUT p99 rose by 2.46 ms.

Large-PUT p95 has a 3.51% higher median, but its paired changes range from
−10.28% to +15.33%, with a mean of +0.99%; that workload is too variable to
promise a fixed large-upload latency penalty. Working-set GET throughput had a
6.12% higher median, but one pair was slower; this is not a claim that encryption
universally speeds up reads. Small warm-GET p95 rose by about **0.13 ms**.
CPU throttling was recorded and differed between layouts despite identical CPU
limits; the table reports the measured full-layout behavior, not attribution of
every difference to cryptography.

These observations close the missing matched **cache-workload comparison**.
They do not waive the earlier direct-I/O/QD32 regressions, production runtime/base
layout gates, or rollout safety requirements. No fleet-wide capacity or memory
gain is inferred. The PR remains draft and production enrollment remains disabled.

### Fixed method

The experiment used the same Paris EPYC 7232P/NVMe RAID1 node and runtime digest
`2c7e3ddc67bd196452663078c9f95bf8dd17a654d8bb0d9c0c388bc8c072ab43` as the
preceding investigation. Runtime limits were one CPU/768 MiB with a 4 GiB cache;
the same-node client had two CPUs/2 GiB and eight concurrent requests. Only one
runtime was active at a time. Twelve fresh-cache samples ran in the predetermined
order **AB BA AB BA AB BA**, where A is shared XFS and B corrected thin encryption.
This produces six adjacent pairs, equally split between each layout running first.
No setting was tuned between samples.

- **Shared XFS:** a private fresh directory in the existing 128 GiB `data` LV,
  bind-mounted into the fixture. The filesystem remained unchanged: four allocation
  groups, reflinks enabled, 64 MiB journal, zero log stripe, `relatime`, and its
  existing `prjquota` mount option. This was not a fresh standalone plain LV.
- **Corrected encrypted layout:** a new 13 GiB virtual LV in a private 32 GiB
  thin pool with 512 KiB chunks and 512 MiB metadata. LUKS2/AES-XTS, discard
  passthrough, crypto workqueues with submission from crypto CPUs, XFS with
  reflinks disabled, 64 MiB journal and explicit 4 KiB log stripe; `noatime`,
  project inheritance and a 10 GiB hard project quota. The same node/NVMe array
  backs both layouts. The filesystem's virtual size is not the cache grant.

Every sample ran the unchanged full cache benchmark (400 small PUT/GETs,
64 large 4 MiB PUT/GETs, 6 GiB eviction churn and post-churn GETs), then seeded
and checksum-read a shuffled 1 GiB working set larger than runtime memory.
It then ran a separately reported 400-write warmup and 4,000 small PUTs plus
4,000 checksum GETs. These extended small-request measurements are **after the
full/churn/working-set sequence**, not a cold-cache test. Churn throughput is
total uploaded bytes divided by summed upload-phase time, excluding object
generation and setup. All request failures and checksum mismatches fail the run.

The pre-existing image's client handled the historical full/working-set workloads;
the diagnostic client handled extended small requests. Client identity and mode
were held constant between layouts; the transferred diagnostic binary's SHA-256
was verified as `c5c25a23f0b130ea156858ac7813c5c9a80cb565c77234600a9f30eb48888a41`.
Runtime CPU/throttling, memory events, attributable I/O, host CPU/disk counters,
actual XFS geometry and filesystem margins were recorded for each sample.
There was no global cache drop. Synthetic keys/authentication were generated in
memory; this run exercises data-path performance, not OpenBao authorization.

The runtime is a single-node fixture with itself as its peer and a same-node
HTTP client. Internet/TLS/ingress latency, cross-node replication, fleet load,
and a rollout handoff are outside this benchmark. Absolute request latency and
throughput should not be presented as production service-level predictions.
Tables report the median of six per-run measurements and the full observed
range; latency percentiles are per-run percentiles, not a pooled percentile.

### Adjacent-pair evidence

| Pair / order | Shared churn MiB/s | Encrypted churn MiB/s | Throughput change | Warm PUT p95 change |
| --- | ---: | ---: | ---: | ---: |
| 1 / AB | 161.02 | 162.31 | +0.80% | +0.94 ms |
| 2 / BA | 161.03 | 155.29 | -3.56% | +1.28 ms |
| 3 / AB | 162.93 | 157.04 | -3.61% | +1.24 ms |
| 4 / BA | 162.56 | 155.65 | -4.25% | +2.11 ms |
| 5 / AB | 166.35 | 156.88 | -5.69% | +4.00 ms |
| 6 / BA | 163.95 | 154.79 | -5.59% | +3.27 ms |

### Cleanup and provenance

The harness deleted each runtime before detaching its storage and used ordinary
unmounts only. All temporary runtime/client pods, synthetic authentication Secret,
shared-XFS fixture directories, mappings, LVs, sentinel and private pool were
removed. VG free capacity returned exactly to **812,541,542,400 bytes**, with only
the original `data` LV remaining. No node restart, CSI deployment, image
publication, production mutation or global cache drop was performed. The changed
format command was exercised directly on the staging volumes; the Go-driver and
OpenBao lifecycle qualifications described below remain prior evidence, not tests
rerun by this benchmark.

The source remained `f4c163d8d36`; no runtime or driver code changed for this
comparison. The local reports contain measurements and no credentials:

- Results: `kura-matched-results.json`, SHA-256 `239a583f1e94835eef701058748a7786266849a07e83d96fbcc345eae1b757df`.
- Bounded staging harness: `kura-matched.rb`, SHA-256 `93f56306ba987499c6d2d1675c0f72aba6c246f66766a421d9bbf545f9135344`.
- Diagnostic client: SHA-256 `c5c25a23f0b130ea156858ac7813c5c9a80cb565c77234600a9f30eb48888a41`, verified after transfer.

## Small-upload latency investigation — October 29

The October 28 result (shared XFS 28.93–32.99 ms versus thin units
35.77–38.37 ms at 16 KiB PUT p95) was a **whole-layout comparison**, not a
measurement of encryption alone. It sampled 400 small PUTs over roughly one
second per run. Thick and thin paths also differed in project quotas,
`submit_from_crypt_cpus`, reflinks, and device-derived XFS geometry.

### Method and initial controls

The investigation used the same Paris EPYC 7232P/NVMe node, kernel
6.8.0-146-generic, and pinned runtime digest
`2c7e3ddc67bd196452663078c9f95bf8dd17a654d8bb0d9c0c388bc8c072ab43`.
The runtime remained at one CPU/768 MiB and a 4 GiB cache; the same-node client
had two CPUs/2 GiB. Each fresh LV was 13 GiB. Only one runtime was active at a
time, and layouts ran forward then reverse. Each sample collected a cold
400-PUT/400-GET phase, a separately reported 400-write warmup, and then
4,000 PUTs plus 4,000 checksum-verified GETs at concurrency eight. Generation of
request bodies was outside timed phases. The longer phases measure small
requests without eviction; they do not replace the earlier churn benchmark.

Volumes came only from free extents in a private 32 GiB staging pool and a
separate temporary thick LV. A 64 MiB virtual sentinel kept the diagnostic
pool active during thick controls. No CSI template, tenant PVC, server
configuration, or enrollment setting changed. Keys and authentication were
synthetic: this isolates storage I/O and does not repeat OpenBao authorization
qualification. API TLS timeouts affected setup, not the timed pod-IP HTTP path.

The initial 16 samples passed **147,200 requests with zero failures and no
runtime OOM kills**. The plain control below is a fresh plain LV with the test
format, **not the existing shared-XFS production-style baseline**. `Matched`
means matching explicit mkfs arguments, not identical effective geometry.

| Configuration | Cold PUT p95 ms | Warm PUT p95 ms | Fresh sync p95 ms | Overwrite sync p95 ms | Warm CPU s | Warm throttled periods |
|---|---:|---:|---:|---:|---:|---:|
| plain_matched | 24.57–24.63 | 26.17–26.53 | 3.59–3.63 | 2.35–3.93 | 8.78–8.80 | 14–18 |
| thick_legacy | 32.89–35.37 | 29.30–29.40 | 3.87–5.02 | 1.51–4.01 | 9.15–9.15 | 11–11 |
| thick_matched | 31.65–31.75 | 28.93–29.92 | 3.76–3.93 | 1.45–4.00 | 9.10–9.14 | 11–11 |
| thick_quota | 27.05–29.63 | 29.82–30.46 | 3.82–3.98 | 1.43–3.55 | 9.27–9.32 | 10–11 |
| thin_noquota | 32.23–37.80 | 34.44–35.62 | 7.75–7.81 | 1.47–3.99 | 8.87–8.99 | 6–7 |
| thin_quota | 32.87–38.32 | 35.64–36.29 | 7.79–7.87 | 1.65–4.04 | 8.95–8.97 | 5–6 |
| thin_legacy_crypto | 30.64–36.93 | 34.75–35.48 | 7.85–8.04 | 1.53–1.58 | 8.96–8.97 | 6–6 |
| thin_legacy_format | 35.26–38.51 | 36.00–36.05 | 7.79–7.83 | 1.44–4.07 | 8.95–9.14 | 6–6 |

The matched-argument thick/thin midpoint gap was **5.6 ms without quotas**
and **5.8 ms with quotas**. Removing quotas, reverting crypto submission, or
restoring reflinks did not recover most of it. Thin runtime CPU was comparable
or lower, with fewer throttled periods in the aggregate warm PUT/GET counters;
those counters do not time CPU throttling per individual request.

### Durability, premapping and inferred filesystem geometry

A separate serial probe wrote 1,024 chunks of 16 KiB, recording write and
`fdatasync` duration separately, then overwrote the same file and finally tested
buffered writes with a final sync. Fresh-write mean sync latency was
3.60–3.67 ms on the matched thick control and 4.94–4.98 ms on thin without
quotas. Overwrite means overlapped: 1.40–1.48 versus 1.43–1.52 ms. This suggested
an allocation/durability interaction but did not identify its layer.

A second four-sample run passed **36,800 requests**, with zero failures. It
compared ordinary thin storage to an otherwise identical thin LV whose entire
13 GiB was mapped by direct writes before LUKS/XFS formatting. Exact mapped
sectors were checked before and after formatting; `mkfs -K` preserved the maps.
Premapping improved warmed PUT p95 from **35.32–35.77 to 34.12–34.82 ms**. It did
not recover the full gap, so thin allocation alone was an incomplete explanation.
Premapping was a diagnostic, not an admission or production-layout change.

Inspecting `xfs_info` revealed why matching command arguments was insufficient.
The thick controls had four allocation groups and no data/log stripe. Thin
controls inferred sixteen groups, a 128 KiB data stripe unit, a 512 KiB data
stripe width, and a **128 KiB log stripe** from block-device hints. All had a
64 MiB log. Restoring the legacy mkfs arguments changed reflinks but left this
inferred thin geometry in place.

At the underlying RAID device, runtime-cgroup write counters for the same warm
phase were **88.5–89.3 MiB on matched thick controls versus 456.3–469.3 MiB on
thin controls**, with similar write counts. These are attributable cgroup bytes,
not a complete measurement of all host or thin-metadata work. The upstream
[XFS format documentation](https://kernel.googlesource.com/pub/scm/fs/xfs/xfsprogs-dev/+/refs/heads/master/man/man8/mkfs.xfs.8.in)
explains that log writes are rounded to the log stripe boundary. This made
inferred journal padding a testable cause of write amplification.

A third six-sample Paris run changed the log stripe alone (`-l size=64m,su=4k`),
then tested full flat geometry (`-d noalign,agcount=4`) separately. Both retained
LUKS, project quotas, the 64 MiB log, and all durability operations. All
**55,200 requests passed**.

| Thin format | Warm 16 KiB PUT p95 | Warm attributable writes | Fresh sync p95 |
| --- | ---: | ---: | ---: |
| Original inferred 128 KiB log stripe | 34.92–35.72 ms | 469.41–474.05 MiB | 7.85–7.86 ms |
| Explicit 4 KiB log stripe, same data geometry | 30.58–31.33 ms | 93.55–93.75 MiB | 6.51–6.54 ms |
| Fully flat geometry, four allocation groups | 30.25–30.55 ms | 89.08–89.28 MiB | 6.35–6.59 ms |

The log-only change recovered **4.36 ms at warm p95 sample midpoints** and
reduced attributable writes by about **80%**. This is causal evidence for the
inferred log stripe as the dominant avoidable component in this workload.
It does not prove that encryption or thin mapping has zero residual cost.
The contemporaneous matched thick/quota control was 29.82–30.46 ms; the corrected
thin control remains slightly slower. The original shared-XFS 28.93–32.99 ms
range came from a different short benchmark and is not a statistical-equivalence
claim for these extended tests.

Commit `cd3ed558fa9` pins only the log stripe for **newly formatted thin
volumes**, including children through their shared NodeStageVolume path. It
retains data alignment, allocation-group selection, encryption, quotas, reserve
accounting, and sync barriers. Restage does not reformat an existing filesystem;
old volumes need the established staged replacement to adopt the new geometry.
Staging exercised the exact format command on isolated real LVs with the
unchanged deployed CSI image; the changed Go driver is separately compiled and
exercised by the disposable-VM lifecycle test, including an `xfs_info` assertion.

A final fresh-volume ABBA replay used the original full cache client from the
pinned image: 400 small PUT/GETs, 64 large PUT/GETs, 6 GiB of eviction churn,
post-churn reads, then a separate 1 GiB corpus with shuffled checksum reads.
All **12,160 requests passed with zero runtime OOM kills**.

| Layout | Small PUT p95 ms | Large PUT p95 ms | Churn MiB/s | Working-set GET MiB/s | Runtime CPU s |
|---|---:|---:|---:|---:|---:|
| thin_quota | 34.15–35.61 | 270.16–270.58 | 156.06–157.19 | 462.34–487.92 | 42.43–42.93 |
| thin_log4k | 28.42–33.12 | 272.61–283.94 | 154.63–154.68 | 466.14–493.69 | 43.23–43.30 |

The short full-run small-PUT p95 improved, consistently with the longer
diagnostic. Churn was **about 1.3% lower at sample midpoints**, runtime CPU
about 1.4% higher, and large-PUT p95 slightly higher with the correction.
Read-throughput ranges overlapped. This is a measured tradeoff, not a
no-regression or statistical-equivalence claim. It must remain visible in
the release decision. Reducing the log stripe also lowers [XFS's default log-buffer size](https://www.man7.org/linux/man-pages/man5/xfs.5.html)
from 128 to 32 KiB on this stack; that could contribute to the bulk-workload change,
but this experiment did not independently test buffer sizing. No buffer-size
tuning is shipped or claimed as a remedy.

Kura's segment and WAL durability waits are on the acknowledgment path. Small
uploads expose fixed sync costs; larger writes can amortize them. Linux also
commits changed thin mappings before completing the associated flush/FUA, as
shown in the [Linux 6.8 thin target](https://github.com/torvalds/linux/blob/v6.8/drivers/md/dm-thin.c#L696).
The experiment distinguishes these mechanisms; it does not assign every
millisecond to a particular kernel function or establish fleet-wide equivalence.

### Reproducibility, limits and cleanup

The bounded client now supports `-small-only -small-count 4000 -warmup 400` and
explicit concurrency. Its CLI test verifies separate warmup counts and rejects
corrupt checksum responses. `go test ./...` and `go vet ./...` passed. Ruby
syntax and actionlint passed (the latter excludes the repository's existing
custom-runner-label warnings).

The reusable disposable-VM `latency_stack.rb` and dispatch-only
`latency_only=true` job cover the same factors and publish no image. Initial
run [40854445950](https://github.com/tuist/tuist/actions/runs/40854445950) failed
before measurement because the pool was inactive during a thick control;
cleanup passed. An empty sentinel corrected the harness. Run
[40854959458](https://github.com/tuist/tuist/actions/runs/40854959458) passed
16 samples/147,200 requests and cleanup. The geometry-expanded run
[40858913871](https://github.com/tuist/tuist/actions/runs/40858913871) passed
20 samples/184,000 requests and cleanup. VM HTTP tails were noisy and used a
loop-backed disk/kernel 7.0.0-1017-azure; they are not substituted for Paris
measurements. The artifact retains actual geometry and per-phase counters.

The fix qualification run
[40860709975](https://github.com/tuist/tuist/actions/runs/40860709975), source
`cd3ed558fa9`, passed another 20-sample/184,000-request VM comparison and
`TestThinRealStack` on both 64 KiB and 512 KiB pools (21.64 and 22.02 seconds).
Those tests executed rather than skipped: each logged the actual 4 KiB stripe,
and passed quota/reclaim, failed-discard and intent recovery, retained backing,
restart checksums, concurrent admission, reserve refusal and deletion checks.

Across the four Paris experiments, **251,360 requests passed with zero reported
failures and zero runtime OOM kills**. Each run removed its own runtime/client,
synthetic authentication Secret, LV, mapper, mount, pool and sentinel. The final
VG has only its original `data` LV and exactly **812,541,542,400 free bytes**,
matching the initial inventory. The original CSI Pod UID and deployment were
retained; production was not mutated. No global cache drop, forced/lazy
unmount, or uncertain-backing deletion was used. The toolchain was cryptsetup
2.7.0, XFS tools 6.6.0 and LVM 2.03.16; the RAID1 arrays were healthy, with no
resynchronization running at the recorded health check.

Raw local reports (no credentials) are retained outside the source tree with
these SHA-256 hashes:

- `kura-latency-paris-results.json`: `11176657ddfb6904911cc4c934962ac6423e7961bab425c8f4e5b79b28af3412`
- `kura-latency-premapped-results.json`: `6044f6050dceccb1a5b859668607bad5e8373fe28ef85dc689d8771411997ecb`
- `kura-latency-geometry-results.json`: `e7763024cd579d8818c47756204b98f2d4de732dd394c88e6a001077c07091ad`
- `kura-latency-full-results.json`: `f56c0d50f10b9b778a9a39cb80412c0921019f7502d61836e26cc31f4b74bab9`

Earlier direct-I/O/QD32 read regressions remain separate evidence. These
bounded cache controls do not establish fleet-wide equivalence, node power-loss
recovery, supported production runtime layout, or regional capacity/memory gains.
Production-format changes need those applicable gates; this investigation does
not waive them.

## Real Kubernetes/OpenBao qualification on Paris staging

The isolated October 28 fixture runs on
`tuist-tuist-kura-fleet-fm4h8-qmkn8`: AMD EPYC 7232P (8 cores/16 threads), kernel
`6.8.0-146-generic`, the node's actual NVMe-backed VG. It uses a new **48 GiB**
thin data pool made only from unallocated extents, **512 MiB metadata**, **512 KiB
chunks**, **1 GiB data reserve**, **64 MiB metadata reserve** and **eight slots**.
The existing `data` LV and unrelated workload were not converted or reformatted.
This is ordinary bounded provisioning, not the destructive disposable-VM harness.

Only the Paris CSI pod was replaced, using `OnDelete`; the other two plugin pod
identities/images stayed unchanged. The ordinary template was restored under
`OnDelete` immediately after each scoped restart. The test uses an isolated
three-voter persistent OpenBao 2.7.1 cluster, TLS, Kubernetes authentication and
a derived non-exportable Transit key. Two synthetic accounts have real persisted
wrapped key rows and distinct live PVC ownership. The main server deployment,
ordinary key-provider defaults and production enrollment were not changed.

The key listener runs the **compiled production controller, VolumeKeys, Repo,
Kubernetes client and OpenBao provider**, with a small fixture-only Bandit/PubSub
bootstrap instead of the main application's supervision tree/background jobs.
It verifies real projected pod-bound CSI tokens and live PV/PVC ownership. This
is not a full Phoenix deployment smoke test or permanent OpenBao custody rollout.

Image/source identities:

- CSI source `170e555be89bbc3ea0f3445c739029cc92b2e57a`, image
  `ghcr.io/tuist/kura-volumes-csi@sha256:ea6492b17b9db4e8a9c0503d04e0ea4bf73abffe678ca9510f4231a9c4381afc`.
- Experiment runtime from the qualified `ce0cb6914e9` build, image
  `ghcr.io/tuist/kura@sha256:2c7e3ddc67bd196452663078c9f95bf8dd17a654d8bb0d9c0c388bc8c072ab43`.
- Compiled server artifact from `339fea900c053209b07cb4a21243ee7a253839e6`,
  key-only image
  `ghcr.io/tuist/tuist@sha256:cc01d2d5791ac7f1488b9e107a77d34c1f3063486dd2297c3d132b1262562cd0`.
  This derivative omits browser/toolchain and unrelated static/native/doc assets;
  the controller and VolumeKeys BEAM hashes match the full server artifact.

The real staging sequence passed:

1. Verified TLS and rejected an unauthenticated request to the compiled endpoint.
2. Wrapped only the two fixture accounts with OpenBao, then created real encrypted
   parent claims through the Kubernetes external provisioner and kubelet.
3. Created a child through the fenced Unix-socket API. It appeared in the already
   running unprivileged Kura pod through host-to-container propagation. Exact
   response replay allocated nothing twice; a stale generation was refused.
4. Wrote/read a 1 GiB corpus (512 successful requests) across base and child.
   After a real CSI Pod replacement, all 256 objects still matched their hashes.
5. Deleted the runtime Pod and verified both parent and child dm-crypt mappings
   were closed. Sealing two of three OpenBao voters removed quorum. A third seal
   request returned 500 because quorum was already absent; status confirmed two
   sealed voters and one unsealed standby. Real kubelet restage failed with the
   expected key-service 503, rather than opening without authorization.
6. Restored quorum, re-staged, and verified all 256 checksums. Base/child LV UUIDs
   stayed stable while the runtime Pod UID changed; the previous Pod's lease was
   rejected. Transit rotation and account-key rewrap to envelope v2, followed by
   another cold Pod replacement, preserved all 256 checksums again.
7. Held a real child segment open inside the unprivileged Pod. CSI-driven drain
   retired/unlinked its segments. Release failed while the reader remained open;
   both mapped pool usage and full commitment stayed charged. The descriptor's
   bytes stayed readable until final close. Retrying the same release then
   removed the child; repeating the completed request could not credit twice.
8. Created a fresh child for the second synthetic account in the same pool. Its
   experimental runtime wrote/read another 1 GiB corpus (512 successful requests)
   and placed real segments on the new child. Both base LV identities survived.
9. OpenBao audit inspection found 165 records and verified JWT/plaintext fields
   were HMAC-protected rather than logged in cleartext.

The held-reader boundary retained **27,917,287,424 committed bytes** and
**1,383,596,032 pool data bytes**. Final close/deletion reduced commitment to
**20,937,965,568 bytes** (exactly **6.5 GiB released**) and pool data to
**758,120,448 bytes**. These are authoritative pool/device observations, not
`df`, deletion success or fstrim's claimed byte count.

Failures during fixture setup are retained as limitations, not passing evidence:

- The original 903 MB server fixture image hit a registry connection reset while
  pulling. A 114 MB key-only derivative pulled successfully; no containerd socket
  importer or host-control bypass was used.
- The first key bootstrap called an unavailable direct PubSub start function;
  it was corrected to use the dependency's supervisor child specification.
- The initial 512 MiB load generator was OOM-killed during calibration. The
  complete comparison uses a **2 GiB client**, while every runtime remains at
  **1 CPU/768 MiB**. The failed partial sample is excluded.
- Reapplying the initial manifest list attempted to change the already-reset
  plain fixture's immutable init command. Kubernetes refused that update; the
  separate thick claims/pods still provisioned successfully. Subsequent setup
  excludes the existing plain Pod from that list.

Matched hardware comparison and cleanup verification follow below. This
fixture does not qualify node power loss, permanent unseal/backup custody, the
production fairness agent, a supported multi-volume cache format, or a new
migration/endpoint-handoff path. Existing migration safeguards remain mandatory.

## Matched Paris hardware comparison and interpretation

All **ten samples** passed: **30,400 authenticated HTTP requests**, zero reported
failures and zero runtime OOM kills. Layout order was shared XFS, thick monolithic,
thin monolithic, thin units, thick units, then the reverse. Every sample starts
with empty fixture cache data on its own filesystem; the same volumes are reused
across the two passes. All use the same experimental binary (opt-in disabled for
monolithic controls), **1 CPU, 768 MiB runtime memory, 4 GiB cache budget and
13 GiB aggregate virtual size**. The separate same-node client has 2 CPUs/2 GiB.
The shared-XFS control uses an isolated directory on the node's existing XFS
`data` LV; encrypted controls use real thick or thin LVs on the same VG/NVMe.

| Measurement | Shared XFS | Thick LUKS/XFS | Thin LUKS/XFS | Two thick units | Two thin units |
| --- | ---: | ---: | ---: | ---: | ---: |
| Upload/eviction churn, MiB/s | 163.25–163.70 | 160.80–161.80 | 157.22–160.60 | 158.69–160.47 | 160.19–161.26 |
| 16 KiB PUT p95, ms | 28.93–32.99 | 27.34–31.91 | 35.20–36.18 | 30.18–31.72 | 35.77–38.37 |
| 4 MiB PUT p95, ms | 260.56–279.10 | 246.41–256.94 | 261.38–273.27 | 263.35–270.26 | 248.73–273.34 |
| 1 GiB checksum reads, MiB/s | 463.83–479.74 | 469.62–497.65 | 519.54–523.52 | 482.85–509.63 | 502.35–506.27 |
| Runtime CPU seconds, ordinary run | 42.33–42.36 | 42.26–42.56 | 42.38–42.96 | 42.53–42.84 | 42.28–42.40 |

At sample midpoints, thin units are **1.7% below shared XFS** for upload/eviction
churn, versus **2.4% for thick units** and **2.8% for monolithic thin storage**.
The thin-vs-thick unit difference is under 1%; two samples do not establish a
throughput winner. The large thin-unit penalty from loop-backed VMs did not
reproduce in this one-CPU hosted workload. Runtime cgroup CPU stayed similar.

In the October 28 build, the notable latency cost was small uploads: thin-unit 16 KiB PUT p95 was
**35.77–38.37 ms**, versus **28.93–32.99 ms** on shared XFS (about **6.1 ms** at
midpoints). Thick-unit small PUT latency overlapped the shared baseline. Large
PUT p95 and checksum-read results do not show the same slowdown in these samples.
These measurements describe requests to a bounded cache fixture, not whole-build
speed or a promise of zero regression.

The 1 GiB checksum read set exceeds the configured runtime memory limit, but it
is not a fully cold-disk test; global caches were not dropped on the shared host.
Runtime CPU counters exclude some host crypto work. Whole-host CPU counters were
also retained, but include the load generator and unrelated services. The earlier
direct-I/O/QD32 regressions remain separate evidence and are not overturned by a
one-CPU HTTP workload. No regional density, memory savings, hit-rate or general
high-concurrency performance claim follows from this test.

Thin units now have real child-lifecycle/key integration and close cache-workload
performance on the intended hardware. Thick units remain a credible simpler
physical-backing alternative; this comparison does not justify selecting thin
for speed. Both options must retain whole-device backing until deletion. The
experiment supports the base-plus-units safety model; it does not release the
experimental runtime format or remove the versioned base-size/mount-contract
choice before enrollment. See the updated sharing-compatibility review.

Raw report SHA-256: `e117e55f0c0712e509a4b31e9155b10d9b2bae3545109a20507272a58090d90a`.
Child lifecycle evidence SHA-256:
`1d6a2842522e4573c9187f498a0daec207ca5d7adff8f898b83221dd5a14117b`.

## Staging teardown and restoration

Normal Pod/PVC/CSI deletion removed all five benchmark PVs, including the
non-empty child of the final parent. The final pool observation was healthy with
**zero mapped data and zero committed bytes**. Removing the empty test pool also
removed its metadata spare; the VG contains only its original `data` LV and has
exactly its original **812,541,542,400 free bytes** again. Plain fixture contents
were removed; its empty host directory remains. No forced/lazy unmount was used.

The original CSI image/template/RollingUpdate strategy is restored and all three
node plugins are ready. Both non-Paris pod UIDs remained unchanged. Both synthetic
accounts, ownership rows and key rows were deleted; the key inventory reported
zero remaining OpenBao rows. The isolated key endpoint, TLS/auth Secrets, OpenBao
StatefulSet, all three persistent claims/PVs, Services and ConfigMaps were removed.
The three OpenBao PVs used `Retain`; each was verified Released with its exact
claim UID gone before changing only those PVs to `Delete`. All three PVs are now
absent. [Cleanup run 40753215580](https://github.com/tuist/tuist/actions/runs/40753215580)
removed the fixture StorageClass and TokenReview identity/RBAC through the normal
staging deployment lane. Private test unseal shares, root token and TLS private
keys were destroyed after resource teardown. Only dedicated fixture image tags
and non-secret measurement artifacts remain; production was not changed.

## Recovery follow-up and second matched comparison

[Run 40736770879](https://github.com/tuist/tuist/actions/runs/40736770879), source
`74f0000d4dd5eb982c8bf896b2ec93862cb0ad33`, passed in **761.85 seconds** with
**94 assertions**, **30,400 comparison requests**, zero reported failures and
verified cleanup. It includes all child API checks described below plus:

- A capacity-denied create can be cancelled after CSI reconstruction; its
  cryptographic identity remains retired and the parent can grant another unit.
- Seven children plus their parent fill the eight-device profile. A ninth device
  is refused without increasing commitments. All eight filesystems received
  2,048 scattered 4 KiB writes at 512 KiB spacing, deliberately amplifying thin
  allocation relative to quota usage.
- The full snapshot retained **9,294,577,664 mapped bytes** (8.66 GiB),
  **17,186,816 metadata bytes** (16.39 MiB) and **22,011,707,392 committed bytes**
  (20.5 GiB). Checksums survived CSI reconstruction. Normal parent deletion,
  without an allocator-side drain, removed all eight detached devices and
  returned commitments to zero.

The second VM repeated the same five-layout forward/reverse comparison with
13 GiB aggregate virtual size. Do not combine its absolute throughput with the
first VM's values; the shared baseline differs substantially between VMs.

| Measurement | Shared XFS | Thick LUKS/XFS | Thin LUKS/XFS | Two thick units | Two thin units |
| --- | ---: | ---: | ---: | ---: | ---: |
| 6 GiB upload churn, MiB/s | 241.54–242.20 | 241.41–242.31 | 165.65–166.71 | 241.54–241.99 | 165.28–166.86 |
| 4 MiB PUT p95, ms | 199.10–233.62 | 192.28–203.62 | 297.82–301.98 | 197.30–199.87 | 293.72–293.92 |
| 1 GiB checksum reads, MiB/s | 341.57–359.45 | 351.92–353.04 | 356.76–361.83 | 341.02–344.24 | 340.30–350.42 |
| Runtime CPU seconds, ordinary run | 18.71–19.06 | 19.26–19.33 | 19.37–19.58 | 19.27–19.33 | 19.68–19.83 |

Thick units overlap the shared baseline in this VM; thin units are approximately
31% below thick units during upload churn. This strengthens the case for measuring
thick units on the intended hardware before choosing thin provisioning. It is
still a loop-backed mechanism/application experiment, not a staging NVMe result.

A subsequent code review found an additional interruption point: a mount can
succeed before quota setup persists its staging path. Recovery now resolves the
CSI-owned deterministic child path instead of treating an empty record field as
proof of no mount. A targeted real-stack rerun injects this quota failure and
checks cancellation only credits backing after verified detach/delete. That
follow-up passed in [40741254572](https://github.com/tuist/tuist/actions/runs/40741254572),
source `d6ec6223007`, in **110.38 seconds**: **71 assertions**, zero failures,
verified container and backing cleanup. It deliberately skipped benchmarks;
performance numbers above still refer to the earlier matched run.

## Configured device-count and cold-pool recovery qualification

[Run 40739087937](https://github.com/tuist/tuist/actions/runs/40739087937), source
`c96dedee9e1fa059d79f850a5d44c2597dda4a43`, passed in **1,569.31 seconds** with
12 aggregate assertions and verified cleanup. It used a private 384 GiB thin
pool, 512 MiB metadata and 128 fully backed 256 MiB useful-cache devices. Each
received 64 scattered 4 KiB writes at 8 MiB spacing. A 129th device was refused
despite spare data commitment; an injected metadata-reserve crossing withdrew
healthy admission and refused further allocation.

All 128 closed mappings and the deactivated pool recovered their LV identities
and file checksums after cold pool activation. The cold activation/restaging
phase took **91.99 seconds**. The full snapshot charged **15,569,256,448 mapped
bytes**, **17,575,936 metadata bytes**, and **352,187,318,272 committed bytes**.
Normal deletion returned data usage and commitments to zero; the empty pool
retained its normal metadata baseline. This does not test a fully mapped 384 GiB
pool, worst-case fragmentation, physical power loss or a Kubernetes node reboot.

A full mounted observation took **22.55 seconds** at 128 devices in this VM.
That is a scalability limitation: the current implementation invokes host tools
per device while holding its pool lock. Do not infer low-latency allocation or
suitable pressure-control cadence from the passing metadata/recovery checks.
The staging fixture uses an eight-device profile; production scale needs an
explicit observation/operation latency budget and qualification against it.
Source `170e555be89` avoids reactivating already-active LVs during accounting
(the kernel status query does not need device-node repair). Inactive volumes
still activate normally; missing status fails closed. Local Go tests and vet
passed. [Run 40744420814](https://github.com/tuist/tuist/actions/runs/40744420814)
passed **14 assertions** and verified cleanup in **308.17 seconds**. Full
observations took **1.79 seconds** and post-recovery observations **1.65 seconds**,
both within the new five-second gate. Cold activation/restaging took **56.71
seconds**. The complete 128-device recovery, identity, checksum, pressure and
deletion checks passed again. The child-lifecycle follow-up
[40745223600](https://github.com/tuist/tuist/actions/runs/40745223600) passed
**71 assertions** in **142.95 seconds**, with verified cleanup and no repeated
benchmarks.
The before/after runs used different hosted VMs, so timing is evidence for the
explicit budget, not an isolated hardware-controlled speedup measurement.

## Child API and matched thick/thin comparison — October 28

[Run 40733165768](https://github.com/tuist/tuist/actions/runs/40733165768), source
`ce0cb6914e9e6cd0ac43629428e88b376b2035b7`, passed the patched runtime's Clippy/build
and the actual CSI/LUKS/XFS stack test in **1,052.90 seconds**. All **65 assertions**
passed. Ten comparison samples made **30,400 authenticated HTTP requests**, with
zero reported failures. The report contains no failure, all fixture containers
were removed, and the driver log confirms `BORROWED_CLEANUP_COMPLETE=true`.

Unlike the earlier fixture, this run uses the actual fenced `POST /v1/units`
implementation and durable parent/child identities. CSI owns control-file writes,
encryption, child publication and deletion. It passed hot publication into a
running runtime, response replay without duplicate allocation, stale-generation
rejection, closing/reopening parent and child mappings with stable LV identities,
replacement-pod fencing, checksum recovery, open-unlinked-reader release refusal,
CSI reconstruction during incomplete release, exact retry after close, prevention
of released-ID reuse, and transfer to another tenant's independently keyed child.
Both base identities survived and final commitment returned to zero. The restart
is reconstruction of the driver object plus real mapping close/reopen, not a
kubelet, containerd or node reboot. Keys remain fixture-derived: this run does not
qualify Kubernetes ownership or OpenBao integration.

All five layouts now have **13 GiB aggregate virtual size**, the same experimental
runtime binary, 4 GiB cache budget, one CPU, 768 MiB memory, and the same forward/
reverse workload. Multiple-volume layouts use two 6.5 GiB devices. Thin layouts
retain the existing project-quota/sizing profile; thick controls use the real
legacy thick CSI path without project quotas. This compares deployable storage
paths, not encryption in isolation or identical enforcement configurations.

| Measurement | Shared XFS | Thick LUKS/XFS | Thin LUKS/XFS | Two thick units | Two thin units |
| --- | ---: | ---: | ---: | ---: | ---: |
| 6 GiB upload churn, MiB/s | 109.70–125.23 | 113.98–114.50 | 86.26–90.91 | 107.97–108.28 | 83.66–89.60 |
| 16 KiB PUT p95, ms | 7.07–7.41 | 8.00–8.31 | 7.43–8.97 | 7.74–8.71 | 8.18–8.55 |
| 4 MiB PUT p95, ms | 359.31–385.60 | 306.14–315.19 | 512.40–524.44 | 451.70–468.98 | 613.05–643.27 |
| 1 GiB checksum reads, MiB/s | 432.29–434.70 | 433.30–433.92 | 427.37–428.02 | 435.89–437.11 | 424.52–429.43 |
| Runtime CPU seconds, ordinary run | 16.00–16.56 | 16.41–16.43 | 16.55–16.85 | 16.51–16.71 | 16.62–17.06 |

Churn means upload throughput while filling beyond the cache budget and evicting;
it is not download throughput or whole-build duration. At sample midpoints,
thin units are about **20% slower than thick units**, while thick units are about
**8% below shared XFS**. Shared-XFS throughput varied substantially between its
two samples. These loop-backed VM results justify retaining the thick-unit option;
they do not select a production winner or establish hosted performance, memory
cost, hit rate or regional density. Paris NVMe measurements are still required.

Follow-up source `74f0000d4dd5eb982c8bf896b2ec93862cb0ad33` adds cancellation of
unadvertised failed creates, detached-child cleanup on parent deletion, durable
unstage completion, recovery-record validation and an enforced seven-child limit.
Local driver tests, Linux compilation and `go vet` passed. Its separate VM run
also passed eight-device scattered-write/recovery qualification, recorded above.
The configured 128-device metadata profile passed the separate qualification below.
Do not infer these newer checks passed from run 40733165768.

The child key-authorization tests passed locally: **35 ExUnit tests** across the
issuance controller and key management, including separate child keys, sealed AAD,
explicit parent opt-in, live PVC UID replacement and malformed identities. They
use mocked Kubernetes/HTTP dependencies and do not replace the staging test.

Staging-only StorageClass and TokenReview reviewer identity prerequisites were
installed by [40737753180](https://github.com/tuist/tuist/actions/runs/40737753180).
The prior attempt [40737492748](https://github.com/tuist/tuist/actions/runs/40737492748)
selected the wrong GitHub deployment environment and failed before resource apply.
The corrected workflow uses the existing `server-k8s-staging` environment and
normal deployment lane. No hosted application image or enrollment changed.
Server/CSI images were built as downloadable artifacts in
[40734563091](https://github.com/tuist/tuist/actions/runs/40734563091); local fixture
runtime/CSI images were subsequently published under dedicated `kura-child-fixture-*`
tags after explicit user approval. The alternate host-containerd socket importer
was rejected and was not used. Native amd64 server release boot passed in
[40740703970](https://github.com/tuist/tuist/actions/runs/40740703970); this is not
full web-server readiness. An isolated three-voter OpenBao fixture and compiled
key endpoint and matched hardware comparison passed the staging sequence
recorded above. Cleanup/restoration evidence is recorded alongside it.

## Earlier fixture-only prototype (historical evidence)

## Method

The harness calls the actual CSI driver against its own private loop-backed VG,
with a 24 GiB thin data pool, 512 MiB metadata, 512 KiB chunks, 256 MiB data
reserve, 32 MiB metadata reserve and eight device slots. Each fixture volume has
a distinct derived key and runs LUKS2 + XFS with the current CSI sizing profile.
The key service is a test double; OpenBao and Kubernetes authorization are not
qualified by these runs.

Two instances each have a 4 GiB useful floor and a 16 GiB logical ceiling. A
borrowed unit adds 4 GiB useful capacity. The unchanged `Targets` function from
#14825 revision `34956ca681a3dc0dc257ee5b4d0d65814bd5f23d` chooses an 8/4 GiB
grant distribution, then a 4/8 GiB distribution when demand moves. The fixture
can back three units with its existing per-device overhead. This exercises the
target calculation, not the production `Agent`, discovery, leases or an
asynchronous allocator backend.

Logical ceilings sum to 32 GiB, but **existing virtual devices are never
physically overcommitted**. Each useful 4 GiB unit currently reserves a 6.5 GiB
virtual device. Two base volumes plus one borrowed volume reserve 19.5 GiB;
a fourth cannot fit under the 23.75 GiB usable pool budget. This deliberately
reuses the existing sizing profile, including 2 GiB workspace per device.
It is expensive at this test scale and must not be used to claim regional
capacity gains. Borrowed segment-only devices need a separately qualified sizing
profile; runtime staging workspace need not necessarily be duplicated.

Kura uses an experiment-only patch built in a disposable checkout. The patch
adds a specific borrowed-storage root to its existing I/O boundary, deterministic
segment-to-unit paths, multi-root startup recovery and targeted retirement through
normal writer barriers and eviction cleanup. Production runtime builds never
apply the patch. Containers have no capabilities and use a private shared parent
with host-to-container mount propagation. This is a necessary mounting primitive,
not a Kubernetes CSI parent/child publication implementation.

The transfer sequence retains an open descriptor after Kura unlinks its segment,
injects failed TRIM, restarts the CSI object and runtime, verifies retained data,
and requires normal unpublish/unstage/delete before credit. It also checks data
and metadata reserve refusal and two concurrent creates competing for one unit.
Reserve injection tests refusal, not filesystem recovery after actual exhaustion.

The comparison runs shared XFS / monolithic thin LUKS / multiple thin LUKS in
forward and reverse order. All use the same experimental binary (the opt-in is
disabled for the controls), one CPU, 768 MiB memory without swap, a 4 GiB cache,
the same JWT-authorized HTTP client, and a separate 1 GiB checksum-read corpus.
The ordinary workload includes 6 GiB of 4 MiB upload churn at concurrency eight,
plus small/large writes, reads and post-churn reads. Data is generated outside
timed phases. Provisioned sizes differ: the plain filesystem is 13 GiB,
monolithic thin is 10.6875 GiB (the 8 GiB useful-ceiling sizing profile), and the multi-volume
case has two devices sized for 4 GiB useful each. Therefore this is a bounded
application comparison, not equal-overhead/density or saturated-device proof.

Runtime cgroup CPU/memory/I/O counters are retained. Whole-VM CPU ticks include
the HTTP load client and host crypto workers; they are not runtime CPU alone.
There is no peer-replication workload or egress qualification. Warm reads, loop
backing and short samples do not establish cold-NVMe or production performance.

## Attempts and evidence

| Run | Source | Outcome |
| --- | --- | --- |
| [40717800708](https://github.com/tuist/tuist/actions/runs/40717800708) | `b4fdd727113` | Cancelled while the shared build runner was queued; no qualification. |
| [40718897505](https://github.com/tuist/tuist/actions/runs/40718897505) | `e7e5be1691c` | Build and Clippy passed. The base-volume workload passed; the borrowed-volume batch returned 64 HTTP 503s because its path was outside the configured storage roots. No comparison benchmarks completed. Teardown retained the backing after incomplete unmount cleanup. A missing `pipefail` incorrectly made the workflow green: this run is a failure, not evidence of a passed prototype. |
| [40721692541](https://github.com/tuist/tuist/actions/runs/40721692541) | `b7feebd2c42` | Stopped before compilation/stack tests because the selected Rust toolchain lacked rustfmt. No storage qualification. |
| [40723287535](https://github.com/tuist/tuist/actions/runs/40723287535) | `bbf3133d52b` | Passed: real-stack test, 53 assertions, six comparison samples, no reported cache failures and verified teardown. See results below. |

The corrected workflow explicitly installs rustfmt, registers only the borrowed
subtree, propagates the Go test's failure status, and independently checks the
JSON report, completed benchmarks and verified teardown marker. Cleanup retries
normal unmounts and retains backing when detachment cannot be established.

## Completed bounded qualification

Run **40723287535**, source **`bbf3133d52bf7f50edd501b1863ae92e4e1989e4`**,
passed the patched runtime's Clippy and optimized build, then the real CSI/Kura
stack test in 970.75 seconds on kernel `7.0.0-1017-azure`. All 53 assertions passed.
The six comparison samples completed **18,240 authenticated HTTP requests with
zero reported failures**, including checksum reads. Transfer-specific workloads
also passed; they are separate from that request count. The JSON report has no
`failure`, reports `containers_cleaned: true`, and the Go log ends with
`BORROWED_CLEANUP_COMPLETE=true` and `PASS`. No hosted storage was modified.

### Allocation transfer and failure containment

- The pinned #14825 `Targets` calculation moved useful grants from A/B **8/4 GiB
  to 4/8 GiB**. Both base LV identities survived, and the retained base corpus
  passed checksum reads after runtime restart. A borrowed corpus was also read
  after restart before its intentional eviction.
- Idle targeted drain completed in **0.504 s**, without an upload to force
  rotation. The held-open descriptor remained readable across unlink and runtime
  restart. Normal unmount correctly refused the busy filesystem.
- After unlink, the donor still had **1,162,870,784 mapped bytes** and the pool
  retained **19.5 GiB** of commitments. Failed TRIM, the busy unmount and a CSI
  reconstruction did not release that reservation. This is an externally held
  file descriptor, not a long-running HTTP reader or a node reboot test.
- After final close, ordinary deletion took **1.627 s**. The donor disappeared
  from authoritative inventory; total mapped data fell from **2,483,027,968** to
  **1,320,157,184 bytes**, exactly the donor's mapped allocation in this quiet
  interval. Commitments fell from **19.5 to 13 GiB**. The 6.5 GiB reservation
  released is distinct from the roughly 1.08 GiB of blocks actually mapped.
- Two concurrent creates competed for the released unit: exactly one succeeded.
  Reconstructing CSI retained that unpublished allocation's charge. Its later
  idempotent create/stage/publish took **1.927 s** (excludes the initial winning
  create). B then used **2,839,543,808 mapped bytes** on that new unit. Every
  transfer commitment was released at final cleanup.
- Injected data and metadata reserve crossings each made observations unhealthy
  and refused an actual CSI create. This qualifies refusal under the configured
  reserve checks, not actual metadata exhaustion or a worst-case device count.

### Application comparison

Two samples per layout, forward/reverse order, in the same VM:

| Measurement | Shared XFS | One thin LUKS/XFS volume | Base + borrowed thin LUKS/XFS |
| --- | ---: | ---: | ---: |
| 6 GiB upload churn, MiB/s | 96.89–98.87 | 79.99–80.24 | 73.91–74.88 |
| 16 KiB PUT p95, ms | 9.41–11.44 | 9.47–10.27 | 10.21–15.91 |
| 4 MiB PUT p95, ms | 489.69–504.38 | 598.75–730.46 | 605.15–720.29 |
| 1 GiB checksum-read corpus, MiB/s | 178.23–179.90 | 169.82–181.33 | 177.25–181.96 |
| Runtime CPU, seconds/ordinary run | 18.54–19.11 | 19.80–20.75 | 19.50–20.05 |
| Runtime cgroup peak memory, MiB | 371.79–376.97 | 372.03–388.28 | 368.78–382.02 |
| Runtime anonymous memory at ordinary-run end, MiB | 34.82–36.02 | 40.81–42.53 | 39.04–42.13 |

Churn is **client-upload throughput while cycling beyond the cache budget**:
6,144 MiB divided by the sum of 24 churn-PUT phase durations, at concurrency
eight. It is not download bandwidth or whole-build throughput. CPU and memory
cover the ordinary workload, before the separate checksum corpus. Memory peak
includes charged page cache; neither it nor final anonymous memory establishes
per-instance production overhead. Raw whole-VM CPU counters also include the
load generator and kernel workers, with no attributable idle baseline.

On sample midpoints, multiple volumes are **7.1% slower than monolithic thin
LUKS** and **24.0% slower than shared XFS** during churn. Runtime CPU is similar
to the encrypted control; reads overlap. This does **not** meet a claim of no
additional write regression. Two samples, different virtual sizes and a private
loop-backed cloud VM do not isolate the cause or predict production impact.
These absolute values must not be combined with earlier Paris staging or fscrypt
VM runs. A matched device-size comparison on the intended hardware is still
required. Smaller-capacity units may also increase eviction frequency and cache
misses during transfer; this fixture did not measure application build times or
steady-state hit-rate impact.

The run's `borrowed-stack` artifact contains raw results and the driver log;
`borrowed-runtime` contains the compiled binary and exact experimental patch.
For evidence identification, SHA-256 values are:

```
kura-borrowed-results.json  4e59ea2ae96db21436a2a7ec3095829a129b0c16a69da8f0a8ca4c67558e1548
kura-borrowed-driver.log    9502951706df680e9be298f1369faf1fe55274e5b3b95c7d4172e43f2761b729
```

Local CSI `go test ./...`, `go vet ./...`, Linux test-binary compilation, Ruby
syntax, exact patch application/rustfmt parsing, the pinned target fixture and
workflow actionlint checks also passed. A later harness-only cleanup guard checks
all private `.img` files for attached loops before removing the fixture root;
that defensive change is compiled locally, not included in the VM measurements
above. The runtime and benchmark workloads remain the measured revision.

## Interpretation and remaining decisions

Returning a complete backed unit uses deletion as the allocation boundary. This
principle also applies to **thick** LUKS/XFS units: thin provisioning is not
intrinsically required for this granularity of sharing. A matched thick-unit
control is a useful next comparison before choosing the final backend, especially
because earlier direct-I/O results found a thin random-read penalty. Do not infer
thick-unit performance from this thin prototype's application measurements.

This successful bounded prototype leaves production work: stable parent/child identity
and authorization, durable and fenced asynchronous grant operations, complete
retained-volume inventory, Kubernetes mount lifecycle, quota/overhead conversion,
unit-granularity fairness, larger device-count metadata/memory qualification, and
migration of existing monolithic volumes. OpenBao custody/recovery and staged
catch-up, destination-bound write acknowledgments and endpoint handoff remain
independent release requirements. The original single-filesystem requirement is
changed by this candidate, and that tradeoff must remain explicit.
