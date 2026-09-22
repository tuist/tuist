# Tuist (Business Logic)

This directory contains the core business logic and domain modules for the server.

## Responsibilities
- Metric automations accept a one-time `trigger_config.apply_actions_to_existing_matches` request on create/update. A fresh request starts a baseline generation even when the condition is unchanged. Baselines recheck matches in bounded batches and serialize publication per alert with a session advisory lock. Each action runs outside a row-lock transaction, between a short preflight check and a durable checkpoint; edits may cancel the remaining work while an authorized action finishes. Clear the request on completion. Silent publication deduplication tokens include the sorted test ID set so changed payloads on retry are not dropped. Read-only match counts enumerate bounded pages and share the baseline metric, trusted-branch validation, and current-state eligibility logic. Condition edits require a fresh opt-in. Omitting the request preserves pending work; explicit false cancels remaining actions. Baseline attempt generations invalidate stale workers; nullable `event_generation` separately scopes recovery history (falling back to `baseline_generation` for existing rows), so opt-ins and cancellations retain active recovery events. Returned action errors are logged and checkpointed without publishing a successful trigger, allowing the baseline and subsequent evaluation to progress.
- Build task summaries can omit CAS-output ID arrays. Expanded-task lookups resolve those arrays inside ClickHouse using both build ID and task key, group duplicate outputs by node ID, and return 20 rows plus a next-page indicator. Neither request parameters nor task summaries should carry the stored ID arrays.
- Machine metrics retain nullable `offset_ms` from the activity log start during archive processing, independently of the upload timestamp, so recorded samples align with build steps. Older samples without offsets keep their standalone charts.
- `Tuist.Builds.Steps` serves paginated, filtered metadata and individual logs to the HTTP API and MCP. Both transports authorize build-read access first. IDs are decimal strings scoped to a build, and list queries never select log text. Availability distinguishes absent step data from a search with no matches.

