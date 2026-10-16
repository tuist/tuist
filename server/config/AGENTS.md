# Server Configuration

This directory holds Phoenix configuration for the server.

## Responsibilities
- Environment-specific configuration (dev, test, prod).
- Runtime config and endpoint settings.
- `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true` enables reporting-only network trust for every supported project/account on a self-hosted instance. Parse only exact `true` into the startup application configuration; default false, keep hosted denial, and require replica restarts for changes. There is no dashboard/project policy or allowlist.
- Origin app identity uses `TUIST_ORIGIN_APP_ID` and `TUIST_ORIGIN_APP_PRIVATE_KEY` (Ed25519 PEM) through `Tuist.Environment`. Managed production, canary, and staging sync independent signing keys from their respective 1Password vaults; development loads its own `Development/ORIGIN_APP/private_key` through `server/fnox.toml`. Configuring the key alone does not enable PR reporting or authenticate without the App ID.
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
