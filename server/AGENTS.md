# Tuist Server (Elixir/Phoenix)

PostgreSQL is the primary database; ClickHouse analytics writes use `IngestRepo`, reads use `ClickHouseRepo`.

## Development

- Run commands from `server/`. Use Mise and PostgreSQL 16 (`brew install postgresql@16` / `brew services start postgresql@16`).
- Bootstrap with `mise run clickhouse:start` and `mise install`; start with `mise run dev`. CLI integration uses `http://localhost:8080` by default; worktrees can have their own port.
- Dev secrets (OAuth, Stripe, etc.) are optional: `fnox.toml` sources the 1Password `Development` vault using an `op` session or `OP_SERVICE_ACCOUNT_TOKEN`. Without access the server boots with those integrations disabled.
- After dependency changes or in a fresh worktree, run `mise run install`; after pulling migrations, run `mix ecto.migrate`.
- Seed login: `tuistrocks@tuist.dev` / `tuistrocks`.
- `TUIST_DEV_DISABLE_DEBUG_ERRORS=1 mise run dev` renders real error pages instead of Plug.Debugger. `debug_errors` is compiled into `TuistWeb.Endpoint`; when flipping it, remove `_build/dev/lib/tuist/ebin/Elixir.TuistWeb.Endpoint.beam` or run `mix compile --force`.
- Origin app secrets include `ORIGIN_APP/app_id` and its independent Ed25519 PEM `ORIGIN_APP/private_key`. Keep the registered App ID beside its matching key; never hardcode or log private keys.

## Validation

- Prefer focused ExUnit runs: `mix test test/path/to/specific_test.exs`, `mix test test/path/to/test_file.exs:line_number`, or `mix test --only tag_name`.
- Tests compile only English and exclude `:locale` tests by default. Use `TUIST_DEV_ALL_LOCALES=1 mix test` (optionally with a focused path) to compile all locales and include those tests, as CI does.
- Dev compiles skip Boundary validation. Run `MIX_ENV=test mix compile` to check boundaries before pushing.
- Format with `mise run format`; lint with `mix credo`; security checks: `mix sobelow` or `mise run security`.
- For migrations, run `mix excellent_migrations.check_safety`; use `mix ecto.dump` when updating the database structure dump.

## Horizontal Scaling

- Every implementation must preserve horizontal scalability: requests and jobs must remain correct across multiple replicas, arbitrary request routing, rolling restarts and replica failure. Do not require sticky sessions or treat process memory, local files or ETS as authoritative shared state.
- Node-local caches are allowed when disposable and their freshness/invalidation contract is explicit. Preserve bounded authentication staleness and strict privacy/privilege checks; do not replace caching with expensive work or database reads on every request without evaluating load.
- Coordinate shared work through atomic operations in shared infrastructure, with explicit ownership, bounded waits and crash recovery. Prefer coordination independent of Erlang membership when possible. Cluster locks are only valid when discovery and partition behavior are part of the supported deployment contract. Verify actual provider semantics before relying on S3 conditional writes, Redis leases or database locks; expired owners must not release another owner's claim or overwrite its result.
- Make retried work idempotent and persist required work before acknowledging it. Supervision and graceful shutdown do not make in-memory work durable.
- Validate relevant cross-replica and failure scenarios, and consider cold starts, simultaneous cache expiry, CPU cost, database-pool pressure and shared-backend limits. Single-replica tests and warm-cache throughput alone do not establish horizontal scalability.

## Assets

- JS dependencies use aube. `mix assets.setup` installs server esbuild and local `noora` JS dependencies.
- `mix assets.build` builds local `noora` assets, then app/marketing/docs/apidocs bundles. Use `mix assets.deploy` for production assets.

## Elixir and tests

- Do not add typespecs (`@spec`, `@type`, etc.).
- Declare aliases at module level, never inside functions. Prefer aliases for reused modules; reserve imports for DSLs such as `Ecto.Query`.
- Use tagged tuples for recoverable failures.
- Timestamps: `:timestamptz` in migrations, `:utc_datetime` in `lib/`.
- Register mocked modules with `Mimic.copy` only in `server/test/test_helper.exs`, not in individual tests or functions.
- Tests default to `async: true`; avoid global state and change the architecture when necessary to support concurrency.
- Never mutate System environment variables in tests. Use mocks, stubs, or dependency injection for environment-dependent behavior.
- ExUnit files follow `test/**/module_name_test.exs`; tests set up a clean database.
- Comment complex or non-obvious logic and remove addressed TODOs.

