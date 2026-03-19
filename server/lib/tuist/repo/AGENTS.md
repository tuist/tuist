# Repo Monitoring

This context owns the Tuist Server wrappers around shared repo monitoring.

## Responsibilities
- Configure shared repo pool metrics for the server repos.
- Keep repo labels and telemetry prefixes aligned with PromEx wiring.

## Boundaries
- Shared repo pool metric implementation belongs in `tuist_common/`.
- Repo startup and supervision wiring belongs in `server/lib/tuist/application.ex`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Shared helpers: `tuist_common/AGENTS.md`
