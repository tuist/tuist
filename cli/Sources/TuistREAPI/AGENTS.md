# TuistREAPI (CLI Module)

This module hosts the CLI's client for the Bazel Remote Execution API (REAPI, `build.bazel.remote.execution.v2`). It is kept separate from `TuistCAS`, which speaks the unrelated compilation-caching CAS protocol (`compilation_cache_service.cas.v1`).

## Responsibilities
- Keep hashing cross-platform through `Crypto` from swift-crypto; this module is also built on Linux.
- Vendor wire-compatible REAPI Capabilities, ActionCache, CAS FindMissingBlobs/BatchReadBlobs/BatchUpdateBlobs, and ByteStream protocol subsets and generated Swift stubs.
- Respect configured custom CA roots and HTTP(S) environment proxies, including CONNECT authentication and NO_PROXY, for both probing and cache traffic.
- Negotiate SHA-256 cache capabilities, batch limits, and standard REAPI zstd compression. Compress profitable batch uploads at least 1 KiB, accept compressed batch reads, and stream large blobs through `compressed-blobs/zstd` when advertised. Hash and size always describe uncompressed content; bound decoded bytes/window size and verify frame completion. Identity remains compatible with servers that do not advertise compression. Batch-read acceptable compressors describe client decoding support, independently of the server’s ByteStream/upload capabilities.
- Batch FindMissingBlobs by digest count independently of payload batching. Uploads and plans containing ByteStream downloads keep eight transfers active; batch-only downloads use up to 32. Cap batches at 2 MiB and respect smaller advertised server limits; the batch-only download payload budget is at most 64 MiB before protobuf/decompression overhead. Retry transient failures and retain individual successful results.
- Share four gRPC connections across bounded operations, with a 32 MiB HTTP/2 receive window per connection. The transfer limit is global, not multiplied by the connection count. Prefer module-ordered download hints so verified completion callbacks can unblock materialization early.
- Deliver verified blob callbacks progressively; callbacks may move the download into CAS. Exclude failed publications, propagate cancellation, and never republish a completed blob during batch retries. Private batch downloads use streaming writes without syncing their payloads; the storage layer publishes them atomically.
- Blob reads resume: a broken read is retried with `read_offset` at the byte it reached, carrying the bytes on disk and the running hash with it. `read_offset` names an offset into the uncompressed blob, so a resumed compressed read is a new zstd stream with its own decoder. Only consecutive attempts that get no further into the blob count against the resume cap, and the whole blob is still verified against its digest. Writes cannot resume, because a ByteStream write carries the blob from its first byte; a broken upload starts over.
- Resuming a blob is bounded by the bytes it has to show for itself: a download may take as long as a link at `slowestBytesPerSecond` needs for what it has received, so a server that hands over a chunk and stalls is given up on rather than resumed indefinitely. A batch read can neither resume nor be watched for idleness, so its payload-sized deadline is the only thing that notices a hung server there, and it is spent once rather than three times.
- A transfer is cut once it has been idle for longer than `TransferGuards.idleTimeout` plus the time its largest message takes at `slowestBytesPerSecond`, which is what lets a stalled read resume quickly. A message only counts as activity once it is whole, so the allowance is seeded with the largest message the peer is expected to send: the server chunk size for a read, the client chunk size for a write. Cutting on the bare idle timeout would abandon a slow link mid-message. Call deadlines are sized from the bytes a call carries; they are a backstop against a trickle, not the stall guard.
- Stream SHA-256 blobs with bounded concurrency, verify received size and content, and publish action results only after their referenced blobs exist.
- Encode directory trees deterministically, preserve relative symlinks and executable bits, and reject escaping paths and malformed trees when materializing.
- Output snapshots publish one `Tree` blob and the file-content blobs it references. Child `Directory` messages are embedded in the tree, not published as separate CAS blobs; their digests still identify directory edges.
- Provide `RemoteCacheProbeService` (`RemoteCacheProbing`), which issues the REAPI `GetCapabilities` handshake Bazel performs on start-up to verify a remote cache endpoint is reachable, terminates TLS, and authorizes the request before it is handed to Bazel.

- Capability probes allow 30 seconds per attempt and up to four attempts for UNAVAILABLE/RESOURCE_EXHAUSTED, so the first authenticated probe can wake a cold cache. Authorization failures and deadlines are not retried.
- Capability probe regressions live in `cli/Tests/TuistREAPITests` and use a local HTTP/2 gRPC server.

## Filesystem access
- Inject `FileSysteming` into directory snapshot/materialization and transport construction; propagate its async APIs through callers.
- Convert `AbsolutePath` to Foundation URLs with `URL(fileURLWithPath: path.pathString)`; do not rely on transitive `TuistSupport` extensions that are unavailable in the Linux build.
- Use `FileSysteming` for listing, directory creation, file copies, batch-blob and CA certificate reads, and cleanup. Parse PEM/DER from the same loaded bytes.
- The current FileSystem API lacks raw symlink targets, permission bits, configurable write durability, atomic binary writes, and streaming reads. Do not force full disk syncs when initializing a temporary streamed download; use the low-level streaming/data path until FileSystem exposes that control. Keep the narrow Foundation operations needed for those features. Do not normalize raw symlink targets through `RelativePath`: doing so can change chained-link semantics and tree digests.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistBazelCommand` (the probe's consumer).
- Remote cache endpoint resolution/selection lives in `cli/Sources/TuistCAS` (`CacheURLStore`); this module consumes an already-resolved URL and a token provider.

## Code generation
- Generated `*.pb.swift`/`*.grpc.swift` are checked in. Regenerate with `mise run cli:generate-reapi-proto` after editing the vendored `.proto` files.
- The task post-processes the raw `protoc` output so the committed files compile and pass lint: it strips the `type:` argument the pinned `protoc-gen-grpc-swift-2` emits on `MethodDescriptor` (the resolved `grpc-swift-2` runtime rejects it), then runs `swiftformat` with its cache disabled. A second uncached `fileHeader` pass removes the proto comment exposed by stripping the generator header; otherwise fresh CI lint rejects output that the formatter cache considers clean. Generated files are excluded from SwiftLint. Once the runtime accepts `type:`, drop the strip step.

## Related Context
- cli/Sources/TuistCAS/AGENTS.md
- cli/Sources/TuistBazelCommand

## Transfer benchmark
- `cli/Tests/TuistCacheEETests/Storage/ModuleCacheTransferBenchmark.swift` is opt-in via `TUIST_MODULE_CACHE_BENCHMARK_CONFIG`. It compares the real archive/REAPI storage clients against local Kura or an isolated hosted benchmark project, including local publication/materialization, and verifies restored file bytes outside timing. Use HTTPS for hosted endpoints, the same cache credential for both clients, optional metrics, and distinct repetition payloads when measuring cold uploads. Keep it disabled in ordinary test runs.
