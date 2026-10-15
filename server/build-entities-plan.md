# Persistent build entity detail pages

Status: agreed with Claude; implementation complete and validated.

## Goal

Give recorded build entities project-scoped URLs independent of a build,
invocation or command. The dashboard follows the test-case detail pattern.
Generic vocabulary stays internal: public routes, response keys and MCP tools
use Tasks, Cache actions, Modules, Actions and Files as appropriate.

## What we learned from test cases

- `Tests.generate_test_case_id/4` computes identity before writing.
  `TestCase.Buffer.insert_all/1` batches ClickHouse writes. There is no
  PostgreSQL upsert per case.
- The test-case catalog and executions have different read requirements.
  A build entity needs a project/entity/time prefix for history and analytics.
- Test ingestion reads prior cases to carry rolling durations and environment
  timestamps forward. We do not need that read-before-write: identity is a
  pure function and catalog first/last seen are mergeable database aggregates.
- Test IDs concatenate fields with a delimiter. New identities instead use
  versioned length-prefixed components, avoiding delimiter ambiguity.
- The test duration aggregate migration documents that replacing a source row
  does not undo its earlier average or quantile contribution. Counts can use
  distinct execution IDs, but distributions must deduplicate before aggregating.
- Large identifier sets need bounded single-array parameters. Backfills need
  explicit memory/thread/block-size bounds, not merely partitioned reads.

## Agreed storage design

### A slim observation index

Add `build_entity_observations` in ClickHouse, ordered by:

```
(project_id, system, kind, entity_id, id)
```

Use the repository's replicated-engine helper with
`ReplacingMergeTree(inserted_at)`. Producers compute both IDs in process and
append through the existing ingestion buffer. No identity lookup, per-action
Postgres upsert, or cross-database read is added to ingestion.

An observation carries the native identity/display name, parent/execution IDs,
recorded outcome, a separate cache outcome, nullable duration, branch, commit,
nullable CI/local attribution and observation time. It does not duplicate logs,
command lines, source arrays or CAS output arrays. Repeated metadata compresses
within the entity-sorted index and feeds the catalog materialized view.

Native fact tables remain authoritative for individual execution details. The
extra index is justified because those tables are ordered by parent run rather
than persistent entity; Once's native actions are additionally in PostgreSQL.
History across them otherwise requires multiple projections and a cross-store
query layer.

### An idempotent catalog

Add `build_entities` with `AggregatingMergeTree` and a materialized view from
observations. Use min/max for first/last seen and observed-time `argMax` for
names. Never use insertion-order `anyLast`, which lets a delayed report replace
newer presentation data. Identity is immutable for a given entity ID.

There is **no daily average/percentile materialized view** in this change.
Inventory reads the catalog; per-page observation counts and entity detail
metrics read a bounded, deduplicated observation cohort. `FINAL` resolves the
whole replacement row before time/cohort filters, including catalog membership,
so corrected or delayed reports cannot leave stale cohorts behind. Observed
time is not in the replacement key, because a replay may correct it. Readers
pin cross-partition replacement and disable pre-FINAL non-key PREWHERE/skip-index
filtering. Native parent tables retain their latest `argMax` tuples. In-order
catalog aggregation, two query threads, bounded blocks/streams and external
aggregation/sort spill keep reads bounded. Entity/page reads have a 256 MiB/20-second ceiling; kind-wide reads have
a 512 MiB/30-second ceiling. Client timeouts allow five extra seconds. Time or
memory exhaustion is an explicit 503/tool/card error, not a zero or empty cohort.
An idempotent rollup can be introduced later if measured query volume warrants it.

### Retention

Observation retention follows existing sources: 30 days for generated Xcode
modules and 90 days for the other kinds. Catalog identity metadata expires after
365 days without an observation. A bookmark can therefore outlive its original
build, but is not promised to survive the catalog's inactivity retention.

## Identity contracts

| Toolchain | Public entity | Identity |
| --- | --- | --- |
| Gradle | Task | Root project, build path, task path, task type |
| Xcode generated projects | Module | Xcode project name and target name |
| Xcode | Cache action | Compiler kind and exact cache key |
| Bazel | Cache action | Action digest hash, reported mnemonic and target label |
| Once | Action | Reported stable target ID, capability and declared action index |
| Mix | File | Reported repository-relative path |
| Mix | Module | Qualified module name |

Names, branch, environment and parent run are not identity components.
Missing Gradle scope/type fields remain empty; do not guess a root build.
Diagnostic Once identifiers are display labels, not stable identities. Persist
`TargetInstance` and `TargetQueued` mappings already present in the protocol to
attribute declared actions. Missing mappings leave legacy actions unattributed,
without rejecting their reports. Reordering declared Once actions changes their
slot identities.

Xcode and Bazel cache pages explicitly inspect **exact input variants**, not a
logical operation across changing inputs. Grouping descriptions or mnemonics
alone would merge unrelated work. Logical-action pages require a separate,
unambiguous telemetry contract. Bazel CAS blob events must not become action
observations. The digest field is called `action_digest_hash` in the new native
identity; existing APIs retain their original names.