## Translations

- Use `dgettext/2` for translatable text. Run `mix gettext.extract` after adding/changing or moving translated calls (CI checks source-line references) and commit only `.pot` templates alongside code; `translate.exs` and the `tuistit` bot manage translations.
- Never run `mix gettext.extract --merge` or edit `.po` files.
- Currency symbols and monetary amounts are not translatable; surrounding descriptions such as "and up" or "per unit" are. Example: `"0€ " <> dgettext("marketing", "and up")`.
- Catalog translation is incremental by source-message key; write each successful batch before the next request. Reuse Markdown translations only when source and context hashes match.
- Restore the unmerged `l10n/update-translations` branch with a three-way merge before model requests; conflicts stop the run before spending tokens. Save validated partial progress even when translation fails.
- Provider-wide failures stop queued batches across sources and locales; in-flight requests may finish. Keep the translation-step timeout shorter than the job timeout so partial progress can be saved.
- Run `elixir translate_test.exs` from the repository root when changing translation logic or branch recovery; it uses temporary local repositories.

## Dependency caching, build and test insights
- `mix compile` and `mix test` cache supported compiled dependencies and report to the hosted `tuist/server` project through the local `tuist_ex` package. `tuist: [project: "tuist/server", cache: true]` enables caching; the compile alias bootstraps `tuist_ex` and exposes its dependencies without compiling the rest before `tuist.compile` restores cached artifacts. Native/custom compilation and local dependencies still compile through Mix, and unavailable authentication or caching falls back to normal compilation. The test alias keeps database creation, timezone setup, and migrations before `tuist.test`.
- Authenticate locally with `mix tuist.login` (shares the Tuist CLI credentials). In CI, provide a project-scoped `TUIST_TOKEN` or authenticate with `mix tuist.login` using the CI provider's OIDC identity.
- `TUIST_PROJECT` and `TUIST_URL` override the destination. Reporting failures never fail a build or test run; set `TUIST_DEBUG=1` to diagnose them.
- `server.yml` builds once and runs four shards per ClickHouse variant. On a cold checkout, run `MIX_ENV=test mix compile --warnings-as-errors` before planning so the compile alias restores cached dependencies before Mix discovers the SDK task. Plan locally with `MIX_ENV=test TUIST_SHARD_REFERENCE=<unique-reference> mix tuist.test.build --shard-total 4`. On a cold shard, set `MIX_ENV=test`, `TUIST_SHARD_INDEX=<index>`, and `TUIST_SHARD_REFERENCE=<same-reference>`, then run `mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only`. Explicit path loading prevents Mix's task discovery from compiling unrelated dependencies after the OS workers finish the SDK. Run `mise run --no-deps db:reset -- --no-compile --no-deps-check` separately, then `mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download --warnings-as-errors`. Explicit `--no-download` execution bypasses the test preparation alias so it cannot recompile via ecto.create. The local `compile/1` alias also guards SDK bootstrap work on `--no-compile`; list aliases only pass flags to their last action. Separate database setup prevents migration-module redefinition warnings in regression tests. Match `TUIST_DEV_ALL_LOCALES` across the build and shards; CI sets it to `1`. GitHub jobs reuse the build job's reference even when only failed jobs are rerun, and use distinct `--scheme` labels for each ClickHouse variant.
- The hosted `tuist/server` project must be connected to the `tuist/tuist` GitHub repository for OpenID Connect credentials to authorize its reports and shard plans. If planning fails, separately named unprivileged jobs run both unsharded ClickHouse variants while the planner remains red.
- Local/CI ClickHouse keeps HTTP connections alive for 300 seconds and disables request-count rotation. The SQL sandbox's uncommitted rows belong to the driver's session; a transparent reconnect after ClickHouse's default 10,000 requests starts a different session and makes those fixtures disappear. Preserve both settings in `mise/tasks/clickhouse/start.sh`. The launcher also raises the server child's open-files soft limit to the available hard limit, best-effort like release startup, so inherited container limits do not make seeds fail with `EMFILE`. It logs the effective limit and leaves the caller's limits untouched. Run `bash ../.github/scripts/server-clickhouse.test.sh` for low/high/restricted limits, unsupported raises and already-running behavior.
- Concurrent local shards need separate `MIX_BUILD_PATH`, `TUIST_SERVER_TEST_POSTGRES_DB`, `TUIST_SERVER_TEST_CLICKHOUSE_DB`, and `TUIST_SERVER_TEST_PORT` values. Put the database and port overrides after `mise exec -- env` so the development-instance setup does not overwrite them. Leave `MIX_TEST_PARTITION` unset when overriding database names: legacy cross-database migrations append it themselves. For isolated local setup, invoke `bash mise/tasks/db/reset.sh` under those overrides instead of nesting `mise run`, which reloads and replaces the database environment.

