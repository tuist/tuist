# TuistREAPI (CLI Module)

This module hosts the CLI's client for the Bazel Remote Execution API (REAPI, `build.bazel.remote.execution.v2`). It is kept separate from `TuistCAS`, which speaks the unrelated compilation-caching CAS protocol (`compilation_cache_service.cas.v1`).

## Responsibilities
- Vendor wire-compatible REAPI Capabilities, ActionCache, CAS FindMissingBlobs/BatchReadBlobs/BatchUpdateBlobs, and ByteStream protocol subsets and generated Swift stubs.
- Respect configured custom CA roots and HTTP(S) environment proxies, including CONNECT authentication and NO_PROXY, for both probing and cache traffic.
- Negotiate SHA-256 cache capabilities, batch limits, and standard REAPI zstd compression. Compress profitable batch uploads at least 1 KiB, accept compressed batch reads, and stream large blobs through `compressed-blobs/zstd` when advertised. Hash and size always describe uncompressed content; bound decoded bytes/window size and verify frame completion. Identity remains compatible with servers that do not advertise compression.
- Batch FindMissingBlobs by digest count independently of payload batching. Keep eight transfers active without waiting for a complete wave; retry transient failures and retain individual successful results.
- Stream SHA-256 blobs with bounded concurrency, verify received size and content, and publish action results only after their referenced blobs exist.
- Encode directory trees deterministically, preserve relative symlinks and executable bits, and reject escaping paths and malformed trees when materializing.
- Output snapshots publish one `Tree` blob and the file-content blobs it references. Child `Directory` messages are embedded in the tree, not published as separate CAS blobs; their digests still identify directory edges.
- Provide `RemoteCacheProbeService` (`RemoteCacheProbing`), which issues the REAPI `GetCapabilities` handshake Bazel performs on start-up to verify a remote cache endpoint is reachable, terminates TLS, and authorizes the request before it is handed to Bazel.

## Filesystem access
- Inject `FileSysteming` into directory snapshot/materialization and transport construction; propagate its async APIs through callers.
- Use `FileSysteming` for listing, directory creation, file copies, batch-blob and CA certificate reads, and cleanup. Parse PEM/DER from the same loaded bytes.
- The current FileSystem API lacks raw symlink targets, permission bits, configurable write durability, atomic binary writes, and streaming reads. Do not force full disk syncs when initializing a temporary streamed download; use the low-level streaming/data path until FileSystem exposes that control. Keep the narrow Foundation operations needed for those features. Do not normalize raw symlink targets through `RelativePath`: doing so can change chained-link semantics and tree digests.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistBazelCommand` (the probe's consumer).
- Remote cache endpoint resolution/selection lives in `cli/Sources/TuistCAS` (`CacheURLStore`); this module consumes an already-resolved URL and a token provider.

## Code generation
- Generated `*.pb.swift`/`*.grpc.swift` are checked in. Regenerate with `mise run cli:generate-reapi-proto` after editing the vendored `.proto` files.
- The task post-processes the raw `protoc` output so the committed files compile and pass lint: it strips the `type:` argument the pinned `protoc-gen-grpc-swift-2` emits on `MethodDescriptor` (the resolved `grpc-swift-2` runtime rejects it), then runs `swiftformat` (generated files are excluded from SwiftLint, like the TuistCAS stubs). Once the runtime accepts `type:`, drop the strip step.

## Related Context
- cli/Sources/TuistCAS/AGENTS.md
- cli/Sources/TuistBazelCommand

## Transfer benchmark
- `cli/Tests/TuistCacheEETests/Storage/ModuleCacheTransferBenchmark.swift` is opt-in via `TUIST_MODULE_CACHE_BENCHMARK_CONFIG`. It compares the real archive/REAPI storage clients against local Kura or an isolated hosted benchmark project, including local publication/materialization, and verifies restored file bytes outside timing. Use HTTPS for hosted endpoints, the same cache credential for both clients, optional metrics, and distinct repetition payloads when measuring cold uploads. Keep it disabled in ordinary test runs.