Mix module observations carry their containing file's compile duration, clearly
labelled as such. They are not independently measured module durations and must
not be summed as additional compilation work.

## Read and transport contract

`Tuist.BuildEntities` exposes project/system/kind-scoped `list`, `get`, `history`
and `analytics`. Kind strings are checked against a fixed contract map without
creating atoms from input. IDs include the project, system, kind and identity
version. Unknown IDs and wrong-project/wrong-toolchain IDs are not found.

Detail metrics deduplicate observation IDs before counts, averages and
percentiles. Outcome and cache result remain separate. Missing timings and
unknown cacheability do not become zero durations or misses. Hit rate is null
without known lookup results, zero for all misses and 100% for all hits.

Default newest-first history uses keyset cursors over observation time and ID.
Dashboard timestamp/duration sorting uses bounded numbered pages for other
orders, with stable tie breakers and missing durations last. Search and native
outcome/cache/branch filters apply to resolved latest observations before
pagination, not to the five displayed recent rows. REST and MCP expose
bounded period, environment/branch and pagination inputs through a shared
parser. Native-named resources return stable IDs, analytics and native-named
history collections (`executions`, `cache_events`, `compilations`). GET details
never require a parent run identifier.

## Dashboard

Use one internal LiveView and native labels. Include a back button, name and
identity badges, Overview and native History tabs, an asynchronous Analytics
card, environment/date header controls, selectable observations/cache-hit-rate/
duration widgets, charts, recent activity and paginated history. Recent activity
and History share Noora search, sorting, Branch/Outcome/Cache filters and active
chips. As on Test Case Runs, toolbar, chips, table and pagination share one
white card section on inventory and detail pages, not separate bordered
surfaces. Keep the Branch input out of the analytics header. Match the compact,
left-aligned analytics legend and full-width chart section. History links
back to the appropriate recorded build, task execution, invocation or command.
Bazel cache-only observations stay visible even without a BEP invocation report.
One bounded parent-ID lookup per history page enables links only for invocation
reports in the selected project; unavailable optional link metadata never hides
cache observations. Inventory/detail navigation preserves view filters. The Gradle inventory links
to the retained task-ranking page instead of making legacy analytics unreachable.

Inventories use native labeled scope columns instead of a concatenated Identity
field. Gradle separates root project, build path and task type, and formats `:`
as Root build. Xcode/Bazel cache actions expose compiler/key or target/mnemonic/
digest, Once exposes target/capability/index, and file/module identifiers are
not repeated in a separate column. A differing primary identifier remains in
Noora's name-cell sublabel. Detail badges use the same scope formatting. Xcode and Bazel navigation, back buttons and inventories use Actions/Action;
the cache-action API/MCP names and exact-key/cache-timing semantics remain.
Header explanations share Noora's regular small body font and secondary label
color, including the Mix module compilation note. These are presentation changes
only: stored identities, URLs, search and API/MCP contracts are unchanged. Inventory pagination is numbered; cursor-backed
history retains Previous/Next controls.

Successful analytics remain mounted during refresh. Table pagination and
widget changes reuse the current date snapshot and analytics; changing entity
identity clears retained data. Filters remain usable on loading/error/empty
states. No test-only flakiness/quarantine controls are copied.

### Chart follow-up

After comparing Xcode Builds, Xcode Cache and Tests with Claude, and receiving approval:
- Retain count bars. A scatter plot of one dot per execution adds little to a
  count. Outcome-stacked bars are a separate enhancement requiring native
  status/cache buckets; do not label non-failures as successes or hide writes.
- Retain weighted cache hit-rate lines. Individual entity observations usually
  have binary hit/miss outcomes, unlike whole-build hit-rate scatter plots.
  Show hits/misses and their denominator in tooltips; show markers and break
  lines over buckets without lookups rather than implying a measured rate.
- Duration now reuses the existing Line / Scatter plot toggle, with Line as
  the default. Scatter loads only when selected, excludes unmeasured durations
  after deduplication and cohort filtering, and fetches one extra row beyond
  its 10,000-point cap to detect truncation truthfully. Grouping by recorded
  outcome/cache result or environment reuses the same loaded observations.
  No timing is invented for hits/skips or generated Xcode module observations.
- Scatter points use native drill-down for recorded executions. Bazel points
  open entity History scoped to the invocation ID, where the existing bounded
  parent lookup resolves available native links. This avoids 10,000 optional
  BEP-parent probes or links to reports that may not exist.
- Line tooltips show measured-duration sample counts, and hit-rate tooltips show
  hits, misses and their lookup denominator. Both lines retain gaps and markers.
  `duration_samples` is an optional additive REST/MCP metric, including totals,
  previous-period totals and daily points; generated clients can still decode
  responses without it. Zero-duration measurements count; missing timings do not.
