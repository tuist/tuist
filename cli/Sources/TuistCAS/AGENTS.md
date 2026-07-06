# TuistCAS (CLI Module)

This module resolves the cache (CAS) endpoint the CLI and the compilation-cache
proxy talk to.

## Responsibilities
- Resolve the cache URL for a server/account (`CacheURLStore`), honoring the
  `TUIST_CACHE_ENDPOINT` override and the kura (REAPI) endpoints.
- Pick the lowest-latency endpoint when several are returned (`EndpointLatencyService`).

The Xcode compilation-cache CAS/key-value transport itself now lives in the Rust
`cas-plugin/` crate and its `tuist-cas-proxy`; the legacy Swift gRPC daemon
(`CASService`/`KeyValueService`) was removed.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
- cas-plugin/AGENTS.md
