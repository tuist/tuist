# Slack (Context)

This context owns Slack app installations and reporting workflows.

## Responsibilities
- Store and manage Slack installation records for accounts.
- Generate Slack report payloads from analytics and bundle metrics.
- Deliver scheduled Slack notifications via background workers.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Slack installation data is customer data; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