- Empty timing cohorts omit the toggle and show No recorded durations. Scatter
  failures stay independent of summary metrics and table results, with Line
  still available. Outcome-stacked count bars remain a separate enhancement.

## Compatibility and rollout

- No newly required ingestion field and no change to existing execution IDs.
- Existing routes, tools and API response meanings remain supported.
- Native public endpoints and MCP tools are additive; extensible response
  fields remain open strings, not closed generated-client enums.
- New indexing begins when the server ships. Existing histories continue to
  work in their existing pages. No unbounded release-time historical backfill.
- Old reports that lack trustworthy identity telemetry remain accepted without
  guessed attribution. Modern telemetry benefits from its reported scope,
  timestamps and producer event IDs.
- Bazel cache events are indexed only when Kura supplies a valid UUID
  `event_id`, which the native row then reuses as its ID, so retries collapse
  and history links to an existing row. The webhook accepts any string, so an
  event without an `event_id` keeps its existing server-minted UUIDv7 fallback;
  non-UUID strings now use that same fallback instead of failing UUID insertion.
  Neither produces a derived observation: its row ID changes on every retry, so observations would double
  count and link to rows that do not exist. Hashing event content was rejected
  because it would merge distinct real lookups. Deriving a namespace UUID from
  a non-UUID `event_id` would only work if it also became the native row ID,
  changing native ingestion for a case no Kura release produces (Kura mints
  UUIDv7 event IDs), so the plain fallback was kept.
- Once observations use the client run ID as their parent, which the existing
  run page resolves within the project. Actions whose target mappings were never
  reported stay unattributed.
- Regenerate the Swift client from server schemas. Do not edit generated files.

## Insertion audit and existing-client compatibility

New inventory records are derived in the native ingestion path, not when a
page is opened. No producer looks up catalog identity or upserts a PostgreSQL
catalog row. `record/1` computes deterministic IDs in process and submits one
observation batch through the existing RowBinary ingestion buffer; its
supervised process batches writes across reports and uses the shared retry and
shutdown-flush behavior. ClickHouse's `build_entities_mv` creates/updates the
catalog automatically when each observation batch is inserted. Test-mode
write-through is synchronous; production catalog visibility follows buffer
flushes, not HTTP acknowledgment.

| Native data | Insertion hook | Existing-payload coverage |
| --- | --- | --- |
| Gradle tasks | `Gradle.create_build/1` | Existing task fields; legacy missing build path/type stay empty, not guessed |
| Xcode modules | `Xcode.create_xcode_graph/1` | Generated graph targets with existing binary-cache metadata |
| Xcode actions | `Builds.create_build/1` cacheable tasks | Existing parser cache keys/types and operation timings |
| Bazel actions | `ReapiCache.create_cache_events/1` | Existing Kura producer UUIDs; action-cache hit/miss/write, never CAS |
| Mix files/modules | `Mix.create_build/1` | Existing compile reporter paths, module names and file timings |
| Once actions | Projector run completion plus terminal-run recovery | Existing target instance/queued/action events, one run-scoped slot join |

Once mapping writes happen per target instance/execution event, not per action
or catalog identity. They persist stream-resume state. A finished run's actions
are resolved together and submitted as one observation batch. The hourly stale-run
worker also indexes recently finalized/lost runs in a fixed two-hour window,
using 100-run tuple-keyset pages and a concurrently created partial index on
`once_runs(finalized_at, id)` for terminal states. This covers completed actions
of abandoned runs and missed emission during rollout without historical
backfill. Primary projection failures still propagate for `NEEDS_RESYNC`; sweep
failures propagate for Oban retry. Action outcomes never come from the lost-run
status. The recovery window is finite: prolonged failures or delayed sweeps can
outlast it, so this is a backstop, not a permanent delivery guarantee. Unmapped actions
and legacy Kura events without a valid producer UUID stay accepted in their
native store but cannot create trustworthy retry-safe entities. Current Kura
already mints these UUIDs server-side; Bazel clients need no new field. No new
required client field is introduced in any ingestion contract. Replays collapse
when they preserve their native build/run/event identity; a request without a
client build ID that receives a new server-generated ID is a distinct native
build, not a deduplicable retry.

Insertion/query efficiency is structural, not a production throughput claim:
entity-leading observation keys, merged catalog states, read-time latest-row
deduplication, bounded pages/scatter, memory/time budgets and spill. The new
production tables were absent at the read-only check. Actual-schema isolated
volume/concurrency and synchronous Once recovery measurements are now complete
below; production buffer throughput and deployment-specific latency still need
normal canary observation after approved deployment.

