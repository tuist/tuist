# Cold remote CAS replay benchmark

This measures the client-side remote replay path affected by the incomplete-graph fix in PR #12968. The local CAS starts empty; the remote has every blob for every advertised action. It separates client overhead from remote corruption, eviction, or missing data.

## Method

- macOS, Xcode 26.5's real `libToolchainCASPlugin`, Rust 1.94.1, optimized release binaries.
- Identical fixture on the pre-fix implementation (`6963d49895`) and the production closure fix plus shared in-flight blob reads.
- Five independent samples per version and scenario, alternating version order between repetitions. Only one benchmark process runs at a time. Each sample has a fresh CAS directory and proxy.
- 128 action results, each with 41 nodes: one root, eight outputs, and four deterministic incompressible 4 KiB chunks per output. One output and its chunks are shared across actions.
- A real tonic gRPC server, preloaded from graphs created and encoded by Apple's CAS and the production publisher. No missing blobs, fault injection, or remote writes during measurement. The server implements per-key inlining, batch reads, and a valid snapshot metadata response.
- One serial resolver, 16 replay workers, and the production 16-worker materializer. Replay loads locally first, demand-fetches missing nodes, then reads every actual reference. Every action must replay all 41 nodes successfully; the incomplete-closure counter must remain zero.
- Timing starts before snapshot retrieval or the first per-key lookup and ends after every action's entire graph is replayed. The raw results also include serial resolve duration, completion after draining background work, RPC counts, blob request counts, and payload bytes.
- Latency is an added delay per RPC. Bandwidth-limited scenarios use one shared outgoing-payload budget across concurrent server responses. MiB/s means 1,048,576 bytes/s. Payload-byte counts include blob bytes and snapshot metadata, but exclude protobuf action metadata, HTTP/2 framing, and other transport overhead.

The benchmark is a remote replay workload, **not an end-to-end Xcode build**. It does not measure Kura's backing storage, replication, or admission pressure, compiler execution, output-file writing, or a full build's task dependency graph. It uses a supported uncompressed snapshot body; live kura normally wraps snapshot metadata in zstd. The eight scenarios isolate the changed client behavior without claiming a universal build-time bound.

## Results

All times below are milliseconds. Each cell reports the median and the observed minimum–maximum across five samples. Payload MB uses decimal megabytes. The complete samples are in [cold-replay-results.csv](cold-replay-results.csv).

| Scenario | Before ms (range) | Fixed ms (range) | Median change | Payload MB before → fixed |
| --- | ---: | ---: | ---: | ---: |
| inline-local | 48.88 (39.5–52.6) | 47.75 (45.4–150.4) | -2.3% | 17.25 → 17.23 |
| inline-20ms | 2952.48 (2882.3–3045.8) | 2958.51 (2942.9–3038.6) | +0.2% | 17.24 → 17.23 |
| fallback-20ms | 2936.11 (2883.9–3072.1) | 2968.81 (2932.0–3013.6) | +1.1% | 18.51 → 15.17 |
| snapshot-local | 58.14 (47.1–65.3) | 60.10 (46.2–103.9) | +3.4% | 24.88 → 20.33 |
| snapshot-20ms | 285.64 (279.2–297.3) | 285.78 (268.4–320.0) | +0.0% | 21.33 → 16.90 |
| snapshot-60ms | 787.06 (769.0–815.3) | 784.47 (705.0–788.4) | -0.3% | 21.28 → 15.74 |
| fallback-20ms-5mib | 4618.12 (4417.1–4996.0) | 3978.40 (3896.2–4626.2) | -13.9% | 18.86 → 15.17 |
| snapshot-20ms-20mib | 1141.83 (1137.5–1172.5) | 874.30 (853.6–886.8) | -23.4% | 21.83 → 16.18 |

`inline` performs per-key lookups with blobs included. `fallback` performs per-key lookups without inline blobs. `snapshot` fetches metadata once, then resolves keys locally while blobs are fetched over gRPC. `local` means loopback with no injected latency or bandwidth cap.

