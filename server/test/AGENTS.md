# Server Tests

This directory contains ExUnit tests for the Tuist Server.

## Testing Guidelines
- Tests are `async: true` by default; avoid global state and make architectural changes to support concurrency.
- Tests run with a clean database.
- Audit-event assertions should compare contents without assuming chronological order from second-precision timestamps or UUIDv7 IDs generated in the same millisecond.
- Never modify System environment variables in tests (shared state).
- Use mocks/stubs/DI for environment-dependent behavior.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
- Shared Swift/Elixir report identities: `cli/Tests/Fixtures/JUnitIdentity/AGENTS.md`.