Validation: **211 tests passed** across domain/producers, Once lifecycle,
ingestion buffer/dedup-token tests and real Gradle, Mix compile-reporter, Xcode
analytics and signed Kura HTTP ingestion. New assertions cover automatic
catalog/history population, no extra legacy Gradle fields, file/module
derivation, Kura batch replay/write/CAS/legacy semantics, and a 1,000-observation
single-insert/no-read contract. Once recovery covers lost runs without
`RunCompleted`, unchanged action outcomes, unmapped/phase exclusion, projection
and sweep failures with recovery, replay deduplication, 101 equal-time run IDs
across a keyset boundary, and old/active/future run exclusion. The test alias
applied the concurrent index migration locally. Strict Credo passed on all ten
audit-touched source/test/migration files; formatting and `git diff --check`
passed. A baseline Locale warning and a transient FunWithFlags PubSub startup
error appeared, without test failures. Claude's read-only review found no
blockers in the tuple-keyset cast, partial index, replay semantics or worker
permissions. Production buffer behavior is covered by ingestion-buffer tests,
not inferred from synchronous test-mode writes.

## Validation plan

Identity golden values, delimiter ambiguity, tenant/system/kind separation;
legacy payloads and replayed/out-of-order reports; exact deduplication before
metrics; all-hit/all-miss/no-data rates; nullable and real zero durations;
project isolation; stable cursor pagination; native HTTP/MCP names and existing
contract preservation; LiveView loading/refresh/error/empty states and links;
migration engine/retention policy; English Gettext templates; data-export docs;
OpenAPI and generated-client consistency.

## Validation completed

- 149 focused tests passed across identity, catalog/history/analytics, producers,
  Once projection, cache ingestion, native HTTP/MCP contracts, helpers and LiveView.
- 669 existing native-context, controller, MCP and legacy-page regression tests
  passed in the broader regression run (some overlap with the focused run).
- Strict Credo passed for 40 changed source files. The router retains one existing
  nested-module alias suggestion at line 499; repository-wide baseline findings
  were not changed as part of this feature.
- Changed Elixir/HEEx formatting and `git diff --check` passed. Gettext extraction
  updated English `.pot` templates only.
- `mix assets.build` passed after installing local JavaScript dependencies.
- `MIX_ENV=test mise run generate-api-cli-code` regenerated the OpenAPI document
  and Swift client. Semantic comparison with HEAD found no changed or removed
  existing operations or schemas, 21 added operations and 15 added schemas;
  all new operations document the 503 query-limit response.
