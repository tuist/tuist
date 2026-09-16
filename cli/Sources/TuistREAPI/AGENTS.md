# TuistREAPI (CLI Module)

This module hosts the CLI's client for the Bazel Remote Execution API (REAPI, `build.bazel.remote.execution.v2`). It is kept separate from `TuistCAS`, which speaks the unrelated compilation-caching CAS protocol (`compilation_cache_service.cas.v1`).

## Responsibilities
- Vendor minimal subsets of REAPI (`capabilities.proto`) and Remote Asset (`remote_asset.proto`) with generated Swift stubs.
- Provide `RemoteCacheProbeService` (`RemoteCacheProbing`), which issues the REAPI `GetCapabilities` handshake Bazel performs on start-up to verify a remote cache endpoint is reachable, terminates TLS, and authorizes the request before it is handed to Bazel.

- Provide `RemoteAssetProbeService` (`RemoteAssetProbing`), which sends an authenticated FetchBlob request with no URIs through the actual asset route. Only INVALID_ARGUMENT confirms availability; missing routes, authorization/transport errors, timeout and unexpected success return false. Never fetch an origin or persist probe results. Keep the five-second deadline and real gRPC regression coverage in `cli/Tests/TuistREAPITests`.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistBazelCommand` (the probe's consumer).
- Remote cache endpoint resolution/selection lives in `cli/Sources/TuistCAS` (`CacheURLStore`); this module only probes an already-resolved URL.

## Code generation
- Generated `*.pb.swift`/`*.grpc.swift` are checked in. Regenerate with `mise run cli:generate-reapi-proto` after editing either proto.
- The task post-processes the raw `protoc` output so the committed files compile and pass lint: it strips the `type:` argument the pinned `protoc-gen-grpc-swift-2` emits on `MethodDescriptor` (the resolved `grpc-swift-2` runtime rejects it), then runs `swiftformat` (generated files are linted like the rest of `cli/`, not excluded). Once the runtime accepts `type:`, drop the strip step.

## Related Context
- cli/Sources/TuistCAS/AGENTS.md
- cli/Sources/TuistBazelCommand
