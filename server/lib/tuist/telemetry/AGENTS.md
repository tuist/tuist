# Telemetry (Context)

This context defines telemetry event names used across the server.

## Responsibilities
- Provide consistent event name helpers for storage, cache, repo pool, and run events.
- Attach failed ClickHouse read templates and timings to the matching Sentry-compatible error event. Keep parameters out of reports and clear process-local query context after a successful retry.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
