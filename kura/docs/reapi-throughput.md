# REAPI throughput: measured evidence and limits

The [verified client](../test/e2e/reapi-throughput/README.md) compares standard ByteStream reads and unique writes with one transport. The frozen matrix spans 4 KiB, 64 KiB, 1 MiB and 8 MiB blobs at 4/32 workers, three repetitions per profile, four connections and 64 KiB upload chunks. Every byte is SHA256-verified, and replication availability is distinct from acknowledgment. This document records finite Linux ARM64 shared-VM evidence, not production or fleet qualification.

## Complete comparative result

A complete 144-case matrix used equal aggregate 8 CPU quotas, 1536 MiB RAM and no swap per topology, with a separate 8 CPU/2 GiB client. Each replica receives half the server envelope. Medians per profile are geometrically averaged; combined score covers eight read and eight availability-write rates. Rates are MiB/s; score is bytes/s.

| Topology | Write acknowledgment | Full-replica availability | Warm verified read | Combined score |
| --- | ---: | ---: | ---: | ---: |
| Kura standalone | 227.04 | 226.96 | 1451.72 | 601892623 |
| Buildbarn standalone | 925.95 | 924.59 | 912.53 | 963156409 |
| BuildBuddy standalone | 356.20 | 356.01 | 1204.18 | 686559114 |
| Kura two replicas | 163.26 | 93.25 | 1809.60 | 430732136 |
| Buildbarn two replicas | 439.45 | 374.19 | 583.06 | 489784278 |
| BuildBuddy two replicas | 173.91 | 158.04 | 1053.71 | 427896482 |

Kura is **not the overall throughput winner**. It leads geometric-mean warm reads, but trails both references on replicated writes and Buildbarn on combined score. Its 0.66% composite margin over BuildBuddy in this run is smaller than observed repeat variation, not a demonstrated reproducible lead. Standalone and replicated results must remain separate.

Measured Kura runtime image: `db3437abf59a3c019cc1629bf9e380eaaefb15b726a6a8c7c363e8a61e25846a`, the `5abff24b86` implementation including the retained descriptor, four-MiB windows and Linux nonblocking owned reads described below. It includes producer/applier IO, cooperative WAL and inactive-clean-charge mmap admission. Reference pins: Buildbarn `6ded598f64a3a92cfae0bc7de6d33bedc660f635`, BuildBuddy `88af3f322ba21a8185061c6d61dd774c9d655d68`. Both reference implementations were built unmodified using their supported Linux builds. BuildBuddy used its full application and local Pebble/distributed cache configuration with anonymous synthetic traffic, remote execution and telemetry disabled. Exact images, configurations, seeds and raw captures belong in ignored run directories and accompany any new performance claim.

## What improved Kura

The retained backfill changes target redundant copies and context switches, not weaker acknowledgment semantics:

1. Try-only busy decode/staging refusals use the existing idle 1–2-second standard RetryInfo jitter. Critical memory pressure retains the 1–10-second window; response-queue protection and admission ceilings remain unchanged.
2. One admitted 64 KiB private-spool reader window borrows synchronous IO buffers instead of tiny asynchronous per-frame copies.
3. A complete immutable-spool body's entire extent is validated against actual file length, including unread prefetch accounting. Its exact limited reader reaches the same keyed deferred segment append directly, avoiding redundant per-record temporary files and rereads. Ignored bodies are drained; EOF, order, LWW, source guards, dirty-range limits and segment-before-WAL barriers remain intact. Incomplete socket bodies never append directly.
4. Producer spool writes borrow already-owned headers/chunks into descriptor-leased positioned writes, without another Tokio file buffer or detached write. A source-isolated holdout showed a modest throughput/CPU benefit, not a precise matrix-wide percentage.
5. A foreground WAL leader gives ready commit workers one cooperative scheduler turn before capturing the pending prefix, without a fixed sleep or unsynced acknowledgment. Its isolated finite holdout had mixed/small throughput effects; whole-matrix differences remain noisy.
6. Inactive clean pages filling the raw container charge no longer deny already-resident mmap serving when pressure and the hysteretic working set are normal. The same try-only mmap byte pool, residency check, cold-file fallback, response charges and active-working-set/pressure denial remain. Foreground drop-behind still follows both reclaim arms. A verified 8 MiB/32-worker case switched from zero to 271 of 288 primary reads using mmap; this is path evidence, not a precise whole-matrix attribution.

