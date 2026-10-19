# Server Configuration

This directory holds Phoenix configuration for the server.

## Responsibilities
- Environment-specific configuration (dev, test, prod).
- The test ingestion connection permits ordinary views inside the ClickHouse sandbox with `throw_on_unsupported_query_inside_transaction: 0`. Their MergeTree sources still participate in the transaction and roll back; do not treat ordinary views as transaction-owning storage engines or change production consistency settings to accommodate tests.
- Boruta uses `Tuist.OAuth.AuthoritativeCache` with upstream Ecto adapters: authoritative database reads, ignored fills, and retained legacy invalidations. This is the rolling-compatible preparatory release; do not disable invalidations or change membership until all OAuth consumers are upgraded and the [subsequent migration](../lib/tuist/oauth/AGENTS.md) is separately reviewed.
- Runtime config and endpoint settings.
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
