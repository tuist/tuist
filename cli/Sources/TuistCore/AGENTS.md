# TuistCore (Domain Core)

This module contains core domain abstractions and shared models used across the CLI.

## Responsibilities
- Cross-cutting domain models for command runs and analytics (e.g., `CommandEvent`, `RunGraph`).
- Shared run metadata and cache-related telemetry types.

## Boundaries
- Avoid direct dependency on CLI command wiring (`TuistKit`) or entry points.
- Keep IO-heavy or integration-specific logic in feature modules (HTTP, Server, Cache).

## Invariants
- Simulator booting tolerates an already-booted device because callers can hold a shutdown snapshot from before app installation; other boot failures must propagate.
- Analytics types are Codable and designed for transport to the server.
- Models encode run metadata (command args, environment, git info, cache endpoints).
- Restoring a test-products snapshot retains the graph, selective-testing state, and build link, but must not replay the original build's binary cache lookups as activity in each test shard.

## Related Context
- Shared utilities: `cli/Sources/TuistSupport/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`

- Subhash diagnostics carry optional effective destinations, foreign-build hashes, and UI-test device/runtime inputs. Missing historical inputs remain nil; RunTarget destinations retain declared graph metadata.
