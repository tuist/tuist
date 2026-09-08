# Xcode compilation-cache chunking

## Scope

This change covers the Rust Xcode compilation-cache plugin and its Kura transport. Gradle, Tuist binary/module-artifact caching, and their routes are unchanged. A Swift `.swiftmodule` produced by a cached compiler action is in scope; a prebuilt framework archive uploaded by `tuist cache` is not.

Content-defined chunking derives boundaries from bytes rather than fixed offsets. Boundaries can converge again after an insertion or deletion, allowing unchanged chunks to survive. It does not relax compiler invalidation: sources, flags, toolchains, dependencies, and action keys still determine validity. A miss still compiles; a valid remote hit can reuse local chunks while restoring its exact outputs.

Whole-stream compression can propagate a small change beyond the edited bytes. The plugin compresses independently delimited sections using concatenated [Zstandard frames](https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md), then finds transfer chunks in that compressed stream. Existing decoders read it without a new node format. This two-pass strategy is the initial compatible baseline, not a claim that every compiler format achieves good reuse.

## Compatibility and rollout

The plugin negotiates the existing [Bazel Remote Execution interface](https://github.com/bazelbuild/remote-apis), requiring split and splice support and the exact Fast content-defined chunking parameters: 2020 variant, normalization level 2, seed 0, average 512 kibibytes, minimum 128 kibibytes, maximum 2 mebibytes. Integrity uses the [256-bit Secure Hash Algorithm](https://csrc.nist.gov/pubs/fips/180-4/upd1/final), not the rolling boundary hash.

Small frames retain their original encoding without a capability request. Frames at least 2 mebibytes can negotiate independent compression. If that result is below the two-mebibyte transfer threshold, the plugin uses the original whole encoding instead: chunking cannot help that transfer, and separate compression histories can make it larger. The actual encoding choice is memoized. Missing, malformed, unknown, disabled, or failed capabilities disable the optional path. Results are endpoint/project-scoped and expire after five minutes. Unsupported methods during mixed-version deployment disable chunking for five minutes and fall back to ordinary transfers. Authorization and overload failures do not amplify into unlimited whole-blob retries.

Uploads send missing chunks, splice the ordered recipe, and publish the action result last. Xcode reuses Kura's existing recipe-aware content store: no new routes, storage categories, or peer wire format. Ordinary blob reads reconstruct the full compressed node for existing clients. Missing splice dependencies fall back to a complete whole upload. Publication memoization pins encoding alongside digest, so capability changes cannot change an already-described blob. Compression and negotiation start after releasing the local compiler-store handle.

Deploy recipe-aware readers before enabling writes, following the existing [reader-first rollout](architecture.md). This pull request does not make pre-recipe Kura binaries safe peers for recipe-only storage. The only new server behavior is the optional `tuist-inline-max-bytes:2097151` wildcard hint: small outputs remain inline, large ones wait for the client's chunk check, and explicit inline requests retain their semantics. Old servers ignore the hint safely, with less download reuse. Release the capability-aware client after readers support the existing split/splice protocol.

## Local download reuse

The exact action result is looked up first. Nodes already present in Apple's compiler store win before transfer work. For a large missing node, the proxy obtains its recipe, checks persistent chunks, downloads missing pieces, and verifies each piece and the complete compressed blob. It then uses the existing decoder and graph materializer. Corrupt, missing, or evicted chunks cannot become successful cache hits. Root-last materialization and incomplete-closure guards remain unchanged. Network reads never move onto Xcode's serial task-setup path.

Overloaded chunk reads share the original blob's bounded retry budget and retain verified pieces between attempts. Persistent pressure engages the existing fail-fast backoff. Authorization failures stop the read, and omitted or unexpected response digests are rejected. Terminal storage errors stay per-blob, leaving independent successful outputs available. These failures do not trigger whole-blob downloads; that fallback is reserved for missing, corrupt, or unsupported chunk representations.

Verified upload and download chunks share a disposable cache beside the proxy registry. It has 128 buckets with four slots each: at most one gibibyte of payload plus one two-mebibyte staging file. This is a maximum, not promised usable capacity: collisions and chunk sizes affect retention. Replacement evicts the oldest-written slot in a bucket. Process-shared locking, atomic replacement, and digest verification turn corruption, unwritable storage, or eviction into misses. Endpoint and full account/project handle scope slot selection. Cleaning derived data does not clear this cache; a restore still requires an authorized remote action result and recipe.

The capacity and per-insert write lock are deliberately shared across projects. This trades cross-project cache competition and short write contention for a machine-wide disk bound; each insertion releases the lock before the next chunk. The capability probe likewise shares one bounded request per remote instead of letting simultaneous workers send duplicate probes. These are throughput tradeoffs, not additional isolation or latency guarantees.

Cold readers fetch all bytes and pay for recipe requests. Smaller chunks can reduce bytes while increasing compression cost, metadata, requests, and eviction. Measure wall time and memory as well as payload. Proxy `batch_download_bytes` and `reused_chunk_bytes` describe transport work, not compilation avoided.

Background materialization and compiler-demand workers share active large-node reads against the same remote/project. Otherwise both can observe missing chunks before either finishes downloading them. The table is keyed by hash and size, capped at 128 active reads, and retains no completed-output cache. Waiters receive the same verified result; failures and worker panics wake them and release the entry for retry. Small-node batching and each caller's absence-retry policy remain unchanged. This is worker-side coordination, never a wait on Xcode's task-setup thread.

Each read reserves its batch's large digests together and completes the reads it owns before waiting for another batch. Split requests run with at most eight in flight; the batch's missing chunks and small outputs share one size-bounded read. Publication similarly pools chunk presence and uploads before issuing up to eight splices concurrently. Extra working storage is limited to a normal 32-mebibyte batch or one oversized output, rather than expanding the whole closure at once. Split-request overload uses the parent blob's retry budget and preserves independently successful outputs; it never triggers a larger whole-blob fallback.

## Output-by-output investigation

Inspect the actual cached graph, not just the generated file's extension. Swift's [output backend](https://github.com/swiftlang/swift/blob/main/lib/Frontend/CASOutputBackends.cpp) has both ordinary byte outputs and a separate structured-object path. Which path an installed Xcode uses must be measured. Keep existing graph reuse before chunking large leaves.

`cas-plugin/examples/cache_output_inventory.rs` reads output identifiers from Xcode cache-hit remarks and walks their graphs through Apple's plugin. It reports each node's size, references, original/negotiated compressed sizes, transfer eligibility, and chunk digests. Printed identifiers are decoded by Apple's plugin. The probe does not upload or transform data, but reading a store can advance local generations: use only an idle disposable fixture store. Missing nodes fail the probe instead of producing a partial inventory.

A generated 16,000-struct inventory on Xcode 26.5 / Swift 6.3.3 found single opaque nodes for the Swift module, object, Swift dependencies, and source information. All four exceeded the compressed transfer threshold. Two imported Clang module nodes compressed to 83,151 and 19,565 bytes; the remaining outputs stayed small and whole. A generated C fixture also used one opaque object node. These observations apply to these fixtures, not all Xcode projects.

## Validation and benchmarks

From `kura/`:

```sh
mise exec -- bazel build //:kura
mise exec -- bazel test //:kura_lib_test --test_filter=inline --test_output=errors
mise run clippy
```

Run local Kura with `KURA_REAPI_BLOB_CHUNKING_ENABLED=true`. From `cas-plugin/`, export `TUIST_CHUNKING_TEST_URL=http://127.0.0.1:18765` and optional colon-separated compiled artifact paths as `TUIST_CHUNKING_ARTIFACTS`:

```sh
mise exec -- cargo test --lib --test chunking_negotiation --test batch_read_backpressure --test publish_write_backpressure
mise exec -- cargo test --release --test content_defined_chunking -- --include-ignored --nocapture
mise exec -- cargo build --release --example cache_output_inventory
mise exec -- cargo test --example cache_output_inventory
```

Live tests verify edited uploads, legacy whole reads, action lookups, persistent reuse across readers, and corrupt-local-chunk repair. Negotiation tests exercise disabled, unknown, old, and mixed-version services plus malformed recipes/chunks over a real wire. These are not a full old-binary fleet rollout test.

### Transfer payloads, rerun 2026-09-08

Apple M5 Pro, 64 gibibytes memory, Xcode 26.5 / Swift 6.3.3, optimized Kura and release Rust client, loopback. Edited revisions follow seeded bases. Readers restart between revisions, retaining only bounded transfer chunks. Headers and recipe metadata are excluded. Generated workloads are not customer benchmarks.

| Edited output | Previous whole compressed bytes | Uploaded / downloaded chunk bytes | Reduction |
| --- | ---: | ---: | ---: |
| Eight-mebibyte corpus, twelve-byte insertion | 8,388,829 | 579,770 | 93.1% |
| Generated C object, one function edit | 3,801,739 | 2,001,189 | 47.4% |
| Generated Swift module, one property rename | 25,148,875 | 18,163,443 | 27.8% |

Independent compression made the edited Swift blob 25,256,947 bytes; 7,093,504 were reused. Both revisions still compiled. The C pair was freshly generated with both revisions compiled at the same input path; it reproduced the original pair's payload sizes.

Observed edited download times were 48, 28, and 190 milliseconds respectively. These are single loopback observations including verification and storage, not controlled speed comparisons against the old client. Upload timings exclude compression. Do not infer build acceleration.

### Batched transfers under latency

Three sequential before/after pairs used the same release-mode wire harness on loopback. Every split and read request incurred 300 milliseconds of simulated server latency; every presence, upload, and splice request incurred 100 milliseconds for the upload case. Capabilities were warmed before timing. These isolate transfer scheduling, not compiler time or a real wide-area network.

| Workload | Serial chunk path, median | Batched chunk path, median | Request shape |
| --- | ---: | ---: | --- |
| Four three-mebibyte downloads | 2,798 ms | 1,075 ms | Four splits overlap instead of serializing; four chunk reads become one. |
| Six three-mebibyte uploads | 2,305 ms | 858 ms | Six presence checks and six uploads become one each; six splices overlap. |

The batched client's whole-output cold-read baseline was 324 milliseconds. Cold chunk reads remain slower because they need recipes, chunk verification, and local storage; this change removes serial amplification, not the inherent cold-path overhead. A separate ten-output test verifies that split and splice concurrency never exceeds eight. Overlapping-reader, overload, terminal-error, and mixed-version tests run independently of timing assertions.

Reproduce current measurements from `cas-plugin/` with:

```sh
mise exec -- cargo test --release --test chunking_negotiation large_reads_pool_missing_chunks_and_overlap_split_requests -- --exact --nocapture
mise exec -- cargo test --release --test chunking_negotiation large_uploads_pool_presence_and_updates_before_overlapping_splices -- --exact --nocapture
```

The serial baseline used the pre-fix client at `94455e7378` with the same regression harness; its request-count assertions fail as expected. Individual download samples were 2,864 / 2,798 / 2,755 milliseconds before and 1,075 / 1,141 / 882 after. Upload samples were 2,312 / 2,305 / 2,204 before and 856 / 1,220 / 858 after. Host scheduling contributes noise, so the request counts are the primary regression check.

### Actual Xcode action restores

Build the release plugin and proxy first. On an Apple silicon Mac with Xcode 26, start local Kura with chunking enabled, then run from `kura/`:

```sh
KURA_E2E_XCODE=1 TUIST_CHUNKING_TEST_URL=http://127.0.0.1:18765 mise exec -- shellspec spec/e2e/xcode_chunking_spec.sh --format documentation
```

The suite generates a 4,000-struct Swift fixture from the readable assets in `spec/fixtures/xcode-chunking/`. It compiles the base and a single-property rename at the same source and derived-data paths, then independently tests cold restoration, a restarted reader retaining chunks, and cross-revision reuse. Each remote restore must hit every cacheable action and reproduce twelve output files byte-for-byte. It checks positive reuse and reduced downloads after restart, using post-build transport counters. Writers and readers have separate transfer caches. The suite stops its proxies and retains its isolated directory of compiler stores and logs for inspection.

The suite is skipped unless explicitly enabled on a supported Mac. It does not start or stop the Kura server, change launch agents, or modify a developer's existing compiler cache. The standalone artifact payloads above are historical fixture measurements; regenerating fixture names changes the corpus and can change compressed byte counts.

The ShellSpec run on 2026-09-08 passed all three examples in 173.04 seconds, including fixture compilation and waiting for transport statistics. The initial build had zero of four hits; the property rename reused two imported-module actions and recompiled the two Swift actions. All five subsequent restores hit all four actions and reproduced twelve output files byte-for-byte.

| Empty-store restore | Batch payload downloaded | Locally reused chunk bytes |
| --- | ---: | ---: |
| Base, cold reader | 18,291,636 | 0 |
| Base, restarted reader retaining chunks | 226 | 18,291,636 |
| Property rename, reader retaining base chunks | 16,133,629 | 2,200,883 |

Each scenario uses an independent reader cache. The restart scenario seeds its own cache with 18,293,100 downloaded bytes; the edit scenario seeds another with 18,293,100. Small-output request timing can change aggregate counters slightly. The unchanged restore demonstrates reuse after cleanup, not reuse across edits. The property rename achieves much less reuse than the standalone large-module fixture.

Counters exclude inline outputs, action metadata, and recipe metadata, and are not build-time measurements. A fresh source or derived-data path can change compressed sizes. The suite asserts correctness, cache hits, positive reuse, and reduced restarted-reader downloads rather than pinning byte counts to one machine.

The selected compression also keeps smaller compiler outputs efficient: in the previous fixture, independent compression grew a Swift dependency node from 1,165,671 to 1,272,457 bytes while remaining below the transfer threshold. Retaining its original encoding avoids that 9.2% growth. This size-based decision applies to any output without a format-specific parser.

Kura's strict Clippy check passed. The plugin tests passed; its Clippy check still reports existing warnings, including raw-pointer safety diagnostics in `llcas_get_plugin_version`. Allowing only that existing lint on the command line permits the check to complete; no source suppression was added.
