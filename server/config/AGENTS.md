# Server Configuration

This directory holds Phoenix configuration for the server.

## Responsibilities
- Environment-specific configuration (dev, test, prod).
- Runtime config and endpoint settings.
- Request logging filters Google One Tap credentials alongside passwords, secrets and tokens.
- Marketing's esbuild `noora/hooks` alias resolves individual Noora hook sources
  so unused charting and form runtimes stay out of the marketing bundle.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`

- GitLab coordinator polling uses the dedicated `runner_gitlab` queue on web nodes; network waits must not occupy the general `default` queue.

- `TUIST_RUNNER_LINUX_CACHE_VOLUMES=true` gates new Linux cache allocations;
  Helm sets it from the cacheVolumes gate. `TUIST_RUNNER_CACHE_VOLUMES_SA_NAME` selects
  the trusted agent account, and `TUIST_RUNNER_CACHE_VOLUMES_NAMESPACE` its namespace. Reports remain available while allocations are off
  so existing resources can be reclaimed.
