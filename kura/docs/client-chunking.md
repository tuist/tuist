# Negotiated client chunking

## What this optimizes

[Content-defined chunking](https://www.buildbuddy.io/blog/content-defined-chunking/) finds boundaries from the bytes rather than fixed offsets. After an insertion or deletion, boundaries can converge again and unchanged chunks can be reused. This does not make a stale build action valid: compiler flags, source dependencies, toolchains, and task keys still invalidate exactly as before. It reduces the data a resulting miss needs to upload.

Compression is an equally important boundary. A whole-file compression history can turn a local edit into different bytes far beyond the edit. Xcode and Gradle therefore compress independently delimited sections before finding the transfer chunks. The result remains an ordinary concatenated Zstandard or gzip stream, readable by existing decoders. Module archives keep their original bytes and metadata; the client skips monolithic compressed archives because there is little opportunity for reuse. It accepts archives with multiple substantial entries, or a large uncompressed entry, and conservatively leaves extended or unfamiliar archive layouts on the existing uploader.

## Implementation and compatibility

All clients implement Fast content-defined chunking, 2020 variant, normalization level 2, seed 0, with a 512 kibibyte average, 128 kibibyte minimum and 2 mebibyte maximum. Shared deterministic test vectors pin the Rust, Swift, and Kotlin implementations. Content integrity uses the [256-bit Secure Hash Algorithm](https://csrc.nist.gov/pubs/fips/180-4/upd1/final), not the rolling boundary hash.

| Client | Negotiation | Publication | Existing readers |
| --- | --- | --- | --- |
| Xcode Rust plugin | Existing `GetCapabilities`, exact supported parameters and split/splice flags | Upload missing chunks, then existing `SpliceBlob` | Existing logical-blob reads reconstruct the recipe; existing Zstandard decoder reads concatenated frames |
| Module cache | Versioned `/api/cache/chunks/capabilities` | Upload missing chunks, then complete an ordinary artifact | Existing multipart uploads, downloads, archive contents, and ranges are unchanged |
| Gradle | Same versioned capability | Independently compressed gzip members, missing chunks, ordinary artifact completion | Both the Tuist loader and Gradle's built-in remote-cache reader unpack it |

Uploads below 2 mebibytes use the original path without a capability request. Missing, malformed, failed, or unknown capabilities disable the optional path. Capability results are scoped to the endpoint/project and expire after five minutes. Handshakes have short transport deadlines. Unsupported methods during a rolling deployment disable chunk writes for five minutes and fall back to a whole upload. Missing chunks during completion retry presence once for module/Gradle, then fall back; Xcode falls back directly on a splice dependency miss. Overload and authorization failures are not turned into unlimited full-upload retries.

Xcode retains the chosen encoding in its publication memo: recomputing a memoized node must reproduce the digest even if capabilities change. Compression starts only after releasing the local compiler-store handle. No compilation-cache keys, compiler graph edges, or action-result semantics change.

Gradle only spools its writer after successful negotiation and uses the same staged bytes for legacy fallback, so a mixed-version node does not invoke the writer twice. Gzip normalization is bounded to 2 gibibytes of unpacked content and abandoned if the compressed result would exceed the existing 100 mebibyte upload limit or grow more than 5 percent. Module archive inspection and transfer scanning are bounded and do not extract files.

## Additive upload protocol

Every route takes the existing tenant/project parameters (including the account/project handle aliases); writes additionally require `kind=module` or `kind=gradle`.

- `GET /api/cache/chunks/capabilities`: version 1 and exact algorithm, size, normalization, seed, and count limits.
- `POST /api/cache/chunks/missing`: `{ "chunks": [{ "hash": "...", "size": 123 }] }`, returning `{ "missing": [...] }`.
- `PUT /api/cache/chunks/upload`: digest and size in query parameters, raw chunk bytes in the body.
- `POST /api/cache/chunks/complete`: `{ "blob": { "hash": "...", "size": 456 }, "chunks": [...] }`, plus the normal module target parameters or Gradle `cache_key`.

Capability reads require read access. Presence, upload, and completion require write access to that project. Chunks are isolated by tenant, project, and artifact producer. Missing metadata cannot query a different project's chunks. Uploads validate every chunk's digest and size; completion validates the ordered aggregate before publishing anything at the ordinary target key. Missing or corrupt chunks return conflict, never a partial successful artifact.

Metadata bodies are capped at 2 mebibytes and 16,384 digests. Chunk bodies are capped at 2 mebibytes. Completion retains the existing 100 mebibyte Gradle / 2 gibibyte module artifact limits, reserves temporary-disk capacity, uses the shared memory admission budget and bounded file readers, and streams reconstruction through a 64 kibibyte buffer. Temporary output is removed on success, failure, or cancellation. Usage is recorded once for the completed logical artifact, not once per auxiliary chunk.

## Storage tradeoff and rollout

Xcode reuses the existing recipe-only content store. Module and Gradle store auxiliary `transfer_chunks/v1/{hash}/{size}` artifacts **and** an ordinary full artifact. This deliberately avoids changing the on-disk representation or peer replication messages during a mixed-version deployment. An old peer can replicate and serve the completed artifact without understanding chunking. Auxiliary chunks use existing retention, eviction, and project cleanup, including chunks left by abandoned uploads.

This first module/Gradle version saves client upload bandwidth, not download bandwidth or storage. Cold uploads can roughly double physical storage and replication traffic. A changed artifact still writes a complete server-side copy. Do not infer storage or build-time improvements from upload-byte measurements.

Rollout sequence:

1. Deploy the additive server routes; existing clients are unchanged. For Xcode, retain the existing reader-first rollout described in `architecture.md` for recipe-aware nodes.
2. Release capability-aware clients to a small cohort. Compare upload bytes, upload duration, outbox depth, replication traffic, physical writes, eviction rate, and hit rate. Keep small and monolithic compressed module artifacts on their existing path.
3. Expand only when network savings justify the extra module/Gradle storage and compression work. Server rollback leaves whole artifacts readable; clients that meet missing routes fall back.
4. A later, separately negotiated version may use recipe-only module/Gradle storage and chunk-aware downloads. That requires readers and replication peers to understand the new representation before enabling writes. Archive-aware compression needs separate investigation; relaxing build invalidation is not part of this work.

## Local checks and benchmarks

`test/e2e/chunking_fixtures.py` creates a fresh temporary directory with two compiled C object files and two module archives. The generated workload has 80,000 arithmetic functions and changes one function in the second revision. These are real compiler outputs from a generated workload, not a customer project. The additional deterministic eight-mebibyte corpus inserts twelve bytes at offset 1,000,000; boundary tests also cover deletion.

Run a local Kura with `KURA_REAPI_BLOB_CHUNKING_ENABLED=true`, then point `TUIST_CHUNKING_TEST_URL` at its loopback address. The live client tests use unique project namespaces on each run. Supply colon-separated object paths through `TUIST_CHUNKING_ARTIFACTS`, and archive paths through `TUIST_CHUNKING_MODULES`. For Xcode test runners, also pass the corresponding `TEST_RUNNER_`-prefixed environment variables. The monolithic module benchmark intentionally drives the transfer primitive to measure the rejected candidate; the production wrapper selects the legacy uploader for these archives.

```sh
# From kura/
mise exec -- bazel build //:kura
mise exec -- bazel test //:kura_lib_test --test_filter=http::chunking --test_output=errors
mise run clippy
python3 test/e2e/chunking_fixtures.py
python3 test/e2e/chunked_upload_probe.py http://127.0.0.1:18765 http://127.0.0.1:18765 --tenant chunking-test

# From cas-plugin/, with the test endpoint and optional object paths exported
mise exec -- cargo test --lib
mise exec -- cargo test --test chunking_negotiation --test batch_read_backpressure --test publish_write_backpressure
mise exec -- cargo test --release --test content_defined_chunking -- --include-ignored --nocapture

# From gradle/, with the same environment
./gradlew test --tests dev.tuist.gradle.ContentDefinedChunkingTest --tests dev.tuist.gradle.ChunkedCacheUploadTest --tests dev.tuist.gradle.ChunkedGradleBuildTest --tests dev.tuist.gradle.TuistBuildCacheTest --no-build-cache --no-watch-fs --rerun-tasks

# From the repository root
tuist generate tuist TuistCache TuistCacheTests ProjectDescription --no-open
xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -destination 'platform=macOS,arch=arm64' -only-testing:TuistCacheTests/ContentDefinedChunkingTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" COMPILATION_CACHE_ENABLE_CACHING=NO
mise run cli:lint --fix
```

The cross-region ShellSpec check in `spec/e2e/clients_spec.sh` runs the same upload probe against two nodes. The local check above uses one node; it does not establish old-binary fleet compatibility by itself.

For the full Xcode smoke check, build `cas-plugin` with `mise exec -- cargo build --release`, start `tuist-cas-proxy` with an isolated `TUIST_CAS_PROXY_SOCKET` and the local `TUIST_CAS_REMOTE_GRPC_URL`, then generate fixtures with `--proxy-socket` pointing to that socket. In the fixture directory, run `mise x xcodegen@2.46.0 -- xcodegen generate`. Build the generated `ChunkingFixture` scheme with `xcodebuild build -project ChunkingFixture.xcodeproj -scheme ChunkingFixture -destination 'platform=macOS,arch=arm64' -derivedDataPath <fresh-temporary-directory> CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`. Pass the same `TUIST_CAS_PROXY_SOCKET` to the build. Repeat with another fresh derived-data directory to require a remote restore, not a local hit. Drain the first store before the second build with `tuist-cas-proxy --drain <derived-data>/CompilationCache.noindex/plugin --socket <socket> --timeout-ms 30000`.

Locally, the cold Xcode build succeeded with zero of five cacheable tasks reused. A second, empty local store restored three of five tasks remotely, including the large C object. After the source edit, the build also succeeded, two new splice requests reached Kura, and publication drain completed. This is a functional smoke check, not a representative build-speed benchmark. The Gradle build test similarly executes a real cacheable task, clears its output, restores through Tuist with configuration reuse, then restores through the built-in reader without the Tuist cache service.

### Measurements, 2026-09-07

Apple M5 Pro, 64 gibibytes memory, macOS 26.4.1; optimized Kura, release Rust client, Gradle 9.2.1, Swift debug test runner. All traffic was local loopback. Payload sizes below exclude request headers and protocol metadata. The comparison is with the existing compressed whole-artifact payload, not the uncompressed source. Cold uploads seed each project before its edited revision.

| Workload / edited revision | Whole upload bytes | Chunk payload bytes | Reduction |
| --- | ---: | ---: | ---: |
| Xcode, controlled insertion | 8,388,829 | 579,770 | 93.1% |
| Gradle, controlled insertion | 8,391,193 | 579,947 | 93.1% |
| Module transfer primitive, controlled insertion | 8,388,620 | 595,148 | 92.9% |
| Xcode, compiled object | 3,801,739 | 2,001,189 | 47.4% |
| Gradle, compiled object | 4,053,725 | 2,667,395 | 34.2% |
| Module, single compressed binary archive | 4,375,389 | 4,375,389 | 0%; production keeps legacy upload |

For the cold compiled object, Xcode sent 3,800,870 bytes versus 3,800,413 previously; Gradle sent 4,058,212 versus 4,053,885. The changed Gradle object added 1,564 metadata bytes and seven requests. Compression growth was small in these fixtures, but smaller chunks still add headers and lose compression history.

One observed release Xcode upload took 391 milliseconds cold and 222 milliseconds after the controlled insertion; the compiled pair took 228 and 222 milliseconds. This excludes compression before upload. Gradle's measured store includes spooling, normalization, scanning, and upload: the compiled pair took 812 and 1,384 milliseconds in one run, despite sending fewer bytes on the second. These are noisy local transfer timings, not comparative build-speed benchmarks. The benchmark intentionally does not assert timing improvements. Real network latency, bandwidth, compiler output shape, and archive boundaries determine whether reduced bytes improve the build.
