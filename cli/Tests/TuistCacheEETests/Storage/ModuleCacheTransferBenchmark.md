# Module cache transfer benchmark

`ModuleCacheTransferBenchmark.compareTransfers` compares the previous modern module-cache path (`CacheStorage` + `CacheLocalStorage` + `ModuleCacheRemoteStorage`, AppleArchive/LZFSE over HTTP) with `BinaryCacheStorage` + `REAPICacheClient`. Both clients use the same dedicated Kura node and the same prebuilt XCFrameworks. This is a storage-path benchmark, not a compilation or complete `tuist cache`/`tuist generate` benchmark.

The test is disabled unless `TUIST_MODULE_CACHE_BENCHMARK_CONFIG` points to a JSON configuration. Use disposable local Kura storage or an isolated hosted benchmark project, with a cache credential restricted to those projects (pre-exchanged when supported). The benchmark creates remote records and does not delete them. It does not require server changes or a privileged metrics endpoint.

```json
{
  "endpoint": "http://127.0.0.1:8099",
  "metricsURL": "http://127.0.0.1:8099/metrics",
  "token": "LOCAL_BENCHMARK_TOKEN",
  "account": "transfer-bench",
  "inputs": "/absolute/path/to/corpora",
  "output": "/absolute/path/to/results",
  "repetitions": 3
}
```

Each immediate subdirectory of `inputs` is a corpus of XCFrameworks. Each framework must contain iOS device, iOS simulator, and macOS slices using standard architectures. Artifact basenames become target names. Authorize projects named `<corpus>-<zero-based repetition>-archive` and `<corpus>-<zero-based repetition>-reapi` under the configured account, or set `project` to use one existing benchmark project. Action keys include a fresh invocation UUID (overridable with `runID`), corpus, and repetition. The two protocols have separate remote record formats.

For a deployed Kura node, set `endpoint` to its resolved HTTPS cache URL, `authenticationURL` to the Tuist server URL, and `project` to the isolated project handle. TLS follows the endpoint scheme. Both clients receive the same credential outside the timed phases. An existing project token can be used when the deployed server does not support cache-token exchange. Omit `metricsURL`: production timings do not require scraping server metrics, and absent counters mean unavailable, not zero bytes transferred. Confirm deployed capabilities before treating the node as supporting the optimized compression paths.

Fresh action keys alone do not make CAS content cold. Set `independentRepetitionInputs` to `true` and arrange artifacts as `inputs/<corpus>/<zero-based repetition>/*.xcframework` to use distinct content per sample. The generator below prepares 100-module and large-artifact workloads with distinct payload bytes for every invocation, repetition, module, and SDK:

```sh
python3 cli/Tests/TuistCacheEETests/Storage/generate-module-cache-benchmark.py \
  --fixtures /absolute/path/to/compiled-three-sdk-fixtures \
  --output /absolute/path/to/new-benchmark-directory
```

The output includes `inputs` and a provenance manifest. Three corpora exercise 100 modules with 1 MiB per SDK, four modules with 32 MiB per SDK and 50% random payloads, and four modules with 32 MiB per SDK and 100% random payloads. Existing compiled fixture bytes remain shared; the dominant synthetic payload is unique. These are transfer scaling and compression sensitivity workloads, not 100 independently compiled production libraries. Report them as such. Archive pulls and REAPI pulls use the same artifacts and endpoint; the first remote upload populates each sample, so subsequent pulls measure a warm remote service with an empty local cache, not cold backing-object-store latency.

Generate the narrow workspace:

```sh
tuist generate TuistREAPI TuistCacheEE TuistCacheEETests --no-open
```

Then run only the benchmark, with optimized code and the mock types needed by the test harness:

```sh
TEST_RUNNER_TUIST_MODULE_CACHE_BENCHMARK_CONFIG=/absolute/path/to/config.json \
TUIST_MODULE_CACHE_BENCHMARK_CONFIG=/absolute/path/to/config.json \
xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace \
  -destination 'platform=macOS' -configuration Release -jobs 2 \
  -only-testing:TuistCacheEETests/ModuleCacheTransferBenchmark \
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG MOCKING' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  COMPILATION_CACHE_ENABLE_CACHING=NO
```

The benchmark alternates which implementation runs first and uses a separate remote project per corpus/repetition/implementation. Every phase gets an empty local cache directory:

