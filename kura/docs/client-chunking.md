# Xcode compilation-cache chunking

## Scope

This change covers the Rust Xcode compilation-cache plugin and its Kura transport. Gradle, Tuist binary/module-artifact caching, and their routes are unchanged. A Swift `.swiftmodule` produced by a cached compiler action is in scope; a prebuilt framework archive uploaded by `tuist cache` is not.

[Content-defined chunking](https://www.buildbuddy.io/blog/content-defined-chunking/) derives boundaries from bytes rather than fixed offsets. Boundaries can converge again after an insertion or deletion, allowing unchanged chunks to survive. It does not relax compiler invalidation: sources, flags, toolchains, dependencies, and action keys still determine validity. A miss still compiles; a valid remote hit can reuse local chunks while restoring its exact outputs.

Whole-stream compression can propagate a small change beyond the edited bytes. The plugin compresses independently delimited sections using concatenated [Zstandard frames](https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md), then finds transfer chunks in that compressed stream. Existing decoders read it without a new node format. This two-pass strategy is the initial compatible baseline, not a claim that every compiler format achieves good reuse.

## Compatibility and rollout

The plugin negotiates the existing [Bazel Remote Execution interface](https://github.com/bazelbuild/remote-apis), requiring split and splice support and the exact Fast content-defined chunking parameters: 2020 variant, normalization level 2, seed 0, average 512 kibibytes, minimum 128 kibibytes, maximum 2 mebibytes. Integrity uses the [256-bit Secure Hash Algorithm](https://csrc.nist.gov/pubs/fips/180-4/upd1/final), not the rolling boundary hash.

Small frames retain their original encoding without a capability request. Frames at least 2 mebibytes can negotiate independent compression. If that result is below the two-mebibyte transfer threshold, the plugin uses the original whole encoding instead: chunking cannot help that transfer, and separate compression histories can make it larger. The actual encoding choice is memoized. Missing, malformed, unknown, disabled, or failed capabilities disable the optional path. Results are endpoint/project-scoped and expire after five minutes. Unsupported methods during mixed-version deployment disable chunking for five minutes and fall back to ordinary transfers. Authorization and overload failures do not amplify into unlimited whole-blob retries.

Uploads send missing chunks, splice the ordered recipe, and publish the action result last. Xcode reuses Kura's existing recipe-aware content store: no new routes, storage categories, or peer wire format. Ordinary blob reads reconstruct the full compressed node for existing clients. Missing splice dependencies fall back to a complete whole upload. Publication memoization pins encoding alongside digest, so capability changes cannot change an already-described blob. Compression and negotiation start after releasing the local compiler-store handle.

Deploy recipe-aware readers before enabling writes, following the existing [reader-first rollout](architecture.md). This pull request does not make pre-recipe Kura binaries safe peers for recipe-only storage. The only new server behavior is the optional `tuist-inline-max-bytes:2097151` wildcard hint: small outputs remain inline, large ones wait for the client's chunk check, and explicit inline requests retain their semantics. Old servers ignore the hint safely, with less download reuse. Release the capability-aware client after readers support the existing split/splice protocol.

## Local download reuse

The exact action result is looked up first. Nodes already present in Apple's compiler store win before transfer work. For a large missing node, the proxy obtains its recipe, checks persistent chunks, downloads missing pieces, and verifies each piece and the complete compressed blob. It then uses the existing decoder and graph materializer. Corrupt, missing, or evicted chunks cannot become successful cache hits. Root-last materialization and incomplete-closure guards remain unchanged. Network reads never move onto Xcode's serial task-setup path.

Verified upload and download chunks share a disposable cache beside the proxy registry. It has 128 buckets with four slots each: at most one gibibyte of payload plus one two-mebibyte staging file. This is a maximum, not promised usable capacity: collisions and chunk sizes affect retention. Replacement evicts the oldest-written slot in a bucket. Process-shared locking, atomic replacement, and digest verification turn corruption, unwritable storage, or eviction into misses. Endpoint and full account/project handle scope slot selection. Cleaning derived data does not clear this cache; a restore still requires an authorized remote action result and recipe.

Cold readers fetch all bytes and pay for recipe requests. Smaller chunks can reduce bytes while increasing compression cost, metadata, requests, and eviction. Measure wall time and memory as well as payload. Proxy `batch_download_bytes` and `reused_chunk_bytes` describe transport work, not compilation avoided.

Background materialization and compiler-demand workers share active large-node reads against the same remote/project. Otherwise both can observe missing chunks before either finishes downloading them. The table is keyed by hash and size, capped at 128 active reads, and retains no completed-output cache. Waiters receive the same verified result; failures and worker panics wake them and release the entry for retry. Small-node batching and each caller's absence-retry policy remain unchanged. This is worker-side coordination, never a wait on Xcode's task-setup thread.

## Output-by-output investigation

Inspect the actual cached graph, not just the generated file's extension. Swift's [output backend](https://github.com/swiftlang/swift/blob/main/lib/Frontend/CASOutputBackends.cpp) has both ordinary byte outputs and a separate structured-object path. Which path an installed Xcode uses must be measured. Keep existing graph reuse before chunking large leaves.

`cas-plugin/examples/cache_output_inventory.rs` reads output identifiers from Xcode cache-hit remarks and walks their graphs through Apple's plugin. It reports each node's size, references, original/negotiated compressed sizes, transfer eligibility, and chunk digests. Printed identifiers are decoded by Apple's plugin. The probe does not upload or transform data, but reading a store can advance local generations: use only an idle disposable fixture store. Missing nodes fail the probe instead of producing a partial inventory.

| Output | Next experiment | Acceptance boundary |
| --- | --- | --- |
| Swift module | Compare body-only, public declaration, insertion, and dependency edits; investigate reversible field separation where bit-packed references destroy matches. | Exact original node and references; downstream imports pass. An already-identical module needs no new optimization. |
| Clang modules and precompiled bridging headers | Measure explicit-module and chained-header graphs; their [serialized syntax trees](https://clang.llvm.org/docs/PCHInternals.html) use related bitstreams. | Restore actual Xcode actions and compile consumers; a monolithic Foundation header is only exploratory. |
| Objects and debug information | Determine structured versus opaque outputs. For opaque nodes, compare section boundaries. | Preserve graph reuse, relocation offsets, debug content, and exact bytes. |
| Swift dependency and source-information files | Measure independently from ordinary dependency lists; investigate record separation. | Preserve dependency semantics and source locations; account for cold compression as well as warm reuse. |
| Documentation, generated headers, diagnostics, ordinary dependency lists, constant values | Check sizes and whole-node identity first. | Keep small outputs inline and whole. No parser overhead without a measured benefit. |

The first inventory on Xcode 26.5 / Swift 6.3.3, using the generated 16,000-struct fixture, found single opaque nodes for the Swift module (116,953,696 raw bytes), object (216,667,696), Swift dependencies (13,290,892), and source information (21,888,128). All four exceeded the compressed transfer threshold. Two imported Clang module nodes compressed to 83,151 and 19,565 bytes. Other outputs ranged from empty diagnostics to a 12,793-byte generated header and stayed whole. A generated C fixture also used one opaque object node, but its dependency output had two nodes. These observations apply to these fixtures, not all Xcode projects.

Earlier isolated research on three historical ProjectDescription public edits found that reversible bitstream-field separation followed by a dictionary patch reduced payload by 63.7–85.2% compared with whole compression. A monolithic precompiled Foundation-header probe reduced it by 85.6%. **These are experimental codec measurements, not this implementation's chunking results.** Those prototypes are not enabled or shipped here. The real ProjectDescription modules compressed below the production threshold. Native inverse-transform timings excluded base preparation, disk access, networking, and final verification.

An experimental codec needs a separate capability, tenant-scoped digest-pinned base selection, bounded memory/work, no unbounded patch chains, missing-base fallback, corrupt-input tests, and exact reconstruction of the compressed transport identity. Restoring just a module is insufficient: the blob digest covers its compressed frame and graph references. Do not redefine the existing chunk capability to mean a field transform or patch.

The [eight-run automated search](../../cas-plugin/autoresearch.md) compared raw compression sizes, compression strength, and object-section resets across ten output pairs, holding transfer parameters fixed and checking exact reconstruction. Smaller raw frames were not consistently better. Section resets reduced warm payload by 24.1% for the C object and 0.98% for the Swift object, or 1.17% across the corpus. That candidate remains research-only; the production encoder is unchanged. The offline overlap model includes estimated recipe-entry overhead but not local eviction, network scheduling, or a representative customer distribution.

## Validation and benchmarks

From `kura/`:

```sh
mise exec -- bazel build //:kura
mise exec -- bazel test //:kura_lib_test --test_filter=inline --test_output=errors
mise run clippy
python3 test/e2e/chunking_fixtures.py
python3 test/e2e/swift_chunking_fixtures.py
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

### Actual Xcode action restores

Build the release plugin and inventory example first. `swift_chunking_fixtures.py --sources-only --types 4000` generates two `source_revisions` without standalone compilation. The smaller fixture still has chunk-eligible modules and objects, but is cheaper to compile in debug mode. From the repository root:

```sh
python3 kura/test/e2e/xcode_chunking_check.py --source /path/to/revision-0.swift --edited-source /path/to/revision-1.swift --url http://127.0.0.1:18765
```

The driver creates an isolated project and proxy registries, compiles the base, captures a local-hit inventory, restores into an empty compiler store, restarts the reader retaining transfer chunks, and repeats after the edit. Source and derived-data paths stay identical. Writers and readers have separate transfer caches. Every remote-restore task must hit; twelve output files (including module, object, Swift dependencies, source information, documentation, headers, and diagnostics) must match their compiled bytes. It waits for post-build transport counters and asserts the restarted reader reuses chunks and downloads less. Stores move aside only after their proxy stops; evidence remains in the printed temporary folder. Inventory chunk overlap is potential reuse, not measured traffic after bounded-cache eviction.

The first 4,000-struct inventory exposed unnecessary compression growth: the edited Swift dependency node grew from 1,165,671 to 1,272,457 bytes with separate compression histories, but was still too small for chunk transfers. The whole-encoding fallback removes that 9.2% growth. Its source-information output likewise stays on the original encoding. This decision follows compressed output size, not extension, so other highly compressible compiler outputs benefit without a format parser. Trying independent compression before making this decision costs extra encoding work; that remains a tradeoff to measure.

The final 4,000-struct run passed all seven build phases. The initial build had zero of four hits; the edited compilation reused two imported-module actions while recompiling its two changed Swift actions. Both base restores and the edited restore hit all four actions, with all twelve checked files byte-identical to their respective compiled originals. Eight of those files were also unchanged across the property rename; the module, object, Swift dependencies, and source information changed.

The edited output inventories give the next optimization priorities. Matching bytes below are overlap with the base's chunks, before cache eviction or request scheduling, not separate network measurements:

| Changed output | Selected compressed bytes | Matching base chunk bytes | Decision |
| --- | ---: | ---: | --- |
| Swift module | 6,177,929 | 203,049 (3.3%) | Prioritize field-aware experiments; ordinary chunking has little reuse here. |
| Swift object | 12,075,727 | 1,155,259 (9.6%) | Investigate object sections while preserving exact bytes. |
| Swift dependencies | 1,165,674 | Not chunked | Keep original compression below the transfer threshold. |
| Source information | 1,249,947 | Not chunked | Keep original compression below the transfer threshold. |

| Empty-store restore | Batch payload downloaded | Locally reused chunk bytes |
| --- | ---: | ---: |
| Base, cold reader | 18,351,285 | 0 |
| Base, restarted reader retaining chunks | 452 | 18,350,047 |
| Edited revision, reader retaining base chunks | 16,896,156 | 1,358,308 |

These final counters include shared active downloads. Before that change, a previous run of the same generated fixture downloaded 36,700,750 bytes cold and 33,791,724 after the edit: background and demand workers fetched the large nodes twice. The new runs roughly halve those batch payloads. The isolated wire test pins the mechanism exactly: two readers of one 3,145,728-byte node went from 6,291,456 transferred bytes and two split requests to 3,145,728 bytes and one split request.

These are aggregate proxy counters, not unique logical-output sizes, and sequential reads can still repeat work. They exclude inline outputs, action metadata, and recipe metadata. Fresh fixture paths can change compressed output sizes slightly. The unchanged restore is not a cross-revision benchmark. The edited run's modest chunk similarity reinforces why each output needs measuring; the large standalone-module benchmark is not representative of every Swift action. The final cold, restarted, and edited restores took 2.730, 2.415, and 2.518 seconds respectively, single loopback observations with no demonstrated build-speed improvement.

A fresh 16,000-struct debug integration build exceeded the harness's five-minute limit during its initial compilation. The 4,000-struct integration fixture retains chunk-eligible objects/modules and completes reliably; the larger corpus remains useful for standalone transfer measurements. Kura's 906 unit tests and strict Clippy check passed. The plugin's normal tests passed; an additional unsuppressed Clippy invocation stopped at two pre-existing raw-pointer safety diagnostics in `llcas_get_plugin_version`. With only that existing lint allowed on the command line, the inventory example check passed. No lint suppression was added to source.
