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
- Because scrapes are cumulative, a tag value only has to be seen once to be exported for the life of the pod. Series therefore accumulate up to the full tag cross-product, so treat every new tag as a permanent cost rather than one paid only while traffic flows.
- The `path` tag on the Phoenix HTTP metrics is the largest such cross-product: one value per router entry, multiplied by method, status and bucket. The router generates marketing and docs routes once per locale, so `Tuist.PromEx` passes `Tuist.Locale.collapse_locale_path_prefix/1` as the plugin's `:normalize_path` to fold those variants into `/:locale/...`. Adding a locale must not add a route label.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