- **cold-push:** store the complete corpus into an empty remote project, including local caching, archive packing or REAPI slicing/hashing, and publication.
- **existing-push:** store the same corpus from another empty local cache after the server has all content. This deliberately calls storage directly; it does not model the CLI's earlier cache-hit short circuit.
- **cold-pull:** fetch all three SDKs into an empty local cache, including verification, decompression or local XCFramework reconstruction.
- **ios-pull:** fetch only the iOS SDKs with REAPI. The archive baseline retrieves the complete original archive using its original exact key. That is the archive model's best-case transfer cost; it does not claim the old model can hit after a graph change that changes that key.

Timing excludes capability/token setup, metrics scraping, input compilation, post-transfer verification, and cleanup. After each pull, the harness checks declared SDK coverage and SHA-256/size equality for every expected regular file, excluding the regenerated top-level Info.plist. It writes each completed measurement to `results.json` and prints `TRANSFER_BENCHMARK` lines.

When a counting proxy exposes `tuist_benchmark_wire_upload_bytes_total` and `tuist_benchmark_wire_download_bytes_total` through `/metrics`, the JSON also records those deltas. These include HTTP/gRPC framing and exclude metrics requests. Kura's stored-byte counters remain uncompressed CAS sizes even when wire compression is enabled.

The JSON retains Kura's request counters, stored-payload byte counters, read-payload byte counters, and egress counters when exposed by that server version. These are application payload/storage measurements, not Ethernet/TLS/gRPC framing totals. In particular, older Kura versions count batched REAPI reads in `kura_artifact_read_bytes_total` without incrementing the egress counter. Compare those read bytes explicitly rather than interpreting a missing egress counter as zero transfer.

Report the machine, client optimization settings, Kura version/hash, corpus composition/size, repetition count, and medians/ranges. Loopback results with warm OS page caches do not establish WAN performance. Repeated copies of the same frameworks exaggerate cross-target deduplication; synthetic resources do not represent typical Mach-O compressibility. Keep such datasets labeled separately from real artifacts.

## Before compression and transfer optimizations (2026-09-17)

On an Apple M3 Pro with 36 GiB RAM, macOS 26.3, and Xcode 27.0 / Swift 6.4, all 72 measured phases passed, including restored-file verification. Both storage implementations were rebuilt together with Release optimization (`-O`) and test/mocking support. Swift 6.4 crashed while optimizing the unrelated `IssueReporting` test dependency; only that generated dependency target was compiled with `-Onone`. Cache, archive, hashing, crypto, and networking code remained optimized. No source workaround for the compiler crash is part of the PR.

Both models used the same authenticated, native local Kura 0.8.0 executable (SHA-256 `b43072c1f707c3a9ba0abafb1a0db38515fbc7ef2f1317b44cbe3d9c21e2de11`) with fresh project namespaces. This reused the native server binary from the prior local validation; it is not a new server build from this PR head. The existing archive implementation in the current checkout is the baseline; a separate historical CLI executable was not built. The timed calls are the real storage APIs, with production signing, hashing, compression, verification, and network transports, using a supplied local JWT and isolated cache directories.

Corpora:

- **Small:** two real prebuilt Leaf/Shared XCFrameworks from the multiplatform fixture, each containing device, simulator, and macOS outputs; 426,078 regular-file bytes. These are tiny example libraries, not production-scale binaries.
- **Many:** 20 renamed copies of those two frameworks; 4,260,780 bytes. This is a synthetic module-count/deduplication case with deliberately repeated binary content, not 20 distinct libraries.
- **Large:** the two real frameworks plus 4 MiB of distinct synthetic resource bytes per SDK (half deterministic pseudorandom, half zeros) and 64 JSON resources per SDK; 26,519,202 bytes. This exercises large-blob streaming and a few hundred files, with explicitly artificial compressibility.

Times below are median seconds over three repetitions, with min–max in parentheses. Every phase has a fresh local cache; repeat push retains remote content. Model order alternates across repetitions.

| Corpus | Phase | Archive | REAPI |
|---|---|---:|---:|
| small | cold-push | 0.132 (0.114–0.145) | 0.891 (0.580–0.950) |
| small | existing-push | 0.086 (0.080–0.098) | 0.315 (0.304–0.341) |
| small | cold-pull | 0.027 (0.027–0.028) | 0.135 (0.134–0.150) |
| small | ios-pull | 0.027 (0.026–0.029) | 0.130 (0.117–0.166) |
| many | cold-push | 1.017 (0.843–1.070) | 3.593 (3.503–4.580) |
| many | existing-push | 0.903 (0.726–0.995) | 3.056 (2.474–3.060) |
| many | cold-pull | 0.279 (0.183–0.390) | 1.144 (1.115–1.270) |
| many | ios-pull | 0.271 (0.189–0.313) | 0.773 (0.744–0.971) |
| large | cold-push | 0.354 (0.332–0.354) | 1.108 (1.099–1.196) |
| large | existing-push | 0.258 (0.250–0.285) | 0.595 (0.589–0.693) |
| large | cold-pull | 0.085 (0.082–0.089) | 0.263 (0.261–0.267) |
| large | ios-pull | 0.082 (0.077–0.096) | 0.187 (0.183–0.303) |