## Data export documentation

Keep `server/data-export.md` current for all personal and organizational data so legal customer exports remain complete. Update it whenever a change:

- Adds or changes PostgreSQL/ClickHouse tables, customer-data columns, Ecto schemas/models, data relationships, or retention policies.
- Adds stored file types, categories or buckets; changes S3/object-storage keys or path structures, or upload/download processes.
- Collects new user fields, analytics/tracking, integration data, or customer-owned generated content.

Document data type and purpose, storage location (table or S3 path), relationships, retention, and export capabilities. Follow the existing format and verify the export process can actually retrieve the documented data.

## Marketing Site

The marketing site lives under `lib/tuist_web/marketing/` and is a single design:

- Controller pages render templates in `controllers/marketing_html/` (embedded by `TuistWeb.Marketing.MarketingHTML`); LiveView pages keep their template next to the module (`live/marketing_blog_live/blog.html.heex`); the shared navbar and footer live in `components/marketing_layout_components/` and are rendered by `TuistWeb.Marketing.MarketingComponents` from the marketing layout.
- Styles: `assets/marketing/marketing.css` is the single entry, served as `bundle.css` and built together with `bundle.js` from `marketing.js`. Page styles live under `assets/marketing/css/routes/`, layout styles under `assets/marketing/css/layouts/`, tokens and the page skeleton under `assets/marketing/css/shared/`.
- Page switches are cross-document view transitions with prefetch-on-hover (see the root layout); the navbar and footer hooks are mounted by `assets/marketing/js/lib/static-hooks.js` independently of LiveView, so they must not rely on LiveView-only hook APIs.
- Social cards are designed PNGs under `priv/static/marketing/images/og/`, served by `TuistWeb.Marketing.SocialCards`; per-item pages (blog posts, changelog entries, case studies, newsletter issues) keep their generated images.

## Metrics and Alerts
- PromEx plugins listed in `server/lib/tuist/prom_ex.ex` export the `tuist_*`
  metrics that `infra/helm/k8s-monitoring/alerts.md` documents rules for. Alert
  rules are created by hand in Grafana; that document is not provisioning.
- ClickHouse reads are measured by `Tuist.ClickHouseRepo.PromExPlugin` (count
  and duration by outcome) and LiveView async loads by
  `Tuist.LiveView.PromExPlugin`. Add the alert rule alongside a new metric:
  a metric nothing queries has its labels aggregated away by Grafana Cloud.
- `Tuist.Repo.PromExPlugin` exports pool pressure, query attempts by outcome,
  and connection-wait, execution, decoding, and total-duration histograms for
  PostgreSQL and ClickHouse in all runtimes. The `workload` label separates
  web, build processing, test-result processing, and registry synchronization.
  The Processor Service dashboard compares these workloads using the same
  measurements; execution time includes the network round trip.

## ClickHouse Query Parameters
- ClickHouse rejects requests with more than 1,000 HTTP form fields, one per
  query parameter. Every ClickHouse repository uses
  `Tuist.ClickHouse.ArrayInParams`, which binds an integer or binary
  `expr in ^list` (preloads included) as a single `Array(T)` parameter.
- A single parameter is capped at 128 KiB (roughly 3,000 UUIDs). Chunk lists
  whose size depends on data or on the client, as `all_by_uuid_chunks/2` in
  `Tuist.Tests` does, and never build an `or` of per-row equalities.