- Ecto schemas, contexts, and domain services.
- `Kura.Origins` discards counts for deleted accounts when persisting a batch. It locks surviving account keys within the write transaction so concurrent deletion cannot invalidate the batch or discard other accounts' counts.
- External test ingestion uses `Tests.get_test_case_states_at/3` for historical quarantine attribution; current test controls continue using the current-state projection.
- Xcode code coverage (`Tuist.Tests.XcodeCoverage`) is tool-specific. Coverage is read from the result bundle by the shared Swift parser (`xccov` report + archive) wherever the bundle is processed: the macOS xcresult processor for uploaded bundles (the CLI writes a `tuist_coverage_manifest.json` with root spellings, the covered files' Git blob ids and a partial flag into the bundle), or the client in local mode (sent as `xcode_coverage`). `xcode_coverage_files` holds one row per file per shard report with per-line execution counts and function arrays; a report's rows share `inserted_at`, readers use only each shard's latest report (so retries replace rather than add), and merge shards per path as the union of lines. Shards report concurrently, so nothing rewrites merged totals on `test_runs`: the run page derives them from the reports, and each report publishes its totals over the shards reported so far to `xcode_coverage_runs`, versioned by shards included then newest report, which the trend reads with `argMax(…, version)`; those totals stay partial until every shard of the plan reported coverage. Only the repository's own code is kept: the parser drops files outside the checkout and dependency checkouts (`.build`, DerivedData, SourcePackages, Pods, Carthage), and in a Git checkout any file Git ignores. Test code (files only `.xctest` bundles compiled, flagged `is_test` by the parser from xccov's `buildProductPath`) is stored with counts only (no line or function arrays) and excluded from totals, targets and files. Local-mode uploads are deflate-compressed by the CLI. Partial runs (tests skipped on purpose) are labelled and excluded from the trend: coverage is never borrowed from other runs, since file-level evidence cannot be reused without per-test attribution. The whole feature is in early access behind `Tuist.FeatureFlags.xcode_coverage_enabled?/1` (FunWithFlags `:xcode_coverage` per account on canary/production, on elsewhere): ingestion drops `xcode_coverage`, the xcresult processor removes the manifest before parsing, and the run page tab and tests overview widget are hidden when it is off. Gradle coverage gets its own model rather than a generic one.
- Internal Slack delivery succeeds only when Slack returns `ok: true`; API errors must propagate to reporting workers even when the HTTP status is 200.
- Business rules for accounts, projects, bundles, previews, and analytics.
- Module-cache daily hits, misses, miss reasons and distinct module counts can be derived from the full invalidation breakdown with `module_timeseries_from_breakdown/2`. Derive these before filtering out hit-only modules or applying a list limit; count a module name once across products within the selected cohort. The old raw `module_invalidation_timeseries/1` and `modules_timeseries/1` queries are retained solely as independent test oracles.
- Module-cache miss reasons use `changed`, `upstream`, `cold`, and `evicted` consistently in SQL, result maps, and filters. Module-cache invalidation reads discover names with grouped aggregation, then batch independent module histories without splitting their date ranges. Window reads dictionary-encode repeated names and branches to bound memory. Dependency-graph reads identify the latest eligible commit before fetching its targets, preserve branch/environment filters and delayed uploads, and skip graph reads when no dependency edges exist. Blast radius is resolved after the module list is cut to its limit, so the graph is walked only for the modules a page shows and is not read at all for a page that shows none; the dependents time series reverses the graph once per distinct daily graph rather than once per day.
- Xcode build steps (`Tuist.Builds.Step`, `build_steps`) are collected by default for every processed Xcode build, for reuse across build analytics, retain only current-invocation leaf intervals for 90 days, are streamed from the parser sidecar through per-worker ClickHouse writes bounded by 8 MiB of encoded rows or 1,000 rows (an oversized individual row is written alone), and are read with retry deduplication. Each log has an independent 64 KiB allowance and preserves its beginning and end when truncated. `Tuist.Builds.Timeline` opens with the full build visible and permits zooming back out to the entire duration, loading all individual interval metadata once. Zoom, pan and search run locally; there is no range-loading endpoint. The metadata response derives its distinct project/target count from the fetched intervals without a second query. Keyboard navigation queries all steps; browser search reuses the initial full-build metadata. Parser telemetry ends before the consumer starts; ingestion has its own span. Logs share that retention and are fetched separately by build and event ID.
- Content-addressed Open Graph image rendering and shared object-storage caching.

## Boundaries

- Application startup and shutdown ordering: `server/lib/tuist/application/AGENTS.md`.

- Bazel profile processing needs `SELECT` on `bazel_profile_uploads` and
  `UPDATE` on `compressed`, `state`, `error`, and `updated_at`. Keep the
  migrate-time processor grants and CNPG fallback SQL in sync; profile upload
  creation and expiration remain web-runtime responsibilities.

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
- `Processor.BuildProcessor` maps known archive-corruption errors from
  `:zip.unzip` (`:bad_eocd`, `:bad_eocd64`, `:bad_central_directory`,
  `:bad_local_file_header`, and per-entry `:bad_crc`) to
  `{:error, :corrupt_archive}`. `ProcessBuildWorker` discards those jobs on
  the first attempt and marks the build as `failed_processing` right away,
  since the archive is a bad upload and retries won't heal it. Other
  extraction errors still bubble up as `{:error, reason}` so Oban retries
  them and the final attempt marks the build as `failed_processing`.

## Related Context (Downlinks)

- Runner shadow-scheduler snapshot: `server/lib/tuist/runners/shadow/AGENTS.md`.

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

- Kura's moderate retention correction supplements the existing 30-day shrink: 14 complete post-resize days with snapshots, at least seven meaningful eviction days and two ring budgets of turnover can reduce the account claim by 10–25%. Discount known idle whole days from shed age and ring span; require at least 4.5 days of adjusted retention and project toward the 3-day floor plus 25% headroom. Today's short or unmeasured evictions veto the correction, and every known pinned region must supply a shrink verdict. Neither a smaller region's pin nor a deeper shrink elsewhere bypasses the 25% correction cap. Every apply restarts the evidence window, including when it only converges regional pins. Retain the slower occupancy and clearly excessive-retention paths.

- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations and seeds: `server/priv/AGENTS.md`
- Data export requirements: `server/data-export.md`

- Gradle ingestion, task rankings and execution details: [Gradle server context](gradle/AGENTS.md).

- `Builds.RecordedSteps` exposes Gradle and Bazel timeline metadata through authorized API/MCP callers. These adapters reuse source records rather than copying them into Xcode `build_steps`. Opaque IDs remain scoped to the authorized parent; unavailable logs are null.

- Module-cache miss classification compares reported direct inputs, including optional cache-key strings, effective destinations and other reported key inputs through a fingerprint map, before dependency hashes. Compare only optional map entries present on both observations: missing telemetry must not count as a direct change. Availability reads use the same bounded module-name batch as classification and shared ingestion margins.

- Module-cache Unavailable misses require an earlier reported remote hit for the exact artifact key in the same project and recorded cache endpoint. Local hits, partial-input matches, and later reports are not evidence of prior remote availability.

- `scw-fr-par-runners` uses two standard managed replicas and a stable private gateway hostname. `Regions.observed_private_endpoint?/1` identifies private gateway regions: activation, convergence and dispatch freshness must all use this predicate. The provisioner waits for `privateURL`, the current spec generation and fresh `endpointLastCheckedAt`; it never replaces that check with a rendered hostname. Keep the legacy NodePort service enabled during migration. Private replica and endpoint configuration changes must move the manifest revision so existing instances converge.

- `Provisioner.external_endpoint/1` returns `%{url: ..., observed_at: ...}`. Private activation/refresh must persist that controller observation in `last_ready_at`, not replace it with the server clock. Both validation and dispatch use `Regions.private_endpoint_staleness_seconds/0`; storage maintenance must not freeze this clock. Private gateway URLs must not override public URL helpers. Retained NodePorts serve already-dispatched jobs only.
- GitLab runner acquisition and credential boundary: `server/lib/tuist/runners/gitlab/AGENTS.md`. Shared runner-reported logs and billing live in `Runners.JobReports`.


- Kura capacity admission refuses on two readings that are not interchangeable. `Capacity.pressure_line_gib/1` is region-wide and says the region is out of room (`:capacity_exhausted`, answered by another machine). `Capacity.placeable?/2` is per node and says the scheduler cannot place the instance's replicas where their local volumes pin them (`:capacity_unplaceable`, answered by moving the instance or freeing that box). Free space and the instance's own replicas come from one node-wide reading, the same one `room_for?/2` uses, so a resize counts back only what that reading already charged. Each box is charged for every declared replica no other box holds, because a replica mid-rollout is in no pod list but its volume brings it back. A per-node reading that is missing admits: a false refusal there blocks every claim growth in the region and shows up nowhere the account would see.

- An account's Kura claim has one resolution, `PlacerClaims.effective_claim_size/1`: the largest claim pinned on its live storage-governed instances (volumeless statuses excluded), then the sized claim in `kura_placer_claims`, then the plan default. Provisioning, cold returns, warm-handoff targets, runner caches and the claim sizing baseline all read it, so an expansion is built at the claim sizing measures. Do not resolve a new instance's claim from the sized row alone: pins without a sized row exist, and a smaller ring in one region shortens retention for content replicated from the others until sizing raises it. The sweep reads the same inputs in batch through `PlacerClaims.region_claims/1` and `resolve_claim_size/3`.

- `ClaimSizing` measures each region against the claim pinned in that region, never the account's largest pin: that pin funds the ring the region's rollups describe, and scaling a 16Gi ring's shortfall by a 50Gi pin sizes it as if it ran 50Gi. The account still has one claim. A growth whose target the account's claim already covers recommends that claim, so a region pinned under it is raised rather than left short, and applying any proposal moves every volume-holding governed instance to the recommendation in one transaction, raising some and lowering others, and rewrites the sized row so the evidence window restarts. Shrinking reads occupancy for a ring that never fills and retention for one that rotates: every region kept what it shed for three retention floors on every day of 30. A retention shrink projects from each region's own pin and shortest span, at most halves the claim in a step unless another region already runs the account on a smaller claim with that retention, and never goes under the plan's starting claim. Keep a shrink slower to confirm than any growth. Today's live row is passed over by a shrink window only while it has measured nothing against the shrink: one that already evicted (occupancy) or shed content younger than the threshold (retention) vetoes it. `ClaimSizingWorker` tries every open proposal, growths first, and spends its hourly budget only on applies that land, so proposals the cluster keeps refusing cannot starve the ones behind them.

- Runner Kura participates in account disk sizing and plan memory/CPU profiles. New and returning instances pin the account claim; the enrollment migration immediately pins unpinned live runner instances to their account-sized claim (or plan default), capped at the historical 50Gi to avoid bypassing growth admission. The runner pool does not advertise `tuist.dev/memory-ceiling-mib`, so keep `memory_ceiling_bin_packed` disabled there. The region retains a conservative 50Gi accounting fallback for legacy rows without a pin or loaded account; governed creation and cold return pin the sized account budget before rendering. Disk sizing remains account-scoped across public and runner regions, including their telemetry and resize history.

- Cache-endpoint resolution with no Kura endpoint enqueues `Workers.ProvisionOnDemandWorker` (one per account at a time), which runs `Lifecycle.provision_account/2` with the tick's eligibility rules, applies each instance coming up via `Reconciler.reconcile_server/1`, and hands it to `Workers.AwaitActivationWorker`, which checks `Reconciler.activate_when_ready/1` about twice a second and never applies. Activation asks whether the public host's record is published through `Tuist.DNS.record_published/1`, which queries the zone's authoritative nameservers instead of the pod's caching resolver. The tick hands every `:provisioning` server whose deployment it applies to the same worker; rollouts of serving instances are not polled. The minute tick stays the authority for everything these paths miss.
- `Kura.Lifecycle` reclaims an active public instance that has stored nothing since it entered service after `Environment.kura_air_unused_hours/0` (24 hours) on Air or `Environment.kura_unused_days/0` (seven days) on Pro, checked hourly by default. Air caps the unused-path tracking grace at its unused window; inactivity and Pro retain the full tracking grace. Enterprise and keep-warm instances remain exempt. The evidence is `kura_storage_rollups` covering the whole service life: snapshots on every full day since the service start (also the first day and today for Air), and no day with live segment bytes or evictions. Missing telemetry is never read as empty. An `:unused` archival is provisioned again only by demand recorded after it, and the project-creation seed declines while `Demand.unused_hold?/1` holds.
