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
- The `:cache_hit_rate` category averages two sources, module cache and Xcode cache. The current and previous windows must be built from the same set of sources and from equally sized samples, otherwise the comparison measures window composition rather than a regression. `Tuist.Cache.Analytics.cache_hit_rate_metric_window_comparison/4` owns that rule; go through it rather than querying either source per window.

## Related Context

- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
- Slack notifications: `server/lib/tuist/slack/AGENTS.md`
