# Server Configuration

This directory holds Phoenix configuration for the server.

## Responsibilities
- Environment-specific configuration (dev, test, prod).
- The test ingestion connection permits ordinary views inside the ClickHouse sandbox with `throw_on_unsupported_query_inside_transaction: 0`. Their MergeTree sources still participate in the transaction and roll back; do not treat ordinary views as transaction-owning storage engines or change production consistency settings to accommodate tests.
- Boruta uses `Tuist.OAuth.AuthoritativeCache` with upstream Ecto adapters: authoritative database reads, ignored fills and no-op invalidations. Every OAuth consumer must first run the authoritative-reading compatibility release (#14040); ordinary overlap and rollback are supported only with authoritative-reading binaries. Follow the [upgrade and rollback sequence](../lib/tuist/oauth/AGENTS.md) and deploy/observe this removal before changing membership.
- Runtime config and endpoint settings.
- Parse `TUIST_SSO_TRUST_UNVERIFIED_LOGIN_DOMAINS` and `TUIST_SSO_CONFIGURATION_ADMIN_USER_IDS` through `SSOLoginDomainTrust.parse_config/3`. Require explicit true/false and a nonempty unique positive-ID list before enabling trust; reject hosted use. `Environment.sso_login_domain_policy/0` independently denies hosted capabilities. The administrator list restricts SSO writes even when trust is off, enabling a staged audit and safe withdrawal. Changes require converged replica restarts; never persist instance assertions as DNS proofs.
- `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true` enables reporting-only network trust for every supported project/account on a self-hosted instance. Parse only exact `true` into the startup application configuration; default false, keep hosted denial, and require replica restarts for changes. There is no dashboard/project policy or allowlist.
- Origin app identity uses `TUIST_ORIGIN_APP_ID` and `TUIST_ORIGIN_APP_PRIVATE_KEY` (Ed25519 PEM) through `Tuist.Environment`. Managed production, canary, and staging sync independent signing keys from their respective 1Password vaults; development loads its own `Development/ORIGIN_APP/private_key` through `server/fnox.toml`. Configuring the key alone does not enable PR reporting or authenticate without the App ID.
- Request logging filters Google One Tap credentials alongside passwords, secrets and tokens.
- Marketing's esbuild `noora/hooks` alias resolves individual Noora hook sources
  so unused charting and form runtimes stay out of the marketing bundle.

## Related Context
- Keep console and Loki structured-metadata allowlists aligned for auth/selected IDs, legacy handles and bounded feature decisions. These high-cardinality fields are structured metadata, never Loki stream labels. Customer billing IDs remain Sentry extras only, not log/trace attributes.
- Business logic: `server/lib/tuist/AGENTS.md`

- GitLab coordinator polling uses the dedicated `runner_gitlab` queue on web nodes; network waits must not occupy the general `default` queue.

- `TUIST_RUNNER_LINUX_CACHE_VOLUMES=true` gates new Linux cache allocations;
  Helm sets it from the cacheVolumes gate. `TUIST_RUNNER_CACHE_VOLUMES_SA_NAME` selects
  the trusted agent account, and `TUIST_RUNNER_CACHE_VOLUMES_NAMESPACE` its namespace. Reports remain available while allocations are off
  so existing resources can be reclaimed.

## Replica-safety rollout

Distributed release startup requires an explicit private cookie and a numeric fixed listener in 1–65535; remote commands keep ephemeral listeners. The Helm chart rejects multi-replica web configurations without clustering; runtime cannot infer a replica count outside the chart. Configuring discovery is not limited to Tuist-hosted mode. DNS discovers peers but must not explicitly disconnect established connections on failed or partial DNS answers; the BEAM failure detector and node shutdown own connection loss, with OTP partition prevention unchanged. The shared Secret spans image versions, so upgrades form mixed-version clusters; the first migration from image-baked cookies temporarily forms separate old/new islands. Complete and observe OAuth invalidation removal before enabling that overlap.
