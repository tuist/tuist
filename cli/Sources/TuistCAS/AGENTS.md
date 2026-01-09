# TuistCAS (CLI Module)

This module provides content-addressable storage (CAS) protobuf and gRPC stubs used by cache features.

## Responsibilities
- Define gRPC/protobuf types for CAS and key-value operations (`cas.pb.swift`, `keyvalue.pb.swift`).
- Expose generated gRPC clients used by cache integrations.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
