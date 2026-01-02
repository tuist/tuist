# Server Tests

This directory contains ExUnit tests for the Tuist Server.

## Testing Guidelines
- Tests run with a clean database.
- Never modify System environment variables in tests (shared state).
- Use mocks/stubs/DI for environment-dependent behavior.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
