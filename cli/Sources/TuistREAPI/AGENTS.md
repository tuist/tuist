# TuistREAPI (CLI Module)

This module hosts the CLI's client for the Bazel Remote Execution API (REAPI, `build.bazel.remote.execution.v2`). It is kept separate from `TuistCAS`, which speaks the unrelated compilation-caching CAS protocol (`compilation_cache_service.cas.v1`).

## Responsibilities
- Vendor wire-compatible REAPI Capabilities, ActionCache, CAS FindMissingBlobs/BatchReadBlobs/BatchUpdateBlobs, and ByteStream protocol subsets and generated Swift stubs.
- Respect configured custom CA roots and HTTP(S) environment proxies, including CONNECT authentication and NO_PROXY, for both probing and cache traffic.
- Negotiate SHA-256 cache capabilities and batch limits; batch small blobs and stream large blobs with bounded transient retries.
- Stream SHA-256 blobs with bounded concurrency, verify received size and content, and publish action results only after their referenced blobs exist.
- Encode directory trees deterministically, preserve relative symlinks and executable bits, and reject escaping paths and malformed trees when materializing.
- Output snapshots publish one `Tree` blob and the file-content blobs it references. Child `Directory` messages are embedded in the tree, not published as separate CAS blobs; their digests still identify directory edges.
- Provide `RemoteCacheProbeService` (`RemoteCacheProbing`), which issues the REAPI `GetCapabilities` handshake Bazel performs on start-up to verify a remote cache endpoint is reachable, terminates TLS, and authorizes the request before it is handed to Bazel.

## Filesystem access
- Inject `FileSysteming` into directory snapshot/materialization and transport construction; propagate its async APIs through callers.
- Use `FileSysteming` for listing, directory creation, file copies, and CA certificate reads. Parse PEM/DER from the same loaded bytes.
- The current FileSystem API lacks raw symlink targets, permission bits, atomic binary writes, and streaming reads. Keep the narrow Foundation operations needed for those features. Do not normalize raw symlink targets through `RelativePath`: doing so can change chained-link semantics and tree digests.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistBazelCommand` (the probe's consumer).
- Remote cache endpoint resolution/selection lives in `cli/Sources/TuistCAS` (`CacheURLStore`); this module consumes an already-resolved URL and a token provider.

## Code generation
- Generated `*.pb.swift`/`*.grpc.swift` are checked in. Regenerate with `mise run cli:generate-reapi-proto` after editing the vendored `.proto` files.
- The task post-processes the raw `protoc` output so the committed files compile and pass lint: it strips the `type:` argument the pinned `protoc-gen-grpc-swift-2` emits on `MethodDescriptor` (the resolved `grpc-swift-2` runtime rejects it), then runs `swiftformat` (generated files are excluded from SwiftLint, like the TuistCAS stubs). Once the runtime accepts `type:`, drop the strip step.

## Related Context
- cli/Sources/TuistCAS/AGENTS.md
- cli/Sources/TuistBazelCommand
