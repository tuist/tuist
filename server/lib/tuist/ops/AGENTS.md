# Ops (Context)

This context owns ops reporting workers.

## Responsibilities
- Schedule Slack reports for daily/hourly business metrics.
- Query growth stats for users, orgs, projects, and command events.
- Provide bounded, read-only ClickHouse queries and schema discovery for internal operations consumers.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.
- Internal ClickHouse inspection uses its own repository and dedicated read-only credentials.
- `Tuist.Release.migrate` reconciles the dedicated ClickHouse user, role, grants, password, and limits before managed rollouts.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.
- Preserve the ClickHouse query limits and keep external table functions, cluster table functions, and unrestricted system metadata inaccessible.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
