# Alerts (Context)

This context owns alert rules and triggered alert records for projects.

## Responsibilities

- Define alert rules with threshold configurations for metric regressions.
- Store triggered alerts when rule thresholds are exceeded.
- Deliver Slack notifications via background workers when alerts trigger.

## Boundaries

- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails

- Alert rules and alerts are customer data; update `server/data-export.md` on schema changes.

## Related Context

- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
- Slack notifications: `server/lib/tuist/slack/AGENTS.md`