- `tuist generate tuist TuistServer --no-open` and
  `xcodebuild build -workspace Tuist.xcworkspace -scheme tuist CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
  passed, including the generated Swift client.
- Incidental Elixir and Swift lockfile changes from dependency setup were removed.
- Dashboard follow-up: 51 focused domain, LiveView, REST/MCP and parameter tests
  passed, including latest-row activity filtering/search, full-cohort sorting,
  missing timings last, pagination, query-error controls and analytics reuse.
  Scoped strict Credo, changed-file formatting, English Gettext extraction and
  asset builds passed.
- Headless Chrome checks exercised search, sort and outcome-filter menus for all
  seven native kinds, verified canvas/section widths match and legends are left
  aligned, and confirmed the chart stays mounted during table search. Sorted
  history Next/Previous round trips, 390px/1440px layouts and light/dark themes
  passed with no page JavaScript errors or document horizontal overflow.
- Shared table-section correction: 13 LiveView tests passed, with explicit
  structure assertions for inventories, Recent activity and History across all
  seven kinds. Chrome checks verified that toolbar/table elements have the same
  white card-section ancestor with no nested table section. Scoped Credo and
  assets build passed; the local preview was recompiled and restarted.
- Empty-cohort widget correction: 14 LiveView tests passed, covering all native
  kinds and preserving genuine zero timings/hit rates. All three widgets now
  show No data without trends when no observations exist; populated cohorts
  retain metric-specific unavailable messages. Chrome verified equal empty
  widget heights and labels across seven kinds and all three Gradle widget
  selections. Formatting, scoped Credo and English Gettext extraction passed.

- Approved chart follow-up: 61 focused domain/LiveView/REST/MCP tests passed,
  including replay-to-null and corrected cohorts, sample counts, cap-plus-one
  truncation, lazy reads and grouping reuse, independent errors/retry, native
  links, and optional sample-count schemas accepting earlier responses.
- Scoped strict Credo (eight files), changed-file formatting, English Gettext
  extraction, asset builds and `git diff --check` passed. The generated Swift
  client rebuilt successfully with the existing `tuist` Xcode scheme.
- The normal code-generation task encountered the known seven dependency-lock
  mismatches. Its equivalent export/generator commands succeeded using
  `deps.loadpaths --no-deps-check`; no dependency lockfile changed. OpenAPI
  semantic comparison still preserves all existing operations/schemas, with
  the same 21 added operations and 15 added schemas.
- Chrome verified all seven native kinds: six measured-duration scatter pages
  and the unavailable-timing state for generated Xcode modules. Grouping and
  table patches preserve the scatter element; plots retain full-width 240px
  frames; measured-sample and hit/miss-denominator tooltips work. Clicking an
  actual Gradle dot opens its native execution detail. Light/dark and 390px /
  1440px layouts passed without overflow or page JavaScript errors. All nine
  empty-widget regression cases retained aligned No data labels, no trends,
  and equal 154px widget heights.

- Native inventory presentation correction: 23 helper/LiveView tests passed,
  including exact headers for all seven kinds, root versus missing scope,
  genuine zero action indices, and primary identifiers without duplication.
  Scoped Credo, formatting, English Gettext extraction and `git diff --check`
  passed. Chrome verified all seven inventories at 1440px and 390px, shared
  toolbar/table sections, scope search, consistent root-build detail badges,
  and no document overflow or page JavaScript errors. Preview recompiled and
  restarted with these changes.

- Actions-label and subtitle correction: 44 helper/LiveView/REST/MCP tests
  passed, plus scoped Credo, formatting, assets and English Gettext extraction.
  Chrome verified Actions/Action labels and computed subtitle typography/color
  for Xcode, Bazel and Mix module notes in light/dark at 1440px/390px. All seven
  inventory layout checks still pass, with no document overflow or JavaScript
  errors. Local preview recompiled and restarted; routes/contracts unchanged.

- Initial history/source and Built by alignment (first-column identifier
  presentation superseded by the native-context correction below): Recent
  activity and History started with the native parent identifier, retaining
  Outcome separately. Built by reuses the shared CI/user/Unknown badges. Local names
  come from bounded project-scoped native-parent lookups, including recorded
  personal owners, with no owner/viewer fallback; missing environment or actor
  stays Unknown. Parent version resolution retains NULL actor clearing. No
  ingestion, observation schema or public response contract changed.
- 83 focused domain/helper/component/LiveView/REST/MCP tests passed, plus scoped
  strict Credo, formatting and English Gettext extraction. Twenty-two legacy
  generate-run/module-cache/run-detail regressions passed on retry after the
  local ClickHouse service briefly disappeared during the first run. Chrome
  verified first-column IDs and Built by badges on all seven kinds in Overview
  and History, actual local `tuistrocks` attribution, unknown Bazel provenance,
  shared white table sections, and light/dark mobile layouts without document
  overflow or JavaScript errors. Claude's integration review found no blockers.
  The local preview was recompiled and restarted.

- Native build-context correction: the user clarified that the first cell
  should be the human-readable Project/Scheme/Command/Run, not a UUID. Both
  Recent activity and History now follow Build Runs ordering: native context,
  Status, Branch, Commit SHA, Built by, observation duration, Cache, Recorded
  at. Gradle reuses the project-and-tags component; Xcode and Bazel reuse native
  command formatters with recorded arguments/patterns; Passed/Failed use the
  shared status cells. Parent IDs remain in tooltips and native navigation.
  Missing context remains Not reported. Rows still describe individual entity
  observations, so parent aggregate outcome/duration/cache rates are not copied.
- `parent_contexts/4` batches recorded labels, tags, command inputs and actors
  in one project-scoped bounded native read (plus one account/user batch),
  replacing separate actor and Bazel availability queries. Latest tuple
  resolution includes cleared nullable fields. `parent_actor_names/4` stays
  compatible; no storage, ingestion or public response changes.
- Validation: 98 focused domain/helper/component/LiveView/REST/MCP tests passed;
  strict six-file Credo, formatting and English Gettext extraction passed.
  Chrome verified all seven kinds in Recent activity and History, native
  human-readable labels instead of visible UUIDs, exact column order, actual
  CI/user/Unknown attribution, all seven native drill-down destinations, shared
  card structure, and light/dark 1440px/390px layouts without document overflow
  or JavaScript errors. Claude's read-only integration review found no blockers.
  Recompiled/restarted preview is current. The isolated Xcode demo's synthetic
  command arguments were corrected to include `generate`, matching the native
  formatter's expected recorded command; no application formatter was changed.

## Read-only production validation through Atlas

- Production's table inventory does not yet contain `build_entities`,
  `build_entity_observations`, `once_target_instances` or
  `once_target_executions`. Therefore inventory/history/analytics/scatter index
  queries cannot be production-benchmarked before rollout. No DDL, mutations,
  backfills or production data changes were performed.
- Exercised native parent-context query shapes against production data for
  Xcode commands/builds, Gradle, Mix and Bazel. Parameterized 20-ID batches
  returned the expected parents. Additional 100-parent reads included bounded
  ID-selection subqueries; all completed with SQL limits of 256 MiB memory,
  64 MiB group/sort spill, two threads and a ten-second deadline. Results were
  reduced to counts/lengths rather than exporting command strings or names.
- Atlas's dedicated ClickHouse endpoint does not expose server elapsed time,
  scanned rows/bytes or peak memory. Passing its bounds is a smoke test, not a
  latency/load sign-off. Atlas's authorized Grafana ClickHouse proxy provided
  read-only `EXPLAIN indexes=1` plans for four-ID samples: command events used
  project pruning (132 of 9,835 granules) plus `idx_id` bloom pruning (20
  granules); Xcode builds used project/ID primary-key pruning (20/504), Bazel
  project/invocation pruning (1/3), Mix project/ID pruning (1/3), and Gradle
  project-only pruning (6/49). These are selected scan granules from plans,
  not measured rows or timing. Gradle's weaker ID pruning warrants rechecking
  on higher-volume projects as its parent table grows.
- PostgreSQL `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` on a populated Once
  project returned 100 parents in 15.699 ms including sample-ID discovery. The
  lookup uses `once_runs_project_run_id_index`; the account join uses
  `accounts_pkey` with memoization. A recorded-actor account-name batch used
  `accounts_pkey`, returned three user accounts and took 0.065 ms (excluding
  0.449 ms planning). The initial empty-project probe is not counted as useful
  performance evidence. These are individual warm-cache samples, not p95/p99.
- These metadata checks alone do not establish new-feature performance. The
  isolated volume gates below subsequently exercised actual new-table schema,
  filtered/sorted queries, server statistics and concurrent callers without
  waiting for or modifying production tables.

### Volume recheck after ingestion audit

A fresh read-only Atlas pass still found all four new tables and the
`once_runs_terminal_recovery_index` absent. No production writes, deployments,
cache resets or concurrent load generation were performed.

The existing-table lookups were exercised on larger real project cohorts,
returning 100 native parents per family with the same 256 MiB/64 MiB spill/two
thread/ten-second SQL bounds. Native project row counts were 300,169 commands,
647,931 Xcode builds, 39,318 Gradle builds, 1,625 Bazel invocations and 2,042 Mix
builds. Global metadata estimates were about 39.9 million commands, 4.0 million
Xcode builds, 87 thousand Gradle builds, 1.7 thousand Bazel invocations and 2
thousand Mix builds. These counts are native rows, not deduplicated entity
observations, and the smaller Bazel/Mix cohorts are not high-volume evidence.
ID-discovery subqueries add work relative to constant-parameter application
queries. Results only exported counts/byte lengths, not customer labels or
command arguments. ClickHouse still exposes no per-query timing, scan or peak
memory statistics through this endpoint, so these remain bounded smoke tests.

Fresh four-constant-ID plans on the larger cohorts selected 33/502 granules for
Xcode builds with project/ID pruning, and 31/48 for Gradle with project-only
pruning. Gradle scans much of its largest project's parent data despite the
small ID set; successful bounded reads do not eliminate this growth risk.
No unmeasured index change was introduced just to claim it had been resolved.

PostgreSQL supplied actual server measurements:

| Existing-table read | Real volume | Execution evidence |
| --- | --- | --- |
| Once 100-parent context with ID discovery | Project with 5,837 runs | 1.845 ms execution, 1.407 ms planning; 447 shared hit and 3 read blocks; project/run index |
| Native side of Once slot projection | Largest recorded run, 3,432 actions; table estimate 4.88 million rows | First 105.101 ms with 204 read blocks; repeat 1.737 ms with all 2,221 blocks cached; existing run-action index |
| Recovery first page, actual full run projection | About 8,542 runs globally; 13 recent terminal rows | 55.879 ms execution, 0.547 ms planning; sequential scan of 15,082 cached heap blocks (about 118 MiB), 47 KiB sort memory |

The recovery measurement is the **pre-index baseline**, not performance of the
pending concurrent index. Mapping joins could not be tested because their
tables do not exist. The first action read had physical I/O, but caches were not
explicitly reset, so it is not a controlled cold-cache benchmark. None of these
individual samples establishes concurrent p95/p99. Full new-feature production
performance approval remains blocked on deployed tables/indexes,
representative observations and access to ClickHouse query statistics. The
local reduced-result artifact is
`/tmp/build-entities-production-volume-results.json`.

## Isolated volume gates and shipping readiness

Performance is no longer deferred solely because production tables are absent.
`priv/benchmarks/README.md` documents three repeatable private-instance gates and
the high-cardinality variant. They invoke the actual domain methods, verify
fixture cardinalities/replay corrections, retain JSON evidence, and fail their
latency gates rather than converting failures to empty data. No production DDL,
inserts, mutations, cache resets, deployment or concurrent load was performed.

### Bottlenecks fixed

- The observation key now ends in `(entity_id, id)`, not observed time. The
  undeployed migration was corrected; readers use `FINAL` with explicit
  cross-partition/PREWHERE/skip-index safety settings. Whole-row replacement
  preserves cleared values and avoids building an observation-sized argMax
  state table. A direct 1.1-million-row comparison returned identical counts:
  FINAL took 126–268 ms versus 1,182–1,893 ms for the former grouped tuple read.
  Cross-month tests assert two physical partitions, out-of-order older writes,
  cleared duration/cohort values and moved times before filtering.
- Inventory/history return page counts with a window, with a separate count
  only for empty pages. History counts precede cursor filtering. Analytics
  computes period and daily aggregates with GROUPING SETS in one scan.
- Gradle and Mix native build IDs now have bloom skip indexes. Metadata-only
  additions cover new parts; existing parts materialize asynchronously per
  partition. SchemaClone adds missing destination indexes automatically and
  retries unindexed partitions on subsequent reconcile runs without duplicating
  pending mutations. Definition mismatches and repeatedly failing mutations
  are reported, not destructively replaced. Real outside-transaction tests
  exercise index consultation and materialization recovery.

Early experimental artifacts are **not** sign-off: the first generator used
`unhex(MD5(...))` even though MD5 returns raw bytes, and a later larger dictionary
exceeded its seeding budget. Both were fixed (canonical raw MD5 UUIDs and a
bounded dictionary join); cardinality assertions now prevent a reduced-workload
result from silently passing. Shared-instance latency was also contaminated by
other worktree activity, so final gates use a private native ClickHouse process.

### Measured results

Local ClickHouse was 26.1.2.11. A read-only production SELECT reported
26.6.1.2326 and accepted every new safety/block setting. Percentiles below are
**local workload samples**, not production HTTP p95/p99 or controlled cold-cache
measurements. Entity/native-parent gates use 20 serial and 80 concurrency-four
samples per case, with a 2,000 ms sample-p95 budget.

| Gate | Actual synthetic volume | Result |
| --- | --- | --- |
| Seven kinds, all inventory/detail/history/analytics/scatter and Overview fan-out paths | 7.77 million inserts; 70,000 identities; 100,000 hot observations per kind; 10% hot replay/NULL corrections | Endpoint-verified private port 18234: all 112 cases passed, spanning 85 days/four insertion months (modules: 29 days). Concurrent sample p95 at most 769 ms (full-retention filtered inventory), ordinary filtered inventory 490 ms, Overview 392 ms; 11,333 SQL profiles, peak query memory 58.22 MiB |
| High-cardinality Xcode actions | 100,000 identities; 1.11 million inserts including hot corrections | Endpoint-verified private port 18235: all 16 monthly-partition cases passed; worst serial/concurrent sample p95 406/619 ms; peak query memory 72.83 MiB |
| Five ClickHouse native parent families | 11 million rows across two projects, five families and 10% nullable corrections; 100 recent/middle/scattered/wrong-project IDs | Repeated on verified private port 18233: all 20 cases passed; worst concurrent sample p95 131 ms. Gradle recent/middle read at most 16,384 rows; scattered IDs read 881,647 rows/p95 129 ms; wrong-project scans read zero rows |
| Once native/mapping/recovery original private gate | 5,005,000 actions, 10,001 runs, 105,000 rows in each mapping table; hot run 5,000 actions | Direct private port 18233, five serial/20 concurrent samples: mapped-slot p95 22.4/28.3 ms, parent 35.4/1.7 ms; mapped join server execution 4.241 ms; first recovery page partial Index Scan 0.217 ms/94 shared-hit blocks; 201-run/105,000-observation repeated sweep 3.156 s/205 PostgreSQL queries, no double counting |
| Once wrapper/endpoint regression | 505,000 actions, 1,001 runs; same 105,000 mappings and 5,000-action hot run | Verified private port 18235, 20 serial/80 concurrent samples: mapped-slot p95 19.8/17.0 ms, parent 1.2/0.8 ms; repeated 105,000-observation sweep 3.098 s. Separate from the five-million-action proof |

The native fixture keys, selected column types and skip-index definitions were
verified against five zero-row definitions copied from the fully migrated local
reference database, not assumed from hand-written approximations. Scattered
100-ID reads intentionally remain broad; bloom indexes are not a promise that
every arbitrary ID set reads only 100 rows. Actors in native volume fixtures are
unreported and remain absent; recorded-user name batching is covered separately
by domain and read-only indexed production evidence.

Final artifacts: `/tmp/build-entities-speed-shipping.json`,
`/tmp/build-entities-speed-high-cardinality.json`,
`/tmp/build-entities-speed-native-parents.json`,
`/tmp/build-entities-once-volume.json`,
`/tmp/build-entities-speed-once-isolated.json` and their logs. The wrapper retains each
private configuration/dataset; documentation provides reproducible commands.
Reduced metrics and source hashes also live in
`priv/benchmarks/build_entities_results.json`, so review evidence does not depend
on the lifetime of temporary files.

### Further filtered-inventory optimization

Filtered inventories now join observation counts from a single FINAL pass rather
than scanning once for membership and again for page counts. The catalog's
range/search candidates safely narrow whole entity replacement groups: the
catalog range spans all observed versions, so it cannot hide a latest observation
inside the requested window. Unfiltered inventory keeps catalog-only membership.
Explicit PREWHERE contains only project/system/kind/entity-ID key predicates;
time/cohort predicates remain after FINAL, and all three safety pins remain.

An interleaved paired comparison of the original implementation (source SHA256
`4997cd81b67538a30752b917f9e98df76a35c00ec6bfff344bf50136f333baf2`)
and optimized domain methods used the same private dataset and 20 serial/80
concurrency-four calls per kind, asserting identical complete results on every
pair. Filtered-inventory concurrent sample p95 improved **2.3–4.0×**, including
Xcode modules where the entire retained catalog is eligible. The all-kind gate
now also covers filtered search, one-day and full-retention windows. The latter
prevents claiming that selective candidate pruning alone solves broad reads.
Paired evidence: `/tmp/build-entities-speed-paired.json`.

This pass also found that Mise hooks reset the wrapper's exported HTTP port to
shared 8123. The earlier monthly shipping artifacts had isolated databases but
not isolated processes and are **not private-instance sign-off**. The wrapper
now passes the port after Mise, each harness checks both actual repo ports
against required `BUILD_ENTITY_BENCH_EXPECTED_PORT` before writing and rejects
8123, and artifacts record the endpoint. A deliberate mismatch test failed before
database creation. The final gates above use verified private endpoints. The
original direct native/Once gates were already private. A new full five-million-
action seed exceeded its bounded 300-second seed deadline; it is not a completed
gate. The endpoint-regression Once fixture is explicitly smaller, not relabeled.

### Integration and release gates

The branch was fast-forwarded from 2990d009ee to origin/main 526874e650 without
creating feature commits. All feature work remains uncommitted. Tracked/untracked
backups and the preservation stash were retained. The two overlapping intent/
Gettext-template changes were resolved without losing current-main guidance;
generated API files were regenerated rather than hand-merged.

After integration, **480 focused/ingestion/migration/index/REST/MCP/LiveView,
current stateless-transport and legacy native-domain/UI regressions passed**.
After the further query optimization, **405 regressions passed**, including a
103-test core/producer/REST/MCP/LiveView subset, cross-month/NULL/time corrections,
indexes/parity, native ingestion and legacy pages. A new test checks exact filtered
counts, one query for populated pages, catalog range false positives, search and
out-of-range totals. Scoped strict Credo passed on all five newly touched Elixir
source/test/benchmark files. The no-reloader preview was restarted and all seven
browser Overview/History/context/drill-down/light/dark/mobile checks passed again. OpenAPI semantic comparison
preserves all 165 existing operations and 202 schemas, with the same 21 additive
operations/15 schemas, all new operations documenting 503. The required-target
Tuist workspace regenerated and the complete `tuist` Xcode build succeeded.
Strict Credo passed on 21 touched production/test/migration files. The owned
local preview/test prototypes were recreated with bounded copies and retained
backups, preserving all 2,697 demo observations and 44 aggregate catalog
identities (including older first-seen state). Dev migrations and the no-reloader
preview restart succeeded. Chrome revalidated all seven Overview/History pages,
native drill-down, 390px/1440px light/dark layouts, with no JavaScript errors or
overflow. The three benchmark scripts passed formatting, bash syntax/smoke gates
and scoped Credo (procedural orchestration functions have explicit complexity
exemptions; production code has none). Claude's final read-only review found no release blockers; Once's
finite sweep, per-run memory and extra replay writes remain explicit limitations,
not a claim of durable exactly-once delivery or production throughput.

Before rolling out, use the normal canary cascade, with these concrete gates:

1. Apply PostgreSQL target mappings and concurrent terminal recovery index, then
   ClickHouse catalog/observations/MV and native ID-index migrations before
   starting new producer/readers. Existing clients/native IDs remain compatible;
   no unbounded historical backfill is required.
2. Verify source and any configured shadow/in-cluster destination have both new
   tables/MV, the exact observation sorting/version/partition key, and native ID
   index definitions. Reconcile is automated but intentionally availability-
   tolerant; a logged clone/index failure is a rollout blocker, not success.
   Verify runtime/processor grants and no failed index materialization; do not
   require deploys to wait for healthy asynchronous work.
3. Exercise one existing-client report for each native ingestion family and
   verify flushed catalog/history plus native drill-down, tenant isolation,
   unavailable metrics and REST/MCP query-limit behavior. Confirm Once's hourly
   terminal sweep and the finite two-hour backstop, with no producer/buffer/
   shadow-write failures. Buffer flush visibility is not HTTP acknowledgement.
4. Observe canary query duration/scan/memory, 503/card/tool errors, ingestion
   buffer backlog/retries and terminal-sweep age under normal traffic. This is
   deployment verification, not permission to run production load. Keep native
   facts authoritative and stop rollout if the measured local budgets do not
   translate to that environment.
5. Roll back the application first if needed. Keep additive tables/indexes and
   their retention until all new writers/readers stop; old clients/native
   history remain valid. Do not drop Once mappings while new projectors run.

Fresh disposable databases are mandatory for a locally applied prototype with
observed time in its replacement key. This change is safe to make in the new,
undeployed migration only because production absence was verified read-only.
Do not silently use a mismatched prototype table or alter deployed customer
sort keys using this procedure.

## Ownership and review

Claude owns storage, producers, native context hooks and domain tests. The main
session owns dashboard, native HTTP/MCP wrappers, routes, documentation and
code generation. Both review the identity and query seam; final validation is
serialized in this worktree to avoid competing compiler/database processes.
