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

- Recorded timeline coverage includes Gradle clock alignment, all-operation loading, legacy reports, Bazel retained-span limits, opaque IDs, filtered navigation, tab reopening, and API/MCP parent authorization.
