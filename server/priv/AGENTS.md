# Server Private Assets (Migrations, Seeds)

This directory contains database migrations and other private assets.

## Origin integration
- Origin and github.com installs can start at the provider and finish in the shared organization chooser, skipped when only one eligible account exists; Tuist-initiated installs retain their selected organization. The self-hosting guide must include GitHub's additional `/integrations/github/authorize` OAuth callback URL. GHES still starts in Tuist's manifest flow. `marketing/changelog/2026.10.18-provider-initiated-installations.md` announces the provider entry points and organization chooser.
- `docs/en/guides/integrations/gitforge/origin.md` documents native-Origin account/project connections, reporting requirements, and user-facing permissions. Keep it focused on usage, without comparisons to other forges, token-minting internals, or managed-development infrastructure. App registration, key generation, callback/webhook settings, and environment variables belong in `docs/en/guides/server/self-host/server.md#platform-origin`, following the adjacent platform setup structure. Installation does not start CI. `origin_app_installations` stores account-owned installation/app/namespace IDs, not receipts or private keys.
- `marketing/changelog/2026.10.15-cursor-origin-integration.md` announces native Origin reports and uses the matching WebP under `static/marketing/images/changelog/`. Keep the screenshot's synthetic-demo disclosure and the distinction between reporting results and running workflows.

