# TuistCAS (CLI Module)

This module resolves the cache (CAS) endpoint the CLI and the compilation-cache
proxy talk to, and hosts the legacy per-project Swift CAS daemon
(`CASService`/`KeyValueService`) behind the hidden `cache-start` command.

## Responsibilities
- Resolve the cache URL for a server/account (`CacheURLStore`), honoring the
  `TUIST_CACHE_ENDPOINT` override and the kura (REAPI) endpoints.
- Pick the lowest-latency endpoint when several are returned (`EndpointLatencyService`).
- Serve Xcode's compilation-cache gRPC protocol (`cas.proto`/`keyvalue.proto`
  stubs, `CASService`/`KeyValueService`) from the per-project daemon. Neither
  `tuist setup cache` nor `tuist generate` wires it up: the transport they
  configure lives in the Rust `cas-plugin/` crate and its `tuist-cas-proxy`.


## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