Cold-push stored-payload counters and iOS-pull read-payload counters (MiB, medians):

| Corpus | Archive push | REAPI push | Archive iOS pull | REAPI iOS pull |
|---|---:|---:|---:|---:|
| small | 0.042 | 0.371 | 0.042 | 0.257 |
| many | 0.421 | 0.397 | 0.421 | 0.315 |
| large | 12.260 | 24.554 | 12.260 | 16.452 |

Both implementations wrote **zero new payload bytes** on every existing-push phase. REAPI still republishes action records; neither zero new payload bytes nor CAS deduplication means zero requests. The iOS REAPI reader fetched four actions for the two-framework corpus or 40 for the 20-framework corpus, instead of six or 60 for all SDKs.

**Interpretation of the initial run:** the initial implementation fixes SDK compatibility and enables content reuse, but it is not a transfer-performance improvement in these measurements. REAPI loses to archives on every measured wall-clock case. The byte difference reflects the old path's LZFSE compression versus the then-uncompressed REAPI blobs; repeated-content deduplication helps the many-module corpus, while even an iOS-only REAPI read remains larger than the complete compressed archive for the small and large corpora. The loopback timing also includes additional per-file staging, hashing, local CAS writes, signing, and reconstruction. This run does not isolate each operation's contribution; attributing the entire timing gap to any one of them would require profiling.

This initial run motivated the compression and local-processing follow-up below. These results do not change the need for per-SDK keys to support workspace narrowing. A bandwidth/latency-constrained WAN, cold OS caches, large real production libraries, and a complete CLI invocation remain unmeasured.

Raw local evidence: `/private/tmp/module-cache-transfer-optimized2/results.json`, `provenance.json`, `tests.log`, and `final.metrics`. The run completed in 76.17 seconds of test time (527.58 seconds including the optimized dependency build). The earlier debug pilot is excluded from the tables.


## Final compressed implementation (2026-09-17)

All 72 phases passed against a freshly built, authenticated local Kura server, including verification of every restored regular file and SDK coverage. Six REAPI client test functions and two local-action tests passed before profiling. After the profile-driven fixes, 10 targeted tests across the client, directory, and local-repair suites passed in 4.840 seconds. Formatting, implicit dependency inspection, and whitespace checks passed. No full test or acceptance suite was rerun for this follow-up.

The client is a locally built Release (`-O`) test executable invoking the real storage implementations. Swift 6.4 crashes while optimizing the unrelated IssueReporting test dependency, so only that generated dependency target uses `-Onone`; cache, archive, crypto, and networking code remain optimized. The server was built with `cargo build --release` from this worktree; its SHA-256 is `8bb737b46a9c3aef2a23a84964b37195509f61d2084f6f2535176e8b964439fa`. The old temporary server and fixture artifacts were no longer available, so this run rebuilt both. The new corpora contain 435,854, 4,358,540, and 26,528,978 regular-file bytes for small, many, and large respectively. Small contains two real Leaf/Shared fixture XCFrameworks with three SDKs each. Many contains 20 renamed copies of those two artifacts, deliberately exaggerating cross-target deduplication. Large adds 4 MiB of distinct synthetic resources per SDK (half deterministic pseudorandom bytes, half zeros) and 64 JSON resources per SDK. The new numbers must not be treated as a perfectly controlled comparison against the earlier server/fixture binaries.

Both models in this final comparison use the same server and a loopback counting proxy. Wire-byte counters measure TCP payload bytes, including HTTP/HTTP2/gRPC framing, excluding metrics requests; there is no TLS. Capability/token setup remains outside timing. Three repetitions alternate model order, and every phase starts with an empty local cache. Other build/indexing activity was observed on the workstation, so report the ranges and treat these as workstation measurements, not isolated lab or WAN results.

Median seconds (min–max):

