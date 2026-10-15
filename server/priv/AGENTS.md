# Server Private Assets (Migrations, Seeds)

This directory contains database migrations and other private assets.

## Responsibilities
- Rust's onboarding and feature pages live under `docs/en/guides/get-started/rust-project.md` and the `rust.md` pages in build insights, test insights, flaky tests, and test sharding. Keep overview cards, support logos, and shared markdown rendering aligned. Write the getting-started page around developer tasks; explain nextest and agent-friendly mise wrapping in short callouts, and leave compiler/cache internals and unsupported-feature details to the feature guides. Document binary-level nextest concurrency using measured shard history, milliseconds for duration budgets, and the absence of quarantine enforcement and coverage selection. The overview and cache guide show Rust caching with an explicit experimental qualification and link to the build-insights cache measurements; do not imply production-qualified support. Rust alert titles use sentence case. The compilation cache is implemented in Swift within the CLI, not a bundled Rust helper. Document only its registry leaf-library subset and path-sensitive keys; do not retain claims about copied-engine verification or prefetch. Keep feature prose concise and user-facing, using the existing build-system pages as the pattern: short cache-tab guidance, actionable debug commands, and the shared flaky detection/management/quarantine/Slack structure rather than implementation checklists.
- REAPI module-cache upload concurrency and admission retry settings are documented in `docs/en/guides/features/cache/module-cache.md`; keep them aligned with `cli/Sources/TuistREAPI` and Kura's upload sizing guidance.
- Runner cache-volume usage belongs in `docs/en/guides/features/runners/cache-volumes.md`, linked from the runners overview and provider guides. Keep Docker-specific guidance in the Docker page. The docs sidebar is maintained in `lib/tuist/docs_sidebar.ex`.
- PostgreSQL migrations: `server/priv/repo/migrations`
- ClickHouse migrations: `server/priv/ingest_repo/migrations`
- Marketing changelog entries: `server/priv/marketing/changelog`
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
- If you change stored customer data, update `server/data-export.md`.
- Use `:timestamptz` for migration timestamps (per Credo rules).
- Migration filename versions must be unique within each repository. Check for collisions against main when adding migrations, and update explicit test file references if renaming a migration.
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
- Add marketing changelog entries only for customer-facing product changes that are ready to announce.
- Do not add product changelog entries for ops-only, admin-only, internal rollout, infrastructure-only, or otherwise unannounced functionality.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`

- GitLab runner assignments retain encrypted execution payloads temporarily; migration changes must preserve the documented cleanup and disjoint job-ID range. Connections are unique per account and instance URL; routing errors are retained as non-secret assignment metadata.


- The runner Kura sizing enrollment migration pins live, previously unpinned `scw-fr-par-runners` rows immediately to the account-sized claim or current plan default, capped at the historical 50Gi. This intentionally allows cache eviction to release scheduler reservations without waiting for measured shrink confirmation. Growth still requires normal admission. The migration locks only enrollable rows, validates every selected claim before writing, and rejects unsupported quantities rather than silently substituting a budget. Plan defaults are frozen historical values so replay is deterministic; future changes need a new migration or measured sizing. Rollback retains the applied pins to avoid restoring the scheduling blockage.
- Gradle build start timestamps are nullable for backward compatibility and use `Nullable(DateTime64(6))` in ClickHouse. They align recorded operations and machine samples; no upload-time backfill is valid.

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
