# Repo Monitoring

This context owns the Tuist Server wrappers around shared repo monitoring.

## Responsibilities
- Configure shared repo pool metrics for the server repos.
- Keep repo labels and telemetry prefixes aligned with PromEx wiring.
- Export identical pool and query metrics in every server runtime, using the
  bounded `workload` label from `Tuist.Environment.mode/0` to distinguish them.
- `PromExPlugin.attach/0` forwards all six physical repository query events to
  one metrics event. Cloud reads/writes, shadow reads/writes, and ops reads keep
  separate bounded `repo` labels, including when a dynamic repository routes
  reads. Poll optional pools only when running. Keep query text, parameters, and
  customer identifiers out of that event. Record missing timing phases as absent
  rather than zero. `idle_time` is time idle before checkout, not occupancy or a
  component of total query duration. The ClickHouse read-outcome plugin and Ecto
  tracing also consume shadow repository events; retain physical attribution.
- Attach the ClickHouse read-outcome forwarder at startup too. It merges Cloud
  and shadow raw events into one sanitized event before exporting the existing
  metric names, avoiding duplicate Prometheus metric families.

## Boundaries
- Shared repo pool metric implementation belongs in `tuist_common/`.
- Repo startup and supervision wiring belongs in `server/lib/tuist/application.ex`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Shared helpers: `tuist_common/AGENTS.md`