| Corpus | Phase | Archive/LZFSE | REAPI/zstd |
|---|---|---:|---:|
| small | cold-push | 0.149 (0.141–0.150) | 0.549 (0.547–0.647) |
| small | existing-push | 0.082 (0.081–0.083) | 0.187 (0.186–0.224) |
| small | cold-pull | 0.028 (0.027–0.029) | 0.110 (0.109–0.110) |
| small | ios-pull | 0.027 (0.027–0.028) | 0.078 (0.078–0.098) |
| many | cold-push | 0.874 (0.860–0.883) | 2.664 (2.660–2.900) |
| many | existing-push | 0.677 (0.676–0.694) | 1.496 (1.486–1.521) |
| many | cold-pull | 0.199 (0.183–0.205) | 0.792 (0.790–0.806) |
| many | ios-pull | 0.193 (0.172–0.246) | 0.581 (0.575–0.588) |
| large | cold-push | 0.330 (0.322–0.372) | 0.870 (0.859–0.908) |
| large | existing-push | 0.269 (0.265–0.274) | 0.496 (0.477–0.534) |
| large | cold-pull | 0.100 (0.097–0.111) | 0.226 (0.222–0.267) |
| large | ios-pull | 0.104 (0.102–0.104) | 0.171 (0.170–0.189) |

Median wire bytes (upload direction for cold push, download direction for pulls):

| Corpus | Phase | Archive/LZFSE | REAPI/zstd |
|---|---|---:|---:|
| small | cold-push | 59,600 | 190,247 |
| small | cold-pull | 45,936 | 169,225 |
| small | ios-pull | 45,936 | 107,755 |
| many | cold-push | 595,936 | 256,467 |
| many | cold-pull | 459,346 | 175,489 |
| many | ios-pull | 459,346 | 111,954 |
| large | cold-push | 12,872,313 | 12,916,912 |
| large | cold-pull | 12,858,653 | 12,878,445 |
| large | ios-pull | 12,858,653 | 8,605,725 |

Both models wrote zero new server payload bytes on every repeat push. REAPI cold pushes used one FindMissingBlobs call per corpus, including the large streaming corpus, instead of tying lookup count to payload batches. The large corpus's complete compressed REAPI pull is about the same transfer size as the complete archive; its iOS-only pull is about one third smaller. Repeated content makes the many-module corpus substantially smaller with CAS. The tiny corpus still transfers more with REAPI: compression happens per blob, with additional action/Tree/protocol metadata, whereas an archive can compress repeated content across files.

A separate 15-second CPU sample of the optimized many-module run captured staging copies, FileSystem's atomic-write full-sync path, SHA-256 hexadecimal formatting through Foundation, and SwiftECC signing/key construction. The sample mixes storage phases and verification and is not a per-phase percentage attribution. It identified two concrete changes: temporary slice plists and empty streamed-download files no longer force full disk syncs, and digest formatting/validation now operate on ASCII bytes instead of per-byte Foundation formatting and character searches. FileSystem remains the abstraction for supported filesystem operations; its current high-level write API has no durability option, so these private staging writes use the existing low-level binary/streaming path. Plist replacement stays atomic and failed downloads are removed.

REAPI also negotiates zstd for streaming and batch uploads, accepts compressed batch reads, hashes while streaming to avoid rereading downloads, batches missing-blob lookups by metadata count, fills transfer slots as they become available, and avoids reading/signing SDK action records a second time during the same warm operation. The encoding follows standard REAPI compressor fields and `compressed-blobs/zstd` resource names; content digests and server storage identities remain uncompressed.

**Remaining limitation:** REAPI is still slower than the archive baseline on loopback in every final measured case. Compression and the profiled fixes improve the implementation but do not make this rollout performance-neutral. The remaining local staging/materialization, filesystem metadata, signatures, and per-SDK action work are visible costs. The two SDK models also solve different reuse cases: the archive iOS baseline uses the original exact key and downloads the complete artifact. Do not interpret that baseline as evidence that old exact-target keys can satisfy a narrowed incoming graph. That loopback run did not measure WAN performance. The production measurements below address that gap; cold OS page caches, real production-library corpora, and complete CLI invocation times remain unmeasured.


## Production transfer measurements (2026-09-18)

The same locally built Release client measured both storage paths against the existing production endpoint `https://tuist-eu-west-1.kura.tuist.dev`, using the isolated `tuist/reapi-bench-20260918` project. No server changes or deployments were made. A deployed GetCapabilities probe advertised SHA-256, action-cache updates, zstd streaming, and zstd batch uploads. Production did not expose `/api/cache/token` (404), so both paths used the same project-only credential through the existing credential fallback. The credential was revoked after measurement. Server binary/version was not pinned; these results describe the deployed endpoint at the time of the run.