## Responsibilities
- Rust's onboarding and feature pages live under `docs/en/guides/get-started/rust-project.md` and the `rust.md` pages in build insights, test insights, flaky tests, and test sharding. Keep overview cards, support logos, and shared markdown rendering aligned. Write the getting-started page around developer tasks; explain nextest and agent-friendly mise wrapping in short callouts, and leave compiler/cache internals and unsupported-feature details to the feature guides. Document binary-level nextest concurrency using measured shard history, milliseconds for duration budgets, and the absence of quarantine enforcement and coverage selection. The overview and cache guide show Rust caching with an explicit experimental qualification and link to the build-insights cache measurements; do not imply production-qualified support. Rust alert titles use sentence case. The compilation cache is implemented in Swift within the CLI, not a bundled Rust helper. Document only its registry leaf-library subset and path-sensitive keys; do not retain claims about copied-engine verification or prefetch. The build-insights cache section also documents the project-level Cargo Cache dashboard, environment/date filters, measured transport widgets and recent-build drill-down; retain missing-versus-zero and experimental qualifications. Keep feature prose concise and user-facing, using the existing build-system pages as the pattern: short cache-tab guidance, actionable debug commands, and the shared flaky detection/management/quarantine/Slack structure rather than implementation checklists.
- `docs/en/guides/server/data-retention.md` is the public retention reference; keep it aligned with `server/data-export.md`, ClickHouse migrations, and artifact cleanup. Core Xcode build/test insights records have no time-based expiry, but build timeline steps and captured logs and machine metrics have 90-day database TTLs. Do not conflate those records with plan-based artifact-file retention.
- Explicit client actor-claim configuration and privacy/legacy-server compatibility are documented in the English Xcode, Gradle, and Elixir build-insights guides. Claims are off by default; Xcode post-actions need their own environment configuration. This header does not imply report persistence, dashboard support, or new authorization; the endpoint scrubs it from Sentry contexts.
- Grafana build-health setup, metric definitions, reporting limitations, and alert routing are documented in `docs/en/guides/integrations/grafana.md`. Keep this guide aligned with the Grafana plugin readme and link it in `lib/tuist/docs_sidebar.ex`.
- REAPI module-cache upload concurrency and admission retry settings are documented in `docs/en/guides/features/cache/module-cache.md`; keep them aligned with `cli/Sources/TuistREAPI` and Kura's upload sizing guidance.
- Xcode coverage prefix-mapping opt-ins and generated-project LLDB source namespaces are documented in `docs/en/guides/features/cache/xcode-cache.md`; keep the `xccov` compatibility warning and per-target mapping guidance aligned with the CLI.
- Generated-project dependency installation is documented in `docs/en/guides/features/projects/best-practices.md`, using the published `tuist/install@v1` action. Keep that guidance focused on prerequisites, a short workflow, automatic cache selection, default manifest settings, and subdirectory usage. Link to the action reference for advanced options; omit cache layouts, materialization details, key construction, and environment-filter internals from this best-practices page. Keep it scoped to generated projects, without fork-specific branches or canary pins. The cache-volume guide covers general runner behavior.
- Runner cache-volume usage belongs in `docs/en/guides/features/runners/cache-volumes.md`, linked from the runners overview and provider guides. Keep Docker-specific guidance in the Docker page. The docs sidebar is maintained in `lib/tuist/docs_sidebar.ex`.
- Persistent build inventories require PostgreSQL Once target mappings/publication marker and its concurrent unpublished-terminal-run index, then the ClickHouse observations/catalog/materialized view before enabling any project's `:build_entities` flag. Keep the flag default-off; `:build_entities_kill_switch` is the deploy-free stop. Observe ingestion rows, compressed bytes, merge backlog and query limits during an approved canary before expanding enrollment. No automatic backfill or production benchmark load.
- PostgreSQL migrations: `server/priv/repo/migrations`
- GitHub Enterprise split-host/proxy setup, App repository permissions, and webhook events are documented in `docs/en/guides/integrations/gitforge/github.md`. Document only the repository permissions and webhook events required for PR feedback, checking API usage in `Tuist.GitHub.Client` and event handling in `TuistWeb.Webhooks.GitHubController`; manual App setup belongs in the self-hosting guide. The nullable installation `api_url` is transport metadata; it does not replace canonical `client_url`, webhook identity, or existing project connections. Its migration uses `20261007160000`; the prototype `20261006110000` collided with main's absolute bundle-threshold migration. Reconcile any locally applied prototype history against the actual columns before migrating.
- ClickHouse migrations: `server/priv/ingest_repo/migrations`
- `mix_dependency_cache_events` retains local/remote dependency lookup and bypass observations for 90 days and deduplicates by project/build/dependency. Additive migrations store nullable successful bytes/microsecond durations and explicit local/remote I/O sources; legacy data stays null, not inferred. Remote timing measures client CAS transfers, local timing includes verification/installation; compilation is excluded. Shared Kura REAPI events supply real CAS output identities/counts and server throughput, never local-copy surrogates. Shared Elixir setup lives in `docs/en/guides/get-started/elixir-project.md`: `mix tuist.setup --project account/project` installs cold/parallel compile and test aliases and enables `cache: true` automatic structural dependency selection. Cache, build and test feature guides link back rather than duplicating installation/authentication/aliases. Retries and CI sharding remain optional. The Elixir sharding guide compiles through the generated alias in the test environment before discovering `tuist.test.build`, so a cold build does not compile dependencies before caching starts. The linked `elixir-advanced.md` covers selection/exclusions, declared inputs, shared Bazel auth/ActionCache/CAS, producer-path portability, artifact-embedded values, fail-open fallback and no automatic local eviction. Structural selection must not be described as automatic hermeticity. The advanced guide also documents negotiated ByteStream zstd on OTP 28+, identity fallback and uncompressed digest/byte accounting.
- Marketing changelog entries: `server/priv/marketing/changelog`. The preview improvements entry (`2026.10.15-preview-release-notes.md`) covers release-note summaries and full-notes search, counted iOS track filters, native refresh, and macOS discovery across branches. Its matching WebP uses a real iPhone 18 Pro simulator capture with the device's Xcode frame; retain the example-build disclosure and keep the served image within budget.
- Purpose-written agent marketing guides: `server/priv/marketing/agents`, see `marketing/agents/AGENTS.md` for content, discovery, and CDN rollout constraints.
- All served raster images under `priv/static` are checked by
  `mise run marketing:image-budget` (requires ImageMagick).
  Signup artwork is WebP at twice its rendered width; keep replacements within
  the 500 KiB static-image budget (GIFs allow 3200 KiB).
