# ByteStream benchmark and warm upgrade verification

Measured locally on September 21, 2026, on an Apple M5 Pro with 64 gibibytes of memory and macOS kernel 27.0.0. These are single-node loopback measurements, not production network results.

## Outcome and prior decisions

No runtime optimization is retained. The last candidate increased the fixed artifact-lock array from 64 to 256 stripes. Different artifact keys collided less often, while the same key remained serialized through the existing durable commit. It improved write throughput but used more processor time per unit of work in both sustained comparisons, so it was rejected under Kura's resource policy. The branch's final runtime and dependency files match its merge base. Only documentation remains changed; there is no feature flag, detached commit queue, dependency change, storage migration, or change to response buffers.

The history was checked before evaluating or removing the experiments:

- [#11551](https://github.com/tuist/tuist/pull/11551) introduced artifact locks to prevent several peers from appending duplicate copies of the same artifact. It deliberately used a fixed array instead of an unbounded per-key map. Both decisions remain intact. The existing `concurrent_replicated_applies_of_same_key_write_once` regression test passes.
- [#11511](https://github.com/tuist/tuist/pull/11511) established segment synchronization before acknowledgment, including rotation. That ordering remains intact.
- [#12795](https://github.com/tuist/tuist/pull/12795) retained 32 positioned writers after a larger limit failed to show a repeatable benefit. Artifact stripes are not disk-writer permits; this change does not widen that limit.
- [#12009](https://github.com/tuist/tuist/pull/12009) established lifetime-bound response memory permits, and [#12719](https://github.com/tuist/tuist/pull/12719) preserved namespace guards across write checks and commits. Neither mechanism changes.

The earlier coalesced-write experiment was removed: detached commits weakened acknowledgment ordering and could accumulate pending tasks outside the queue bound. The vendored protocol, smaller response chunks, frame-size tuning, and mutex replacements were also removed. The smaller response chunks failed eight existing tests. A broader candidate improved short-run write throughput but increased processor time in two sustained comparisons, so its results are not the final performance claim.

## Compared builds

| Server | Source revision |
| --- | --- |
| Kura baseline, branch merge base | `9c5964933e750cfa82a4342f0f9f9dd7719b294e` |
| Kura evaluated candidate, subsequently rejected | `e97f1000dc` |
| Buildbarn bb-storage | `db620416646d7e96379779144a88660a5b7b0c46` |
| BuildBuddy | `f93633a8eaf173c587dc5589a90d31ce39e1a052` |

Both Kura binaries were built with Rust 1.94.1 using `cargo build --release --bin kura`. Their SHA-256 (Secure Hash Algorithm 256-bit, [specification](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)) digests are:

- Baseline: `899e55744c6920cc31c0ac296588731d368513d6c8222395cc6d7329e62bcbee`.
- Candidate: `94c3251d5516f0bb17d7f1f51b64abdc13ec27d8867e0c47a4d04fc14fc6e0f2`.

The candidate measurements below describe that explicitly rejected revision, not a performance improvement shipped by the final branch. The existing Buildbarn configuration uses an in-memory key-location map and a 300-second minimum persistence epoch. Its acknowledgment durability is not equivalent to Kura's durable segment and metadata acknowledgment.

## Throughput

The supplied `run_bench.sh` and `loadclient` were used unchanged. Each trial starts with a fresh server and data directory, performs 5,000 writes followed by 5,000 reads, and stops the server. There are 32 concurrent requests over four connections, 128-kibibyte artifacts, and 64-kibibyte upload chunks. Kura uses 64 worker threads and the harness's 512/768-mebibyte soft/hard memory settings. Five trials run sequentially for every server, alternating the order of the two Kura builds. Builds and tests do not overlap these measurements.

| Server | Median writes/second | Write range | Median write 95th percentile | Median reads/second | Read range | Median read 95th percentile |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Kura baseline | 2,202 | 2,067–2,366 | 28.381 ms | 21,382 | 19,215–23,711 | 2.605 ms |
| Kura candidate | 2,374 | 2,266–2,434 | 19.285 ms | 22,851 | 19,576–24,486 | 2.360 ms |
| Buildbarn | 24,919 | 17,872–25,590 | 2.389 ms | 28,095 | 21,636–29,399 | 2.412 ms |
| BuildBuddy | 781 | 769–787 | 128.837 ms | 30,124 | 22,187–30,502 | 2.083 ms |

All four builds completed 25,000 writes and 25,000 digest-checked reads without errors. The candidate's median write throughput is 7.8% higher and its median write 95th-percentile latency is 32.1% lower than the baseline. Its read median is 6.9% higher, but the ranges overlap substantially and no read implementation changes, so this is not evidence of a repeatable read improvement. Kura does not beat Buildbarn on either operation; both competitors have higher median read throughput.

The client's payload generator repeats after 2,048 seeds. This workload mixes new and duplicate writes, and servers can handle duplicates differently. It is not a 5,000-unique-blob ingest benchmark. Reads validate size and payload digest. Other workloads and longer runs may produce different rankings.

To repeat with the supplied local harness and a freshly built binary at its configured path:

```sh
WRITE_REQUESTS=5000 READ_REQUESTS=5000 CONCURRENCY=32 CONNECTIONS=4 \
  SIZE_KB=128 CHUNK_KB=64 BENCH_TAG=repeat bash run_bench.sh all
bash summarize.sh repeat
```

The harness remains an external local artifact. Its load-client digest is `ee387e212e445f6bb22b76cd6cf9a7a205d39253e0966cfd56317bdad95172af`. Final trial logs use the `final_` prefix.

## Resource comparison

Each build completed 40,000 writes paced at 50 milliseconds per request, then 40,000 reads paced at 10 milliseconds per request, at concurrency 32 with the same 2,048-key corpus. Writes lasted about 64 seconds and reads about 14 seconds. Metrics were sampled every half second, including 20 seconds after load stopped. Two comparisons ran sequentially, first baseline then candidate, then candidate before baseline. All 320,000 requests succeeded.

| Measurement | Baseline, runs 1 / 2 | Rejected candidate, runs 1 / 2 |
| --- | ---: | ---: |
| Processor seconds for 80,000 requests | 37.12 / 41.31 | 37.80 / 42.36 |
| Allocated heap peak, mebibytes | 52.28 / 53.92 | 54.89 / 52.00 |
| Allocated heap after idle, mebibytes | 13.35 / 13.79 | 12.83 / 12.31 |
| Allocator resident peak, mebibytes | 452.83 / 435.92 | 458.94 / 456.31 |
| Allocator resident after idle, mebibytes | 364.50 / 310.95 | 338.52 / 323.09 |
| Transient reservations, peak / after idle, mebibytes | 12.01 / 0 in both runs | 12.01 / 0 in both runs |
| Logical data-volume bytes | 5,270,443,039 / 5,270,427,267 | 5,270,382,332 / 5,270,367,792 |
| Allocated data-volume mebibytes | 5,161.14 / 5,172.90 | 5,103.27 / 5,118.77 |
| Client-received read bytes | 5,243,401,196 / 5,243,401,288 | 5,243,401,196 / 5,243,401,288 |
| Segment synchronization calls | 4,330 / 4,120 | 3,210 / 3,222 |

Processor time increased by 1.8% and 2.5% for identical completed work. Host variation also affected both builds between the pairs, so these short local runs do not establish an exact production cost. They nevertheless fail to demonstrate the non-regression required to retain a latency optimization. Resident allocator peaks were also higher in both candidate runs, although settled heap was lower and all transient reservations were released. The candidate was rejected rather than treating these costs as unchanged.

Memory and logical payload counters come from the sampled `/metrics` endpoint. Each run recorded 5,242,880,000 successful read payload bytes and 5,242,912,768 write payload bytes including warmup. No capacity shedding or admission rejection was reported. The macOS process-anonymous-memory gauge is unavailable and renders zero; it must not be interpreted as zero memory consumption or as a Linux pressure test. Allocator values above remain usable. Process time comes from `ps` because this build does not expose a process-time counter; disk sizes come from file lengths and `du` after idle. Client byte counts measure received protocol data, not link-layer overhead. There were no peers in these runs, so peer traffic was not exercised and cannot be called validated or unchanged from measurement. The passing same-key replication test checks duplicate disk appends, not network egress.

Raw resource captures use `stress-narrow-{main,branch}` and `stress-narrow-{branch,main}-2` labels in the local verification artifacts. These runs are a bounded local comparison, not a long-duration pressure soak or a complete four-axis mesh qualification.

## Warm upgrade, restart, and rollback

Using one retained data directory, the baseline wrote 2,048 artifacts of 128 kibibytes. After an orderly stop, the candidate opened that store and successfully read every artifact. The candidate then wrote 2,048 artifacts of 257 kibibytes, exercising the staged-file path above the direct-memory threshold. It was killed immediately after the writes completed, without graceful shutdown. The candidate reopened the store and read both corpora, then stopped gracefully. Finally, the baseline reopened the same store and also read both corpora. Every read checked size and digest.

All 4,096 writes and 10,240 verification reads succeeded. This verifies local persistent-store compatibility, acknowledged-write survival across a process crash, and rollback readability for the evaluated candidate. It is not a power-loss test or a live mixed-version mesh test. Storage formats, peer messages, replication code, and acknowledgment ordering were unchanged by that candidate.

## Checks and rollout limits

- `mise run clippy`: passed using Bazel.
- `mise run format -- --check`: passed using Bazel.
- `mise run test-unit -- --test_output=errors`: passed using Bazel; 1,008 library tests passed, 49 intentionally ignored, and the binary target passed.
- `git diff --check`: passed.

The release-container and Linux container-control-group tests could not run because the available Docker client has no running daemon. Production Linux pressure behavior and live mixed-version replication therefore remain unverified. There is no performance implementation to roll out in the final documentation-only branch, and the original goal of beating Buildbarn is not achieved. Keep the pull request as a draft record of the review and measurements, not as a production performance rollout recommendation.
