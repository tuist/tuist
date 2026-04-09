# Http (Context)

This context defines server-owned HTTP observability integration.

## Responsibilities
- Emit server-owned HTTP client metrics for Finch request lifecycle (queue, connection, send, receive).
- Reuse shared transport observability from `tuist_common/lib/tuist_common/http` for Bandit and Thousand Island server metrics/logging.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.
- Shared Bandit/Thousand Island observability belongs in `tuist_common/`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