- Shared `hero-background*` images have a stricter 20 KiB budget and a maximum
  of 1024 pixels per dimension. Served derivatives are 960px desktop and 480px
  mobile; regeneration sources live outside the served tree in
  `server/assets/marketing/source-images`. Open Graph assets are resized to
  1200px wide while retaining their aspect ratio.

## Demo Data
- `repo/seed_cargo_xcode_cache_comparison.exs` replays recorded Xcode activity-log fixtures and accompanying CAS metadata through the production parser into the isolated Cargo/Xcode demo databases only. It preserves recorded task decisions, references, compiler/diagnostic data and Timeline steps; remote/download and cold/upload fixtures populate both cache inspection tabs. Stable IDs make reruns idempotent. `recorded-fixture` tags and custom source/recording metadata distinguish these replays from synthetic history and fresh builds. Build the parser with `native/xcactivitylog_nif/build.sh`, or set `TUIST_CACHE_COMPARISON_PARSER`; optionally reuse parsed output through `TUIST_CACHE_COMPARISON_RECORDS`. Do not invent missing CAS transfers, machine samples or archives. Cargo cache comparison records must come from actual `tuist cargo` captures, not counters copied into synthetic task rows.
- `repo/seed_cargo_xcode_shards.exs` adds seven matched synthetic sharded CI runs to each comparison project after their base seeds, including two/three-shard plans, varied balance, and a failed run. It backdates plans and reports for the shared Shards charts and records reports through `Tests.create_test/1` for merged runs and per-shard drill-down. Reruns retain existing plans/modules/reported shards. Synthetic plans have no downloadable archives; the real archive pipeline lives in `cli/Tests/Fixtures/CargoSharding/AGENTS.md`.
- `repo/seed_cargo_xcode_test_states.exs` adds matched healthy, flaky, flaky-muted, muted, and skipped scenarios to `cargo-demo` and `xcode-demo` after both comparison seeds. It uses `Tests.update_test_case/3` so audit events and current-state projections remain authoritative, and seeds seven synthetic CI histories per project without duplicating them on reruns. These are visual comparison scenarios, not claims of nextest quarantine enforcement.
- `repo/seed_xcode_comparison.exs` adds a public `tuistrocks/xcode-demo` project to the Cargo demo's isolated development database, with 42 synthetic builds and 42 test runs over two weeks. Run after `seed_cargo_analytics.exs`; reruns preserve existing data. It intentionally leaves unsupported demo categories, such as previews and cache activity, empty rather than inventing measurements; the separate recorded-cache replay seed fills cache activity from actual fixtures.
- `repo/seed_cargo_analytics.exs` seeds a public `tuistrocks/cargo-demo` project with synthetic compiler observations, diagnostics, nextest successes/failures/skips/retries, and a binary-level shard plan. Run it in an isolated development database. Existing demo data is retained on reruns; the script prints the dashboard URLs and local login credentials.
- Runner job steps use weighted durations that sum to the job duration, reserving at least one second for each remaining step in the seeded jobs.
- Gradle build seeds populate requested tasks from their generated task list, preferring assemble entry points. Keep build metadata consistent with the tasks shown in analytics.
- Coverage seeds give `tuist/tuist` a commit graph in `git_repositories` (a month of `main`, a merged branch with its merge commit, and an open pull request), a file listing per commit, runs carrying coverage for two schemes, and the published `coverage_commits`. They start from a clean graph on every run, so the trend is never two seedings deep, and they deliberately leave one commit unmeasured, one measured by a single scheme and the newest ones unsignalled, so the history shows a gap, a commit off the trend and a commit still waiting for its completion signal.
- The standard `repo/seeds.exs` creates `tuist/xcode-comparison` and `tuist/bazel-comparison` with matching test histories, including healthy, flaky, muted, and skipped cases. Keep their scenarios aligned for visual comparison; rerunning seeds preserves existing comparison runs.