The latency-dominated medians were within about 1.1% of baseline. The zero-latency snapshot median increased by 1.96 ms (3.4%) for the 128-action workload; the samples also contain two larger fixed-version outliers, preserved in the ranges and raw data rather than discarded. These results do not establish zero CPU overhead.

On constrained links, sharing in-flight reads reduced transferred payload and improved replay: 13.9% faster for fallback at 5 MiB/s, and 23.4% faster for snapshots at 20 MiB/s.

### Additional loopback samples

The first comparison had two larger fixed-version outliers, so the two zero-latency scenarios were repeated 20 times per version in alternating groups of ten. Every sample still uses a fresh local CAS and proxy. These additional samples are preserved separately in [cold-replay-local-results.csv](cold-replay-local-results.csv).

| Scenario | Before median / p95 / max ms | Fixed median / p95 / max ms |
| --- | ---: | ---: |
| inline-local | 46.66 / 53.58 / 55.11 | 48.45 / 77.89 / 93.91 |
| snapshot-local | 48.33 / 57.80 / 59.44 | 48.71 / 72.25 / 105.56 |

The median increases are 1.79 ms (+3.8%) for inlined replay and 0.38 ms (+0.8%) for snapshot replay. The higher fixed-version tail also recurs in these samples. The benchmark therefore supports a small median overhead for the local CPU/storage work and clear bandwidth savings; it does not prove unchanged tail latency or unchanged end-to-end build duration. No outlier was discarded, and no cause for the tail difference is inferred from elapsed time alone.

## What the benchmark changed

The first production safety fix made a demand load complete its descendants before storing the root. Initially, its manifest repair and the background materializer could both download the same blobs. A preceding five-sample comparison measured fallback payload increasing from 19.69 MB to 30.24 MB (+54%), even though an unconstrained loopback connection mostly hid the effect on elapsed time.

The final implementation shares in-flight materialization reads by Remote identity and blob hash. Readers fetch only unclaimed blobs and reuse overlapping results. They do not hold the registry lock over network calls. Entries are removed on completion, and owners wake followers on errors or unwinding, so there is no persistent negative cache or stranded waiter. This preserves the graph-ordering fix while eliminating most duplicate transfer. Standalone single-object demand coalescing remains separate.

## Kura's responsibility and the client's responsibility

Kura's `get_action_result` checks every output blob in the manifest and returns NOT_FOUND when a required blob is absent. It also extends applicable blob lifetimes after that gate. Snapshot reconciliation removes entries with missing or unverified blobs. The CAS plugin lists every node of a value graph as an output file, so these gates cover the manifest's descendants; Kura does not need to understand Apple's internal CAS frame format to check their availability.

Those server checks are necessary. A cached snapshot is not an indefinite lease, and best-effort inlining does not deliver every blob in one response. Even a healthy server cannot ensure that the client finishes downloading, decoding, and storing all descendants before the client process exits. The client therefore still owns safe ordering of its local writes and validation of incomplete graphs left by older versions. The fix adds no remote existence probes to healthy local hits.

Relevant source: `kura/src/reapi/service.rs` (`get_action_result`, `first_evicted_output`, lifetime extension and wildcard inlining), `kura/src/reapi/snapshot.rs` (`collect_dead_snapshot_entries`, `reconcile_snapshot_index`), and `cas-plugin/src/proxy.rs` (resolve, materialization, demand repair, shared reads).

## Reproduce

From `cas-plugin/` on a Mac with Xcode installed:

```sh
cargo +1.94.1 test --locked --offline --release --lib cold_remote_replay -- --ignored --nocapture
```

`TUIST_CAS_BENCH_SAMPLES` defaults to five; use one when alternating separately built baseline and fixed binaries. `TUIST_CAS_BENCH_SCENARIO_FILTER=local` selects the two loopback scenarios. The benchmark prints one `COLD_BENCH` JSON record per sample. Copy `src/proxy_cold_replay_benchmark.rs` and its `include!` into the baseline's test module when comparing an older production implementation; the workload and measurements must remain identical between versions.
