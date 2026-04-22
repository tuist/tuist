# Server Tests

This directory contains ExUnit tests for the Tuist Server.

## Testing Guidelines
- Tests are `async: true` by default; avoid global state and make architectural changes to support concurrency.
- Tests run with a clean database.
- Never modify System environment variables in tests (shared state).
- Use mocks/stubs/DI for environment-dependent behavior.
- Tests that touch ClickHouse should opt in at the case level with `clickhouse: true`, for example `use TuistTestSupport.Cases.DataCase, clickhouse: true` or `use TuistTestSupport.Cases.ConnCase, clickhouse: true`. That marks the test with `:clickhouse`, registers ClickHouse cleanup automatically, and must not be combined with `async: true`.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
