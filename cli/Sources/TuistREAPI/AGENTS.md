# TuistREAPI (CLI Module)

This module hosts the CLI's client for the Bazel Remote Execution API (REAPI, `build.bazel.remote.execution.v2`). It is kept separate from `TuistCAS`, which speaks the unrelated compilation-caching CAS protocol (`compilation_cache_service.cas.v1`).

## Responsibilities
- Vendor wire-compatible REAPI Capabilities, ActionCache, CAS FindMissingBlobs, and ByteStream protocol subsets and generated Swift stubs.
- Stream SHA-256 blobs with bounded concurrency, verify received size and content, and publish action results only after their referenced blobs exist.
- Encode directory trees deterministically, preserve relative symlinks and executable bits, and reject escaping paths and malformed trees when materializing.
- Provide `RemoteCacheProbeService` (`RemoteCacheProbing`), which issues the REAPI `GetCapabilities` handshake Bazel performs on start-up to verify a remote cache endpoint is reachable, terminates TLS, and authorizes the request before it is handed to Bazel.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistBazelCommand` (the probe's consumer).
- Remote cache endpoint resolution/selection lives in `cli/Sources/TuistCAS` (`CacheURLStore`); this module consumes an already-resolved URL and a token provider.

## Code generation
- Generated `*.pb.swift`/`*.grpc.swift` are checked in. Regenerate with `mise run cli:generate-reapi-proto` after editing the vendored `.proto` files.
- The task post-processes the raw `protoc` output so the committed files compile and pass lint: it strips the `type:` argument the pinned `protoc-gen-grpc-swift-2` emits on `MethodDescriptor` (the resolved `grpc-swift-2` runtime rejects it), then runs `swiftformat` (generated files are linted like the rest of `cli/`, not excluded). Once the runtime accepts `type:`, drop the strip step.

## Related Context
- cli/Sources/TuistCAS/AGENTS.md
- cli/Sources/TuistBazelCommand
