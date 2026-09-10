# Ops (Context)

This context owns ops reporting workers.

## Responsibilities
- Schedule Slack reports for daily/hourly business metrics.
- The hourly sign-up report posts new users and organizations to `#gtm` every day, including weekends. Slack API failures must propagate to Oban for retries.
- Internal reports authenticate with `TUIST_SLACK_TUIST_TOKEN`, sourced by ESO from `SLACK/tuist_token` in the per-environment `tuist-k8s-<env>` 1Password vault. An `account_inactive` response requires restoring the Slack identity or replacing that credential; code retries cannot repair it. After a secret replacement, ESO must sync and the server pods must reload their environment before validating `auth.test` and channel delivery.
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