7. Serial segment copies retain their leased persistent descriptor through completed-range synchronization and aligned cache advice. Their positioned writes already finish before returning, so the legacy close/path-advice/reopen cycle protected no detached buffer. Buffered Tokio staging helpers retain that safeguard. A multithreaded regression test verifies full patterned bytes over two dirty windows plus a ragged tail, three cache-release actions and exactly one writer open.
8. Foreground staging and dirty ranges use one 4 MiB source window plus one 4 MiB destination window, rather than a warm window up to 16 MiB and an 8 MiB drop interval. The actual synchronized ranges shrink with their charges; decoder buffers, nonblocking growth, existing retries, bandwidth shaping and durable acknowledgment remain unchanged. This trades more frequent synchronization on some uploads for fewer burst refusals. It is not a uniform latency improvement.
9. Owned segment reads on 64-bit Linux first try `preadv2(RWF_NOWAIT)` into the same admitted Vec. Cold, unsupported, interrupted or zero results reuse the allocation through the existing blocking helper; partial prefixes and real errors preserve cursor/EOF semantics. Single-chunk identity ByteStream responses use this reader, avoiding transient mapping setup on a cache hit. Non-Linux, multi-chunk and HTTP mapped eligibility remain unchanged. The filesystem-specific qualification and limitations are below.

10. Synchronously durable appends of complete staged files on Linux may use positioned `copy_file_range`, capped at each remaining four-MiB dirty window. Partial copies advance exactly; unsupported, interrupted or zero results disable the probe for that append and reuse the admitted copy buffer for positional reads and writes. The source descriptor stays leased through destination synchronization. Deferred appends retain their original reader because phase-2 synchronization outlives that local descriptor scope. Streams, framed private spools, non-Linux paths, memory charges and segment-before-WAL acknowledgment barriers are unchanged. Its later optimization-only qualification is separate from the comparative table.

The strongest isolated IO evidence is the same-backoff original 8 KiB applier control: score 251008786 and CPU 109.83 seconds, compared with the direct-spool candidate's 355905225 and 77.43 seconds in the complete comparison. One MiB full-replica availability rose from about 109–110 to 234–237 MiB/s. Removing unrelated speculative lock-stripe and unsafe staging-mmap changes did not sacrifice demonstrated gains; neither showed reproducible benefits.

Before the mmap-gate change, **optimization-only** candidate repeats reached 380550695 (`38a75bc10b` implementation), with a frozen pre-yield control at 357827508. The first mmap-gate score was 383040747, just 0.65% higher and within known noise. A subsequent complete all-topology run reached 388944532 before the window/descriptor changes. The window/descriptor version reached 402103539 in a full comparison. The Linux NOWAIT version first reached 412897298 in an optimization-only matrix, then 430732136 in the latest complete comparison. The latter two used unchanged server code yet differ by 4.32%, illustrating why these composite differences are not isolated causal estimates. Warm-read variation contributes, while replicated availability remains below both references. Same-code scores and large-write retry tails vary materially. Neither the tiny current BuildBuddy margin nor the latest source edit establishes a general ranking or precise percentage gain.

## Resources and qualification

In the complete comparison, replicated anonymous-memory peaks were Kura 412.78 MiB, Buildbarn 662.14 MiB and BuildBuddy 1245.64 MiB. Whole-run sampled server CPU was 55.94, 191.61 and 121.85 seconds. These totals include different verification work and are **not a clean timed-only CPU comparison**. BuildBuddy requires two extra direct local backend readbacks; the other replicated topologies use one peer readback plus primary warm reads.

Ordinary distributed REAPI readback can mask a missing BuildBuddy replica. The pinned verifier requires missing-all on both local backends before loading, missing-zero convergence inside write availability, then full local SHA256 reads on both nodes. Shared-storage references, malformed responses and short/oversized/corrupt data invalidate a case. No failed operation is divided out.

