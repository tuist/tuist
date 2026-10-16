# Verified REAPI throughput client

A black-box client for comparing ByteStream reads and unique writes across implementations. The timed transport is identical for all servers. JSON lines separate `write_ack`, `write_available`, replica qualification, `warm_verify` and `read`; any failed operation exits nonzero and invalidates the case.

## Build and run

Use the repository's pinned Go toolchain and disable the enclosing workspace:

```sh
cd kura/test/e2e/reapi-throughput
GOWORK=off go test ./...
GOWORK=off go build -o /tmp/reapi-throughput .
GOMEMLIMIT=1400MiB /tmp/reapi-throughput \
  --target 127.0.0.1:4000 --peer 127.0.0.1:4001 \
  --instance bench --size 65536 --count 1024 --workers 32 \
  --connections 4 --read-passes 8 --seed 1234
```

Endpoints use plaintext gRPC, so run only on an isolated test network with synthetic data. Omit `--peer` for standalone measurements. The measured runner uses fresh empty storage for each topology/repetition and retains it across the eight profiles in increasing size/concurrency order. Each profile gets a fresh unique corpus and instance; results therefore include cumulative storage/cache history, not a server restart per profile. The client refuses a unique-write case unless all generated digests are initially missing. Seeds must differ between independent cases but remain identical across implementations for the same case. Data generation is outside the timed write interval.

Run the client inside the same Linux network as the servers rather than through a macOS VM forwarding proxy. Bound it with a separate 8 CPU quota, 2 GiB RAM and no swap; `GOMEMLIMIT=1400MiB` is GC guidance, not a replacement for the cgroup ceiling. Corpus payload is capped at 512 MiB, with at most 1,048,576 digest records across all rounds and 16,777,216 timed read operations per round to bound bookkeeping too. Workers are capped at 4096 and connections at 1024. Parameter checks use division rather than overflow-prone size/count products; these are software ceilings, not a guarantee that every permitted combination fits the client quota. `--rounds` generates a fresh bounded corpus each round. For multi-round runs it retains only prior digests, not prior payloads, and finally reads every accumulated digest in full on the primary and configured replicas. Provision storage for the full retention corpus; an evicted prior digest fails that qualification rather than being counted as success. RPCs have finite deadlines; `Unavailable` and `ResourceExhausted` retries honor standard RetryInfo, retain a one-second minimum, and include all retry delay and count in results. No failed operation is divided out.

## Frozen primary matrix

| Blob size | Unique blobs | Workers |
| --- | ---: | --- |
| 4 KiB | 4096 | 4 and 32 |
| 64 KiB | 1024 | 4 and 32 |
| 1 MiB | 256 | 4 and 32 |
| 8 MiB | 32 | 4 and 32 |

Each profile uses four connections, 64 KiB upload chunks, deterministic unique incompressible data and eight complete verified read passes. Run three repetitions, randomize server order, take each profile's median, then the geometric mean across eight read and eight full-availability write rates. A missing case, timeout, integrity failure, OOM or sustained monitoring failure invalidates the run. Do not substitute a smoke score or change the frozen matrix to obtain a win.

Use equal **aggregate** server envelopes: 8 CPU quota, 1536 MiB RAM and no swap. Standalone gets the whole envelope; two replicas each get 4 CPU/768 MiB. Keep anonymous data volumes on the same VM disk, remove them after each repetition, wait for actual readiness before loading, and sample resources during load and at least five seconds afterward. CPU quota equality is not CPU affinity or physical host/network/disk separation.

`write_available` starts with the write clock and ends only after all configured replicas report presence. Qualification then reads every blob in full and checks SHA256; it is not one sentinel or a cursor check. Timed reads follow a separate warm verification pass. These are **warm**, not OS-cold, measurements. Software memory bounds do not prove the client is unsaturated: report client CPU, cgroup memory, GC/OOM and sampling gaps.

## BuildBuddy local replica qualification

A distributed BuildBuddy REAPI frontend can fetch a remote node's copy, so ordinary peer REAPI readback is not proof of local replication. Instead configure:

```sh
/tmp/reapi-throughput --target node-a:1985 \
  --buildbuddy-local-peers node-a:9000,node-b:9000 \
  --instance bench --size 1048576 --count 256 --workers 32 \
  --connections 4 --read-passes 8 --seed 1234
```

The pinned codec calls each node's internal DistributedCache service bound to that node's local Pebble backend. It requires missing-all before writes, missing-zero convergence inside write availability, and full local SHA256 readback on both nodes. Shared-storage references, malformed messages, oversized/short reads and digest mismatches fail the case. The pin is BuildBuddy `88af3f322ba21a8185061c6d61dd774c9d655d68`; update and requalify the codec if that protocol changes. This additional qualification is not the timed upload/read transport.

## Source and durability disclosure

The measured reference pins were Buildbarn `6ded598f64a3a92cfae0bc7de6d33bedc660f635` and BuildBuddy `88af3f322ba21a8185061c6d61dd774c9d655d68`, built without source modifications. Record exact source revisions, runtime image IDs, toolchains, configurations, corpus seeds and raw JSON for every new comparison. BuildBuddy's full application/Pebble topology and default at-rest zstd are part of its measured configuration.

Do not conflate availability with identical crash durability. Buildbarn's periodic persistent epochs differ from Kura's segment and metadata WAL acknowledgment barriers. BuildBuddy's blob file writer defaults to sync-on-commit, but its Pebble metadata Set/Delete uses NoSync. Asynchronous Kura acknowledgment and synchronous mirrored/distributed references are not the same topology contract; report full-replica availability separately.

## Resource and evidence limits

Track memory peak **and settled** anonymous/allocator bytes, pressure tiers, refused work and transient reservations; data-volume bytes and retention; CPU seconds per unit of work; and client versus peer wire bytes. Filesystem allocated blocks and logical bytes differ. An XFS holdout produced an intermittent ~508 MiB extra allocation on one 512 MiB sealed segment while total logical segment bytes remained exactly 3 GiB on both replicas. The outlier appeared on control and candidate runs. Preserve per-file length/block inventories rather than calling it duplicate data or a leak.

Total process CPU includes corpus-generation wait, timed traffic, verification and idle/background work. BuildBuddy's two local backend readbacks differ from the other topologies' one peer readback, so whole-run CPU is not identical timed-only work. Sampling every second may miss short peaks.

The finite holdout uses sixteen fresh 384 KiB/512-worker rounds and 3 GiB unique writes per implementation, under unchanged quotas. Historical holdouts verified each round's current corpus, not all prior digests after the last round. The client now additionally requires final full-SHA256 readback of all 8192 retained digests on the primary and replicas, recording separate retained-verification phases. This extra read work belongs to qualification, not the frozen primary score. It is not perpetual load, steady-state compaction/retention, crash/restart qualification or a physical multi-host result. Compressible data, batch RPCs, OS-cold reads, independent presence workloads and production network separation remain separate qualification axes, not results of this matrix.

See [the measured comparison and design notes](../../../docs/reapi-throughput.md). Never promise an overall or fleet win without contemporaneous data demonstrating it.