## CI build reuse

- The test builder, formatter and seed jobs retain ordinary `deps` and `_build` volumes. Always run dependency resolution and the required compilation/checks on warm caches; Mix owns invalidation.
- Shards download the exact build and disable compilation during database setup and explicit `--no-download` execution. Do not normalize checkout timestamps to hide invalidation. The guarded project-local compile function must skip SDK bootstrap as well. Load restored paths explicitly before discovering the test task, including in retry processes; discovery otherwise runs before forwarded flags can take effect.
- Keep the builder's `_build` volume plain. On main, current ClickHouse shards instrument their own downloaded builds with `--cover`; shards do not retain `_build` in a volume. This avoids copying builds or publishing instrumented BEAMs into the builder cache. The builder's volume also owns CLDR downloads, without a nested archive cache.
- `bash ../.github/scripts/server-db.test.sh` tests migration script forwarding and failure guards without databases.
- Docker's optional `mix-cache` context retains only the production builds of `tuist`, `tuist_common`, `tuist_ex` and `noora`, never test outputs or fetched/native dependencies. Keep `deps-builder` layer-cached; seed the four project directories through a read-only bind in the compile RUN and let Mix invalidate them normally. Export `mix-cache-export` before assets/release so no old release enters the snapshot. Ordinary builds use an empty seed and require no cache service.
- Keep the Docker `swift-artifacts` scratch stage between the Swift builder and runtime/release consumers. Only the parser executable and Swift runtime libraries belong there, so a cached build does not materialize the toolchain and `.build` tree just to copy shipped artifacts.
- Docker builds use the repository root context and `Dockerfile.dockerignore`, not `server/.dockerignore`. Keep every Dockerfile COPY input allowed, and exclude nested dependency/build directories and credentials. The fetched dependency stage copies only local package manifests and skips local compilation; local sources compile in the application stage. Preserve per-commit runtime security updates. Explicitly retain the public `priv/static/server/self-host/.env.example` after the general `.env*` exclusion; the Docker smoke test asserts it ships. Bare parent negations re-include their entire subtree, so keep the context allowlist narrow.

## Related Context (Downlinks)
- Isolated cluster discovery checks: [verification/AGENTS.md](verification/AGENTS.md).
- Activity log executable and streamed step protocol: [native/xcactivitylog_nif/AGENTS.md](native/xcactivitylog_nif/AGENTS.md).
- Business logic: [lib/tuist/AGENTS.md](lib/tuist/AGENTS.md).
- Web/UI layer: [lib/tuist_web/AGENTS.md](lib/tuist_web/AGENTS.md).
- Assets pipeline: [assets/AGENTS.md](assets/AGENTS.md).
- Configuration: [config/AGENTS.md](config/AGENTS.md).
- Migrations, docs and seeds: [priv/AGENTS.md](priv/AGENTS.md).
- Test conventions and regression contracts: [test/AGENTS.md](test/AGENTS.md).
- Grafana dashboards (Oban + others): [`infra/grafana-dashboards/`](../infra/grafana-dashboards/) (Git Sync'd with Grafana Cloud — see `infra/AGENTS.md`)

- Gradle and Bazel build detail pages reuse the shared build timeline. Source adapters expose recorded operations and explicit coverage; see `lib/tuist/gradle/AGENTS.md` and `lib/tuist/bazel/AGENTS.md`.

## Deployment

- Read [../infra/AGENTS.md](../infra/AGENTS.md) before shared-infrastructure work. Managed deployments use CAPI Kubernetes on Hetzner through Helm; chart and environment values live in `infra/helm/tuist/`.
- `.github/workflows/server-production-deployment.yml` cascades main through canary, acceptance tests, runners acceptance and the Kura rollout gate before production (with a hotfix fast path). Runners acceptance requires remote compilation-cache hits; `.github/workflows/runners-acceptance.yml` probes production runners and the BER1 rack hourly.
- Canary/production pin the newest `kura@X.Y.0-canary.N` in the deployed commit; the cascade calls `kura-release.yml` when Kura changed. Fresh staging builds its runtime from that commit. `kura_runtime_image_tag` overrides the pin in `server-deployment.yml`, which also supports single-environment manual deployments.
