# Repo Monitoring

This context owns the Tuist Server wrappers around shared repo monitoring.

## Responsibilities
- Configure shared repo pool metrics for the server repos.
- Keep repo labels and telemetry prefixes aligned with PromEx wiring.
- Export identical pool and query metrics in every server runtime, using the
  bounded `workload` label from `Tuist.Environment.mode/0` to distinguish them.
- `PromExPlugin.attach/0` forwards the three repository query events to one
  metrics event. Keep query text, parameters, and customer identifiers out of
  that event. Record missing timing phases as absent rather than zero.

## Boundaries
- Shared repo pool metric implementation belongs in `tuist_common/`.
- Repo startup and supervision wiring belongs in `server/lib/tuist/application.ex`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Shared helpers: `tuist_common/AGENTS.md`
