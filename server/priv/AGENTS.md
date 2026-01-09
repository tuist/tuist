# Server Private Assets (Migrations, Seeds)

This directory contains database migrations and other private assets.

## Responsibilities
- PostgreSQL migrations: `server/priv/repo/migrations`
- ClickHouse migrations: `server/priv/ingest_repo/migrations`

## Guardrails
- If you change stored customer data, update `server/data-export.md`.
- Use `:timestamptz` for migration timestamps (per Credo rules).

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
