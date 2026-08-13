# Prom Ex (Context)

This context owns PromEx helpers and buckets configuration.

## Responsibilities
- Provide custom bucket configuration for PromEx/Peep distributions.
- Provide the PromEx storage adapter (`Tuist.PromEx.StripedPeep`, wired in `server/config/config.exs`).

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.
- Keep `StripedPeep.scrape/1` non-destructive. Counters and distributions have to be cumulative for `rate/1` and `histogram_quantile/2`, and PromEx also calls `scrape/1` from `PromEx.ETSCronFlusher` and discards the result, so anything freed on read never reaches Prometheus. Bound memory through tag cardinality instead.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