The historical off-matrix holdout used sixteen fresh 384 KiB/512-worker rounds, 3 GiB unique writes per implementation, full per-round current-corpus reads, unchanged quotas and bounded client memory. Those runs did not verify all prior-round digests after the last round. The published client now adds separate final primary/replica readback phases covering every accumulated digest, retaining only digest metadata rather than all payloads; new qualification must report whether those phases completed. The latest source-isolated old-gate/candidate holdout completed both 8192-object final readbacks per variant, 3 GiB on each node. Full-retention qualification adds 6 GiB read traffic per variant and is separate from primary timing. Candidate/control filesystem inventories showed exactly 3 GiB logical segment bytes per node, including during an intermittent ~508 MiB allocated-block outlier. One sealed 536739840-byte segment reported 1069875200 allocated bytes on XFS; the outlier occurred on controls too. This is consistent with speculative/preallocated extents, not extra logical artifacts or proven leakage. Retain length/block inventories and seek extent-level evidence before asserting a precise filesystem cause.

In that isolated mmap-gate holdout, old gate/candidate availability rates were 74.34/77.57 MiB/s, server CPU 46.91/44.10 seconds, anonymous peaks 622.3/638.0 MiB and five-second settled anonymous memory 198.2/273.1 MiB. Logical segment bytes remained exactly 3 GiB per node and no transient permits remained. Candidate live jemalloc allocations were lower, but one replica's allocator residency remained elevated at five seconds. This is not proof of steady-state memory improvement; longer settling and repeated offered-load qualification are still needed.

### Window and descriptor qualification

The added large-object holdout uses seven fresh rounds of 80 six-MiB objects, 480 MiB of active corpus and 3.28125 GiB retained per node. The client configures 128 workers but only 80 can be active with 80 objects; this is not evidence of 128 simultaneous large-object operations. Its unchanged 512 MiB corpus guard rejected an earlier oversized proposal before loading, rather than allowing an unbounded client. Both nodes finally SHA256-verify all 560 historical objects. The original sixteen-round 384 KiB/512-active-worker holdout still independently verifies all 8192 historical objects on both nodes.

Against a source-isolated descriptor-retaining control with the original windows, the latest large holdout measured candidate/control availability of 119.72/60.86 MiB/s, 481/723 retries, 35.58/34.30 CPU seconds, 422.2/434.8 MiB peak anonymous memory, and 53.8/51.0 MiB after thirty seconds. Both variants used 7316056 KiB of allocated data-volume space with identical retained payloads. Earlier isolated repeats also showed the burst benefit, but CPU and allocator peaks varied. The ordinary 384 KiB holdout measured 77.43/76.67 MiB/s, 44.64/44.77 CPU seconds, 662.2/669.5 MiB peaks and 93.0/93.4 MiB after thirty seconds. These remain finite shared-host observations, not steady-state guarantees.

The window-only prototype initially increased allocated volume space from about 7.316 million to 13.579 million KiB despite identical logical data. Each sealed 510 MiB candidate segment occupied about 1020 MiB. Matching Linux 7.2.5 XFS source documents that the first writable close may trim speculative EOF extents, while subsequent close/reopen cycles preserve later preallocation. Earlier closes inside six-MiB records crossed that heuristic. Reversed source-equivalent baseline controls reproduced normal allocation; retaining the persistent descriptor through advice removed the doubled-allocation effect with four-MiB windows. No truncation, hole punching or global filesystem tuning was used. Preserve allocated-block inventories, not only logical lengths, when qualifying other filesystems and workloads.

### Linux nonblocking owned-read qualification

The first optimization-only matrix reached 412897298, with 58.87 sampled server CPU seconds and a 418.56 MiB anonymous peak. The table above now covers the same candidate in a **complete all-topology comparison** at 430732136. Composite variation is substantial; this is not an isolated causal percentage.

For identity ByteStream responses fitting one existing reader chunk, 64-bit Linux now fills the admitted response Vec through `preadv2(RWF_NOWAIT)` when bytes are immediately available. Cold, unsupported, interrupted and zero results reuse that allocation through the existing blocking reader; partial results advance only their initialized prefix, and real I/O errors propagate. Multi-chunk mmap, non-Linux mapped eligibility, HTTP mapped Bytes, response charges and durability are unchanged. Simply selecting the old blocking owned reader had regressed small warm reads and was rejected first.

