# TuistCAS (CLI Module)

This module resolves cache URLs for the CLI and the compilation-cache proxy.
The Xcode compilation-cache transport lives in `cas-plugin/`.

## Responsibilities
- Derive hosted cache URLs locally from the account handle: `<account>.cache.tuist.dev`, with `-staging` or `-canary` appended to the account in those environments.
- Honor `TUIST_CACHE_ENDPOINT` first; self-hosted servers require this explicit override.
- Validate account handles before composing a DNS name. Do not restore endpoint discovery, persisted endpoint choices, or client latency probes.
- An authenticated demand-registration call wakes new or archived instances and records activity. It returns no URLs and has a two-second request budget; deduplicate it for five minutes, and back off failures for 30 seconds while allowing an already-serving cache to remain usable. Explicit overrides skip hosted demand registration. Authentication and authorization remain server responsibilities.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
- cas-plugin/AGENTS.md
