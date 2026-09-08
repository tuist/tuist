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

- Kura private gateway coverage belongs in the region and Kubernetes provisioner suites, with dispatch/activation coverage in `tuist/kura_test.exs`. Cover stale generations, expired observations, incomplete gateway readiness, environment hostname isolation, two replicas and retained legacy NodePorts.

- Private endpoint regressions should prove that old `lastReconciledAt` does not invalidate a fresh endpoint check, while repeatedly reading the same `endpointLastCheckedAt` cannot renew `last_ready_at`. Revision digest tests should cover order-independent CIDRs and reuse the module's canonical text hashing.
