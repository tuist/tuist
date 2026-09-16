# ClickHouse access recovery and migration

This directory owns the recovery fallback for the ClickHouse operator identity.
Managed deployments reconcile the same state through `Tuist.Release.migrate`
before every server rollout.

It also owns [`migration.md`](migration.md), the runbook for moving an
environment's ClickHouse onto the in-cluster server. Each step runs through the
launcher in `infra/mise/tasks/clickhouse/migration.sh`.

## Guardrails

- Internal query users must be distinct from application ingestion and read users.
- Grant only the application database tables and the specific system metadata tables required by the caller.
- Never grant external source, cluster, file, dictionary, user-management, or access-management privileges.
- Keep the fallback file aligned with the release reconciler and Helm-generated credential.
- Run migration steps through the launcher, not the chart's `clickhouse.managed.migration` deploy hook.
- Keep the launcher's step list aligned with the ClickHouse tasks in `Tuist.Release`.
