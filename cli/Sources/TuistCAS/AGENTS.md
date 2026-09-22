# TuistCAS (CLI Module)

This module resolves the cache endpoint the CLI and the compilation-cache proxy
talk to. The Xcode compilation-cache transport itself lives in the Rust
`cas-plugin/` crate and its `tuist-cas-proxy`.

## Responsibilities
- Resolve the cache URL for a server/account (`CacheURLStore`), honoring the
  `TUIST_CACHE_ENDPOINT` override and the kura (REAPI) endpoints.
- Wait for an endpoint the server reports as being provisioned, only when the
  caller opts in with `CacheProvisioningWait.forInteractiveCommands`.
- Pick the lowest-latency endpoint when several are returned (`EndpointLatencyService`).
- Keep the server's endpoint expiration authoritative. Do not put an unexpiring
  in-memory cache in front of `CachedValueStore`: a long-lived caller must see a
  refreshed selection once the previous answer expires.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
- cas-plugin/AGENTS.md
