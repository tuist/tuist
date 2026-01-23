# Ingestion (Context)

This context owns ingestion buffers for ClickHouse writes.

## Responsibilities
- Buffer RowBinary inserts in memory and flush on size/time thresholds.
- Provide a GenServer interface for async insert and flush operations.

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