## Guardrails
- Regenerate Gettext `.pot` templates with `mix gettext.extract` (without `--merge`) after moving translated calls as well as changing strings: CI checks source-line references too. Commit generated `.pot` changes only; never edit `.po` translations.
- If you change stored customer data, update `server/data-export.md`.
- Xcode 27.1 RC retirement uses forward-only, idempotent profile and unclaimed
  queued-job statements. Exclude claims by both reserved and executed job IDs.
  It requires an already-deployed stable chart plus post-rollout reconciliation;
  follow `infra/runner-image/xcode-27.1-retirement.md` at repository root.
- Use `:timestamptz` for migration timestamps (per Credo rules).
- REAPI cache output hints default to empty strings for historical rows and older Kura nodes. Append physical ClickHouse columns in schema order; these identifiers correlate profile descriptions and are never repository source links.
- The Origin installation migration creates indexes concurrently and validates its provider constraint separately after adding it without validation, so existing connection writes are not blocked by an index build or constraint scan. The installation column keeps its UUID type when its nullability changes.
- Migration filename versions must be unique within each repository. Check for collisions against main when adding migrations, and update explicit test file references if renaming a migration. Mix cache creation and I/O metrics use `20261009120100` and `20261010110100`; their prototype versions `20261009120000` and `20261010110000` collided with upstream migrations. Reconcile locally applied prototype history against the actual tables/columns before migrating.
- OAuth refresh-token lookups use the concurrent partial `oauth_tokens_refresh_token_index` on non-null `refresh_token`, independent of `client_id`. Preserve the upstream query shape, verify migration/rollback and index validity, and do not infer production capacity from synthetic query plans.
- Runner cache migrations create indexes concurrently with DDL transactions and
  migration locks disabled; verify both forward migration and rollback.
- Runner cache size measurements reference uses and cascade with their retention;
  historical observations must not be overwritten by subsequent agent reports.
- Declare table engines in new ClickHouse migrations through
  `Tuist.IngestRepo.Migration.engine/1`, as in
  `engine: Migration.engine("ReplacingMergeTree(inserted_at)")`, never as a
  literal. The in-cluster ClickHouse accepts only replicated engines, and
  `test/tuist/ingest_repo/migration_test.exs` fails on a literal `MergeTree`
  engine in any migration after `20260914120000`.
- Bound ClickHouse `INSERT SELECT` backfills with explicit read/insert thread,
  block-size, and query-memory settings, including catch-up passes. Copying
  one partition at a time alone does not bound their peak memory usage.
- Build a new skip index for existing parts with one asynchronous mutation per
  partition (`SchemaClone.partition_ids/3` and
  `SchemaClone.materialize_index_statements/4`, `mutations_sync = 0`), never a
  whole-table `MATERIALIZE INDEX`: retention does not bound how much one
  mutation does. `SchemaClone.reconcile/1` adds skip indexes a migration added
  to existing tables onto the in-cluster ClickHouse after every deploy
  (additive only), and logs and reports (`indices_mismatched`) an index both
  sides define differently instead of replacing it. On every run it also
  materializes the indexes listed in `@materialized_on_reconcile`
  (`gradle_builds.idx_id`, `mix_builds.idx_id`) in each partition that still
  has parts without index data, unless a materialization of that index is
  already pending; one that keeps failing is logged, not resubmitted. That
  detection reads per-part index sizes, so an allowlisted index must be its
  table's only skip index. Add an index there only when a hot read depends on
  it and the table is small enough to rebuild partition by partition.
- Tests reading `system.parts`, `system.data_skipping_indices` or
  `system.mutations`, or running `ALTER`, cannot use DataCase's ClickHouse
  transaction: use `ExUnit.Case, async: false` with
  `Sandbox.start_owner!(Tuist.IngestRepo, shared: true, sandbox: false)` (see
  `test/tuist/clickhouse/schema_clone_materialization_test.exs`).
