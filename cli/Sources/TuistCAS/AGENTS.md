# TuistCAS (CLI Module)

This module resolves cache URLs for the CLI and the compilation-cache proxy.
The Xcode compilation-cache transport lives in `cas-plugin/`.

## Responsibilities
- Derive hosted cache URLs locally from the account handle: `<account>.cache.tuist.dev`, with `-staging` or `-canary` appended to the account in those environments.
- Honor `TUIST_CACHE_ENDPOINT` first; self-hosted servers require this explicit override.
- Validate account handles before composing a DNS name. Do not restore endpoint discovery, persisted endpoint choices, or client latency probes.
- URL resolution performs no network requests. Actual cache requests wake archived hosted instances through the shared activation gateway; authentication and provisioning are server responsibilities.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
- cas-plugin/AGENTS.md

- Missing self-hosted endpoint overrides disable remote caching with a warning in ordinary builds and proxy startup; malformed overrides remain errors. Custom/registered hosted endpoints use the same explicit override contract. Do not reintroduce obsolete discovery errors or readiness polling.
- `tuist cache config` returns a project-scoped exchanged cache token so the Xcode proxy carries signed placement origin. Only a 404 from an older self-hosted server retains raw-credential compatibility.
