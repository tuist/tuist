# TuistCAS (CLI Module)

This module resolves the cache (CAS) endpoint the CLI and the compilation-cache
proxy talk to, and hosts the legacy per-project Swift CAS daemon
(`CASService`/`KeyValueService`) served on the non-kura path.

## Responsibilities
- Resolve the cache URL for a server/account (`CacheURLStore`), honoring the
  `TUIST_CACHE_ENDPOINT` override and the kura (REAPI) endpoints.
- Pick the lowest-latency endpoint when several are returned (`EndpointLatencyService`).
- Serve Xcode's compilation-cache gRPC protocol (`cas.proto`/`keyvalue.proto`
  stubs, `CASService`/`KeyValueService`) from the per-project daemon for accounts
  not yet on kura. On the kura path this transport instead lives in the Rust
  `cas-plugin/` crate and its `tuist-cas-proxy`; the CLI picks between them on
  the `kura` client feature flag.
- The daemon's CAS saves declare `tuist-checksum-sha256` (the SHA-256 of the compressed body sent; the CAS id
  hashes uncompressed content and cannot stand in for it), and loads verify the body against the served
  header. A mismatch is reported to the compiler as `objectNotFound`, a miss it recompiles from, and
  counts as a healthy backend for the circuit breaker.


## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
