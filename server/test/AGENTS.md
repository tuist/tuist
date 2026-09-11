# Server Tests

This directory contains ExUnit tests for the Tuist Server.

## Testing Guidelines
- Tests are `async: true` by default; avoid global state and make architectural changes to support concurrency.
- Tests run with a clean database.
- Audit-event assertions should compare contents without assuming chronological order from second-precision timestamps or UUIDv7 IDs generated in the same millisecond.
- Never modify System environment variables in tests (shared state).
- Use mocks/stubs/DI for environment-dependent behavior.
- Telemetry handlers are global: `:telemetry_test.attach_event_handlers/2` also delivers an event a concurrently running test emitted, tagged with this test's own ref. Use `TuistTestSupport.TelemetryCapture.attach_event_handlers/1`, which forwards only what the attaching process emits.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`

- Recorded timeline coverage includes Gradle clock alignment, all-operation loading, legacy reports, Bazel retained-span limits, opaque IDs, filtered navigation, tab reopening, and API/MCP parent authorization. Shared lifecycle coverage also checks source/project identity, forced refresh, stale and inactive-tab bootstrap requests, and authenticated HTTP metadata downloads for all three build systems.

- Shared Swift/Elixir report identities: `cli/Tests/Fixtures/JUnitIdentity/AGENTS.md`.

- Kura private gateway coverage belongs in the region and Kubernetes provisioner suites, with dispatch/activation coverage in `tuist/kura_test.exs`. Cover stale generations, expired observations, incomplete gateway readiness, environment hostname isolation, two replicas and retained legacy NodePorts.

- Private endpoint regressions should prove that old `lastReconciledAt` does not invalidate a fresh endpoint check, while repeatedly reading the same `endpointLastCheckedAt` cannot renew `last_ready_at`. Revision digest tests should cover order-independent CIDRs and reuse the module's canonical text hashing.

- GitLab runner tests reject unmocked HTTP requests; the Go executor uses a local fake coordinator for execution, artifacts and masked-log validation.