Separate ptrace diagnostics verified complete bytes under the same quotas, but their timings are not performance evidence. The four-KiB primary recorded 41211 `preadv2` calls, 289 errors and exactly 289 `pread64` fallbacks, with 123 startup/other `mmap` calls and no `mincore` calls. The older mapped path created one mapping/residency/unmap cycle per small read. Linux release tests cover exact range/cursor/truncation behavior, allocation reuse, overflow rejection and the real single-chunk gRPC route. The test image's overlay filesystem exercised the unsupported fallback, while the data-volume diagnostic exercised non-error NOWAIT reads. This does **not** establish a speedup on every Linux filesystem or kernel.

The same-source pre-change control and candidate completed both historical-corpus qualifiers, including every final primary/replica digest. All columns show control/candidate:

| Holdout | Availability MiB/s | Server CPU seconds | Peak anonymous MiB | Anonymous after 30s MiB | Allocated volume KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 384 KiB, 512 workers, 8192 retained objects/node | 77.35 / 78.91 | 43.94 / 41.21 | 680.1 / 577.8 | 92.3 / 86.2 | 6308696 / 6308720 |
| 6 MiB, 80 active workers, 560 retained objects/node | 112.39 / 118.67 | 32.54 / 29.04 | 425.7 / 450.1 | 55.7 / 47.2 | 7316056 / 7316056 |

A reversed-order repeat completed the same full-retention proofs. Original control/candidate availability was 77.19/75.83 MiB/s, CPU 46.30/40.90 seconds, peaks 652.6/573.2 MiB and thirty-second memory 90.7/84.9 MiB. Large-object availability was 123.00/116.09 MiB/s, CPU 36.53/28.87 seconds, peaks 468.3/386.1 MiB and thirty-second memory 54.5/45.0 MiB. Large allocated space remained identical; original allocated space differed by only 144 KiB. The lower sampled CPU/memory recurred, but availability was not uniformly faster, so do not describe a general latency improvement.

Namespace interface counters now independently capture server and client traffic. Server TX minus client RX estimates peer plus administrative TX, not exact per-flow payload: 3230989398/3231022411 bytes for the original holdout and 3529271139/3528447613 for the large one, differences below 0.03%. These finite captures show no material wire-amplification increase; they do not establish an egress improvement or replace metered production accounting. Wire framing and bandwidth shaping remain unchanged, and steady-state mixed traffic is still outstanding.

Whole-run memory, pressure/refusals, data allocation/retention, CPU and peer/client egress must all be reported, including unchanged axes. Peaks and settled values are separate. No OOM or failed verification was accepted. A hung sampler SSH process once invalidated a holdout despite successful client completion; bounded subprocess lifetimes now prevent an unbounded cleanup wait. Missing monitoring is not successful qualification.

### Complete staged-file kernel-copy qualification

After the retained runtime's baseline and all four identical-image qualifiers recovered, the sync-only kernel-copy implementation reached an **optimization-only** score of 441538133, with 53.33 sampled server CPU seconds and a 408.23 MiB anonymous peak. This is 1.68% above the unchanged-image repeat at 434226013, within known repeat variation rather than a precise causal estimate. The complete comparative table still measures the earlier implementation; do not combine this new score with its older reference rows.

All four source-isolated historical-corpus pairs completed, candidate first and retained Linux-owned-read control second. Columns below show **control/candidate**, with the same corpus, quotas, deadlines and final full-byte SHA256 verification on both nodes:

