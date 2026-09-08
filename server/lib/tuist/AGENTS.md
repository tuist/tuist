# Tuist (Business Logic)

This directory contains the core business logic and domain modules for the server.

## Responsibilities
- Machine metrics retain nullable `offset_ms` from the activity log start during archive processing, independently of the upload timestamp, so recorded samples align with build steps. Older samples without offsets keep their standalone charts.

- Ecto schemas, contexts, and domain services.
- Business rules for accounts, projects, bundles, previews, and analytics.
- Xcode build steps (`Tuist.Builds.Step`, `build_steps`) are ingested alongside build details for reuse across build analytics, retain only current-invocation leaf intervals for 90 days, are streamed from the parser sidecar in batches of 100, and are read with retry deduplication. Each log has an independent 64 KiB allowance and preserves its beginning and end when truncated. `Tuist.Builds.Timeline` returns individual intervals in a maximum 120-second viewport with a 60-second buffer on either side for local zooming. Subsequent range requests reuse the build summary held by LiveView to avoid rescanning totals and duration. Search, target filtering and keyboard navigation query all steps. Logs share that retention and are fetched separately by build and event ID.
- Content-addressed Open Graph image rendering and shared object-storage caching.

## Boundaries

- `ClickHouseDictionarySource` builds escaped local dictionary sources for migrations.
  Its query options suppress application SQL logging without overriding managed
  ClickHouse logging policy; server password masking requires valid dictionary DDL.

- Web controllers and LiveView code live in `server/lib/tuist_web`.
- Data migrations live in `server/priv`.

## Related Context (Downlinks)

- Accounts: `server/lib/tuist/accounts/AGENTS.md`
- Alerts: `server/lib/tuist/alerts/AGENTS.md`
- Api: `server/lib/tuist/api/AGENTS.md`
- App Builds: `server/lib/tuist/app_builds/AGENTS.md`
- Authentication: `server/lib/tuist/authentication/AGENTS.md`
- Authorization: `server/lib/tuist/authorization/AGENTS.md`
- Aws: `server/lib/tuist/aws/AGENTS.md`
- Bazel: `server/lib/tuist/bazel/AGENTS.md`
- Billing: `server/lib/tuist/billing/AGENTS.md`
- Bundles: `server/lib/tuist/bundles/AGENTS.md`
- Cache: `server/lib/tuist/cache/AGENTS.md`
- Cache Action Items: `server/lib/tuist/cache_action_items/AGENTS.md`
- Command Events: `server/lib/tuist/command_events/AGENTS.md`
- Ecto: `server/lib/tuist/ecto/AGENTS.md`
- Github: `server/lib/tuist/github/AGENTS.md`
- Http: `server/lib/tuist/http/AGENTS.md`
- Ingestion: `server/lib/tuist/ingestion/AGENTS.md`
- Key Value Store: `server/lib/tuist/key_value_store/AGENTS.md`
- Kubernetes: `server/lib/tuist/kubernetes/AGENTS.md`
- Marketing: `server/lib/tuist/marketing/AGENTS.md`
- MCP: `server/lib/tuist/mcp/AGENTS.md`
- Namespace: `server/lib/tuist/namespace/AGENTS.md`
- Oauth: `server/lib/tuist/oauth/AGENTS.md`
- Ops: `server/lib/tuist/ops/AGENTS.md`
- Projects: `server/lib/tuist/projects/AGENTS.md`
- Prom Ex: `server/lib/tuist/prom_ex/AGENTS.md`
- Registry (Swift Package Registry writer): `server/lib/tuist/registry/AGENTS.md`
- Remote Execution API Cache: `server/lib/tuist/reapi_cache/AGENTS.md`
- Repo: `server/lib/tuist/repo/AGENTS.md`
- Result Bundle: `server/lib/tuist/result_bundle/AGENTS.md`
- Runs: `server/lib/tuist/runs/AGENTS.md`
- Slack: `server/lib/tuist/slack/AGENTS.md`
- Storage: `server/lib/tuist/storage/AGENTS.md`
- Telemetry: `server/lib/tuist/telemetry/AGENTS.md`
- Utilities: `server/lib/tuist/utilities/AGENTS.md`
- Vault: `server/lib/tuist/vault/AGENTS.md`
- Vcs: `server/lib/tuist/vcs/AGENTS.md`
- Xcode: `server/lib/tuist/xcode/AGENTS.md`

## Related Context

- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations and seeds: `server/priv/AGENTS.md`
- Data export requirements: `server/data-export.md`

- Gradle ingestion, task rankings and execution details: [Gradle server context](gradle/AGENTS.md).
