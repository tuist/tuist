# TuistCAS (CLI Module)

This module resolves the cache endpoint the CLI and the compilation-cache proxy
talk to. The Xcode compilation-cache transport itself lives in the Rust
`cas-plugin/` crate and its `tuist-cas-proxy`.

## Responsibilities
- Resolve the cache URL for a server/account (`CacheURLStore`), honoring the
  `TUIST_CACHE_ENDPOINT` override and the kura (REAPI) endpoints.
- Wait for an endpoint the server reports as being provisioned, only when the
  caller opts in with `CacheProvisioningWait.forInteractiveCommands`.
- Use a sole endpoint directly, including managed stable hostnames whose regional selection belongs to DNS. Pick the lowest-latency reachable endpoint only when several unranked endpoints are returned (`EndpointLatencyService`); retain this compatibility path for mixed custom/self-hosted endpoints, older servers and regional fallback.
- `getCacheEndpointSelection` resolves a fresh response and returns the selected URL with that response's alternatives. `tuist cache config` must use this operation: independently fetching the URL and endpoint list can mix regional and stable responses during rollout/rollback and mislead the CAS proxy's relocation check. Build callers can keep using `getCacheURL` with server-directed cache expiry.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
- cas-plugin/AGENTS.md
