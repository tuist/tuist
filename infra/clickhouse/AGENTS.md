# ClickHouse access bootstrap

This directory owns operator-run ClickHouse user and role provisioning.

## Guardrails

- Internal query users must be distinct from application ingestion and read users.
- Grant only the application database tables and the specific system metadata tables required by the caller.
- Never grant external source, cluster, file, dictionary, user-management, or access-management privileges.
- Keep the matching secret-store field and Helm feature gate documented in `README.md`.