All **72 measured phases passed**, including SDK coverage and SHA-256/size verification of every restored regular file outside the timed region. No full suite or acceptance suite was rerun. An initial account-token run was stopped before its short-lived credential could expire and is excluded from these results. The final run used fresh generated payloads and fresh action keys. The client source was `dd727f4df8`; the machine, Release optimization, and narrow IssueReporting compiler workaround match the earlier local measurements. This invokes the real storage implementations, not complete CLI command execution.

Each corpus has three repetitions, with model order alternating. Every phase starts with an empty local cache. Cold push uses fresh keys and distinct dominant payload bytes per repetition, module, and SDK. Existing push retains the remote content from that sample. Pulls follow upload, so remote contents are warm; this does not measure a cold backing object store. Compiled fixture bytes remain shared. Both models include local staging, signing, hashing, compression, network transfer, and materialization; credential setup, capability negotiation, verification, and cleanup are outside timing.

The corpora remain synthetic scaling/compression workloads around real compiled three-SDK frameworks:

| Corpus | Modules | Regular-file bytes | Files | Generated payload |
|---|---:|---:|---:|---|
| many-mixed | 100 | 339,437,220 | 8,400 | 1 MiB per SDK, half random/half zero |
| large-mixed | 4 | 403,647,780 | 336 | 32 MiB per SDK, half random/half zero |
| large-incompressible | 4 | 403,649,508 | 336 | 32 MiB per SDK, all random |

Median seconds (min–max), including local storage work:

| Corpus | Phase | Archive/LZFSE | REAPI/zstd |
|---|---|---:|---:|
| many-mixed | cold-push | 34.80 (34.71–42.82) | 49.90 (48.64–49.97) |
| many-mixed | existing-push | 5.61 (5.38–6.07) | 16.31 (15.63–16.56) |
| many-mixed | cold-pull | 3.58 (3.33–9.15) | 14.91 (14.88–15.04) |
| many-mixed | ios-pull | 3.32 (3.18–3.55) | 9.76 (9.65–10.07) |
| large-mixed | cold-push | 47.86 (33.42–77.97) | 48.71 (41.94–75.17) |
| large-mixed | existing-push | 0.69 (0.67–0.98) | 1.41 (1.41–1.66) |
| large-mixed | cold-pull | 4.24 (4.13–4.58) | 4.74 (4.27–4.97) |
| large-mixed | ios-pull | 4.67 (4.18–5.09) | 2.91 (2.81–3.57) |
| large-incompressible | cold-push | 121.40 (76.47–142.56) | 75.91 (64.20–84.48) |
| large-incompressible | existing-push | 1.03 (0.95–1.19) | 3.84 (1.59–4.45) |
| large-incompressible | cold-pull | 9.69 (8.25–10.85) | 9.81 (8.64–20.99) |
| large-incompressible | ios-pull | 8.69 (8.01–10.32) | 6.13 (5.76–7.07) |

The archive iOS-pull baseline uses the original exact key and downloads the entire three-SDK archive. REAPI fetches only the two iOS SDKs. This comparison quantifies the narrower transfer, not compatibility of old exact-target keys with a narrowed graph. Production metrics and wire-byte counters were not collected; empty counter maps mean unavailable. Artifact sizes above are uncompressed source bytes, not network throughput measurements. This is one workstation/network path, with three samples and no controlled WAN latency/bandwidth, remote load, or cold OS page caches. It is not a benchmark of 100 independently compiled production libraries or complete CLI invocation times.

**Interpretation:** this production run does not reproduce a universal REAPI slowdown, but it also does not establish a performance-neutral switch. For four large frameworks, median full restores were close: 4.24 → 4.74 seconds for mixed data and 9.69 → 9.81 seconds for incompressible data (archive → REAPI). Restoring just iOS improved by 38% and 29%, respectively. Large mixed-data uploads were about equal; incompressible uploads favored REAPI in this run, but upload ranges were wide and the network/server load was uncontrolled.

The 100-module workload remains a substantial regression: median cold push increased from 34.80 to 49.90 seconds, full restore from 3.58 to 14.91 seconds (4.2×), and iOS-only restore from 3.32 to 9.76 seconds (2.9×). Repeat push was slower with REAPI in every corpus. The implementation still needs work on many-module overhead before claiming general performance parity. These end-to-end storage timings do not isolate RPC latency, local per-file publication, signing, or materialization; the earlier local profile identifies candidates, not a production attribution.

The [raw measurements and corpus provenance](ModuleCacheTransferBenchmark.production-2026-09-18.json) retain all 72 unrounded phase timings and the deployed capability response; credentials are excluded.