- Add marketing changelog entries only for customer-facing product changes that are ready to announce.
- Do not add product changelog entries for ops-only, admin-only, internal rollout, infrastructure-only, or otherwise unannounced functionality.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`

- GitLab runner assignments retain encrypted execution payloads temporarily; migration changes must preserve the documented cleanup and disjoint job-ID range. Connections are unique per account and instance URL; routing errors are retained as non-secret assignment metadata.


- The runner Kura sizing enrollment migration pins live, previously unpinned `scw-fr-par-runners` rows immediately to the account-sized claim or current plan default, capped at the historical 50Gi. This intentionally allows cache eviction to release scheduler reservations without waiting for measured shrink confirmation. Growth still requires normal admission. The migration locks only enrollable rows, validates every selected claim before writing, and rejects unsupported quantities rather than silently substituting a budget. Plan defaults are frozen historical values so replay is deterministic; future changes need a new migration or measured sizing. Rollback retains the applied pins to avoid restoring the scheduling blockage.
- Gradle and Xcode build start timestamps are nullable for backward compatibility and use `Nullable(DateTime64(6))` in ClickHouse. They align recorded operations and machine samples; no upload-time backfill is valid. Xcode `build_runs.started_at` comes from the activity log's Apple-reference timestamp; `inserted_at` remains unchanged as the creation timestamp and partition/cursor key.

- GitLab live-assignment expiry and connection lookups use concurrent partial indexes restricted to `payload IS NOT NULL`; retain historical metadata without making polling scan completed jobs.

- Migration versions must be unique within each repository even when already applied. The GitLab routing migration uses `20260911080000`; its prototype `20260910160000` collided with main’s Bazel profile migration. Any prototype database needs its version history reconciled against the actual schema before migrating.

- Runner Kura enrollment uses `20260911090100` after its incoming main-branch migration collided with Bazel’s `20260910160000`. Re-execution is safe: enrollment selects only live rows without an existing storage pin.

- Automation `event_generation` is nullable and falls back to `baseline_generation` for historical rows. It preserves recovery history across one-time action requests and cancellation; condition changes advance both generations. Keep attempt revision checks separate from event queries.

- Cache-volume image publication adds nullable digests and published generation,
  plus a base HEAD generation defaulting to zero. This is separate from the
  invalidation epoch; schema rollback follows local-image fleet cleanup.
  Its version is `20260924130000`; the prototype `20260923120000` collided with
  main's account cache-meter migration. Prototype databases need their migration
  history reconciled before either migration runs; verify the corresponding
  columns instead of assuming which migration the old version represents.

- Kura identity backfill is forward-only: audit historical provisioner references and reservation collisions before deployment. Unknown/conflicting references abort; never guess a live volume namespace. See `kura/docs/account-renames.md` at repository root.

- Kura client URL expiry is separate from handle ownership: `client_url_expires_at` is set to 90 days when a name is retired, cleared on rename-back, and never deletes its reservation. Historical names with unknown rename dates get 90 days from the expiry migration. Both migrations are forward-only.

- Keep Grafana documentation organized around metric tables, with build-system differences, query options, and setup in separate sections. Document where shared failure categories and Gradle cache estimates also appear in native dashboards.

- The platform expansion initially retains the legacy seven-column unique
  index. `20261007150000_enable_macos_cache_volumes.exs` removes it concurrently
  after platform-aware server rollout. Its rollback requires macOS allocations
  disabled, jobs drained and macOS data/metadata reclaimed before recreating the
  legacy index. Do not roll back to pre-platform server images after enablement.

- The Grafana guide distinguishes the neutral percentile-based failed-or-slow metric from explicit duration targets, documents paired cache savings/coverage, and points native failure classification to build details and category filters rather than default table columns.

- Cache-volume writer policy adds an empty-default exact branch list on volumes and auto-default commit intent and nullable additional-branch grant provenance on uses. Preserve existing volume identity, clear epochs and default-branch permissions; document policy data in the export inventory. `runner_cache_volume_uses.commit_mode` and `runner_cache_volumes.writer_branches` are no longer read.