| Holdout | Availability MiB/s | Server CPU seconds | Peak anonymous MiB | Anonymous after 30s MiB | Allocated volume KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 384 KiB, 512 workers, 8192 retained objects/node | 75.73 / 81.45 | 37.70 / 38.85 | 607.4 / 605.5 | 87.0 / 85.8 | 6308848 / 6308772 |
| 6 MiB, 80 active workers, 560 retained objects/node | 114.18 / 129.02 | 26.50 / 29.00 | 415.2 / 430.0 | 41.9 / 46.9 | 7316056 / 7099060 |
| 192 KiB, 512 workers, 16384 retained objects/node | 123.84 / 114.92 | 35.77 / 37.05 | 475.4 / 489.4 | 106.9 / 111.2 | 6325848 / 6325336 |
| 768 KiB, 128 workers, 4096 retained objects/node | 160.29 / 160.67 | 31.78 / 32.14 | 642.6 / 627.0 | 62.9 / 62.5 | 6301208 / 6300192 |

This is not a uniform CPU, latency or headroom improvement. The 192 KiB pair had 4/21 write retries, while the other pairs had 4387/3527, 476/478 and 87/84 respectively. Peer-plus-administrative TX estimates remained within 0.01% for each pair. Retained bytes were identical; allocated-tail variation had already occurred with unchanged implementations, so the lower six-MiB allocation is not proof of a precise reflink saving. Reversed repeats and steady-state qualification remain necessary.

A separate full-byte diagnostic of the synchronous path observed 64 successful kernel copies totaling 256 MiB, replacing the corresponding staged-file reads and destination positioned writes without removing synchronization. Native tests/clippy and freshly compiled Linux production/test clippy pass. Linux functional cases cover explicit offsets and unchanged seek positions, outside-range sentinels, real I/O errors, short-source/tail reconciliation, a real cross-filesystem fallback, exact dirty-window release and clean reopen. Successful `copy_file_range` may copy or reflink depending on the filesystem; neither all-filesystem speedup nor crash/power-loss qualification is established.

## Runtime repeatability and recovery

Later checks used the **exact same retained runtime image** on both sides of each off-matrix pair, not different source builds. Both sides retained and SHA256-verified every historical object under unchanged quotas, admission, corpus and deadlines. One 192 KiB/512-worker pair nevertheless measured 48.37 versus 107.50 MiB/s availability and 121.25 versus 39.87 server CPU seconds. Its allocated volumes and peer traffic were nearly identical. This threefold CPU variation with identical code prevents attributing smaller differences between source candidates from a single pair. Earlier RPC and monitoring timeouts remain failed qualifications, not samples to discard from successful averages.

A bounded restart of the empty, session-owned Linux VM preserved its 16 CPUs, 12288 MiB RAM, 64 GiB virtual disk and exact image inventory. Uniform host prerequisites were checked before and after setup. An unchanged-image, optimization-only matrix then reached 434226013, with 54.42 server CPU seconds and a 409.45 MiB anonymous peak. All four same-image historical-corpus pairs completed. This is **not a new server optimization**, a causal restart-speedup estimate or a replacement for the complete comparative table above. Considerable repeat variation remained: the six-MiB pair used 42.64 versus 60.68 CPU seconds despite identical images. Physical separation and steadier runtime conditions are still required for precise attribution.

Private Linux release-test images also require fresh application compilation when sharing a Cargo target cache across source reversions. A cached build layer can restore source timestamps older than a later test artifact. Touching the application crate roots before clippy and tests, as the production Docker build already does, restored the expected retained-source test inventory. Native Bazel checks, Linux production/test clippy and retained functional cases remain mandatory; cached test output is not evidence that the current source was exercised.

## Durability and environment caveats

- Buildbarn's periodic persistent epochs differ from Kura's durable segment and metadata-WAL acknowledgment barriers. BuildBuddy syncs blob files by default, but Pebble metadata Set/Delete uses NoSync. Availability is not identical crash durability, and Kura was not weakened to match.
- The 16-vCPU VM, virtual disk, host and network are shared. Equal CPU quota is not affinity or physical isolation. Client saturation and file-cache/socket reclaim must be monitored.
- Reads are warm, not OS-cold. The matrix does not prove compressible-data, batch-RPC, independent presence, perpetual compaction/retention, crash/restart or mixed-host behavior.
- A finite verified holdout does not establish steady-state allocator behavior, fleet leadership, production throughput or an independent failure domain.

See [architecture](architecture.md) for the maintained byte/metadata ordering and resource-ownership contracts. Further improvements should begin with measured bottlenecks, not an engine replacement or copied competitor durability tradeoff.
