# ClickHouse access recovery

This directory owns the recovery fallback for the ClickHouse operator identity.
Managed deployments reconcile the same state through `Tuist.Release.migrate`
before every server rollout.

## Guardrails

- Internal query users must be distinct from application ingestion and read users.
- Grant only the application database tables and the specific system metadata tables required by the caller.
- Never grant external source, cluster, file, dictionary, user-management, or access-management privileges.
- Keep the fallback file aligned with the release reconciler and Helm-generated credential.
