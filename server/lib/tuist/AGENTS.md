# Tuist (Business Logic)

This directory contains the core business logic and domain modules for the server.

## Responsibilities
- Machine metrics retain nullable `offset_ms` from the activity log start during archive processing, independently of the upload timestamp, so recorded samples align with build steps. Older samples without offsets keep their standalone charts.
- `Tuist.Builds.Steps` serves paginated, filtered metadata and individual logs to the HTTP API and MCP. Both transports authorize build-read access first. IDs are decimal strings scoped to a build, and list queries never select log text. Availability distinguishes absent step data from a search with no matches.

- Ecto schemas, contexts, and domain services.
- `Kura.Origins` discards counts for deleted accounts when persisting a batch. It locks surviving account keys within the write transaction so concurrent deletion cannot invalidate the batch or discard other accounts' counts.
- External test ingestion uses `Tests.get_test_case_states_at/3` for historical quarantine attribution; current test controls continue using the current-state projection.
- Business rules for accounts, projects, bundles, previews, and analytics.
- Module-cache invalidation reads discover names with grouped aggregation, then batch independent module histories without splitting their date ranges. Window reads dictionary-encode repeated names and branches to bound memory. Dependency-graph reads identify the latest eligible commit before fetching its targets, preserve branch/environment filters and delayed uploads, and skip graph reads when no dependency edges exist. Blast radius is resolved after the module list is cut to its limit, so the graph is walked only for the modules a page shows and is not read at all for a page that shows none; the dependents time series reverses the graph once per distinct daily graph rather than once per day.
- Xcode build steps (`Tuist.Builds.Step`, `build_steps`) are collected by default for every processed Xcode build, for reuse across build analytics, retain only current-invocation leaf intervals for 90 days, are streamed from the parser sidecar through per-worker ClickHouse writes bounded by 8 MiB of encoded rows or 1,000 rows (an oversized individual row is written alone), and are read with retry deduplication. Each log has an independent 64 KiB allowance and preserves its beginning and end when truncated. `Tuist.Builds.Timeline` opens with the full build visible and permits zooming back out to the entire duration, loading all individual interval metadata once. Zoom, pan and search run locally; there is no range-loading endpoint. The metadata response derives its distinct project/target count from the fetched intervals without a second query. Keyboard navigation queries all steps; browser search reuses the initial full-build metadata. Parser telemetry ends before the consumer starts; ingestion has its own span. Logs share that retention and are fetched separately by build and event ID.
- Content-addressed Open Graph image rendering and shared object-storage caching.

## Boundaries

- Build ingestion no longer reads `feature_flags`. Its processor read grant in
  `Release` and `infra/cnpg/tuist-processor-grants.sql` remains for compatibility
  with older processor releases during rolling deployments and rollbacks.

- `ClickHouseDictionarySource` builds escaped local dictionary sources for migrations.
  Its query options suppress application SQL logging without overriding managed
  ClickHouse logging policy; server password masking requires valid dictionary DDL.

- Web controllers and LiveView code live in `server/lib/tuist_web`.
- Data migrations live in `server/priv`.
- `Processor.XCActivityLogParser` runs the MuonTrap executable through
  `System.cmd` in a timed task, collecting the parser's inherited stderr without
  MuonTrap's output acknowledgement protocol. This avoids `:epipe` on fast exits
  while retaining process cleanup when the task times out or its caller dies.
- `Processor.BuildProcessor` returns ZIP extraction errors to `ProcessBuildWorker`
  so Oban retries them and the final attempt marks the build as `failed_processing`.

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

- Module-cache miss classification compares reported direct inputs, including optional cache-key strings, effective destinations and other reported key inputs through a fingerprint map, before dependency hashes. Compare only optional map entries present on both observations: missing telemetry must not count as a direct change. Availability reads use the same bounded module-name batch as classification and shared ingestion margins.

- Module-cache Unavailable misses require an earlier reported remote hit for the exact artifact key in the same project and recorded cache endpoint. Local hits, partial-input matches, and later reports are not evidence of prior remote availability.

- `scw-fr-par-runners` uses two standard managed replicas and a stable private gateway hostname. `Regions.observed_private_endpoint?/1` identifies private gateway regions: activation, convergence and dispatch freshness must all use this predicate. The provisioner waits for `privateURL`, the current spec generation and fresh `endpointLastCheckedAt`; it never replaces that check with a rendered hostname. Keep the legacy NodePort service enabled during migration. Private replica and endpoint configuration changes must move the manifest revision so existing instances converge.

- `Provisioner.external_endpoint/1` returns `%{url: ..., observed_at: ...}`. Private activation/refresh must persist that controller observation in `last_ready_at`, not replace it with the server clock. Both validation and dispatch use `Regions.private_endpoint_staleness_seconds/0`; storage maintenance must not freeze this clock. Private gateway URLs must not override public URL helpers. Retained NodePorts serve already-dispatched jobs only.
