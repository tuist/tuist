# Pulse: Tuist's fork

Pulse was forked from [GreptimeDB](https://github.com/GreptimeTeam/greptimedb) under Apache-2.0.

Pulse is the observability backend in Tuist's clusters. Since November 2026 it
is this fork; before that it was a separate Elixir application, which is in
this directory's history before the import commit. Tuist renamed the code to
Pulse (see [Tuist changes](#tuist-changes)), publishes it as
`ghcr.io/tuist/pulse`, and clusters deploy it as the `pulse` release.

## Upstream base

| | |
| --- | --- |
| Repository | The upstream project linked above |
| Tag | `v1.3.0` |
| Commit | `badceec12a0e98fd69e83e9b9b9b06d9358b78dd` (2026-10-28) |
| License | Apache-2.0, in [`LICENSE`](LICENSE). Upstream has no NOTICE file. |

The import is the upstream tree at that commit, except:

- **Enterprise sources.** Upstream is open core. The files under its
  Enterprise License are not Apache-2.0, and that license forbids copying or
  distributing them, so they are not in this repository: `LICENSE-ENTERPRISE`,
  `licenserc-enterprise.toml`, `licenses/enterprise-header.txt`, and the sources
  for triggers, the recycle bin, and undrop and purge of dropped tables. The
  `enterprise` Cargo feature and the code it gated were removed after the
  import (see below).
- **Upstream automation.** `.github/` (its workflows do not run inside this
  monorepo) and the agent skills in `.agents/skills/` and `.claude/`.
  `AGENTS.md`, its `CLAUDE.md` symlink and the rest of `.agents/` are kept.

## Tuist changes

Every upstream source file Tuist changed is marked with a `Modified by Tuist`
line under its license header, or a `Tuist:` comment at the change. Files
without a license header, such as test expectations and configuration, are
covered by this list.

- **Serialized retained-window recovery.** `ADMIN flush_flow(name, true)`
  marks the retained, aligned windows of an ordinary time-windowed batching
  flow dirty and recomputes them while holding its live execution lock.
  Finite `EXPIRE AFTER` bounds the scan; source arrivals after capture remain
  queued. Unsupported flow modes and older flownodes reject the request.
  The one-argument flush keeps its dirty-only semantics. Implementation spans
  `common/function/src/flush_flow.rs`, `session/src/hints.rs`,
  `operator/src/flow.rs`, `flow/src/adapter/flownode_impl.rs`, and
  `flow/src/batching_mode/{engine,task,state}.rs`. Scoped window splitting also
  accepts an exactly-one-window remainder, so adjacent dirty work cannot turn
  a one-window repair into an acknowledged no-op. ADMIN exact-signature
  conversion in `operator/src/statement/admin.rs` checks argument count before
  casting, so overload resolution cannot silently discard the recovery flag.
  Window-boundary probing in `flow/src/batching_mode/time_window.rs` uses the
  expression's timestamp precision, so fractional origins do not inflate the
  cached stride and drift into adjacent windows during recovery. Wide probe
  arithmetic and a final endpoint probe preserve representable nanosecond
  boundaries without overflowing or misclassifying large windows as unbounded.
  Cached evaluation preserves a representable lower boundary when the next
  upper boundary is outside the timestamp range, including exclusive-end alignment.
  Retained recovery freezes its evaluation timestamp on a local task clone and
  uses that same subsecond cutoff for marking and selecting windows, so an
  expired preceding dirty window cannot consume the retained-window budget.
  SQL window planning rejects unrepresentable bounds before consuming dirty
  work instead of falling back to an unfiltered scan outside retention.
  Retained recovery validates source TTL against the aligned lower bound on
  its frozen clock before marking or writing work. Window budgets and splits
  retain nanosecond precision so fractional strides cannot consume future bins.
  Budget multiplication is checked without narrowing counts to 32 bits, and
  finite TTL validation compares source age without overflowing timestamp cutoffs.
- **Exact count-rollup prototype.** `tests/perf/count_aggregate_benchmark.py`
  compares raw dashboard-style counts with minute summaries plus uncovered raw
  rows in a disposable local database. Immutable ingestion batches and an
  explicit, manually published coverage frontier keep late arrivals visible;
  partially covered minutes remain raw. The harness checks independent event
  counts, tenant filters, nanosecond boundaries, unpublished summaries,
  idempotent rebuilds, and persisted results after restart. It is not connected
  to customer ingestion or dashboard reads and does not implement production
  publication or recovery coordination.
- **Lower PromQL range-query allocation.** `RangeManipulate` borrows window
  descriptors while building each field and timestamp range array instead of
  cloning the descriptor vector twice per column, and no longer gathers a time
  index that it immediately replaces with aligned timestamps. `RangeArray`
  validates dictionary keys in place instead of collecting a temporary vector,
  retaining null-key rejection and range bounds checks. These changes live in
  `src/promql/src/extension_plan/range_manipulate.rs` and
  `src/promql/src/range_array.rs`; window membership and output formats are
  unchanged. Focused `RangeArray` tests cover sliced dictionary keys, null keys,
  and out-of-bounds ranges, including empty ranges past the end and lengths
  that would overflow a 32-bit bounds calculation.
- **Lower write and projected-scan allocation.** The cached-size WAL encoder
  reserves its first length cache from the message shape rather than repeatedly
  growing it; reused encoders keep amortized geometric growth. The encoded bytes
  are unchanged. Simple bulk memtable snapshots copy only selected active field
  buffers, retaining zero-buffer placeholders for unselected positions and
  sharing frozen buffers as before. Allocation-budget regression tests use the
  test-only `allocation-counter` dependency, and the WAL benchmark includes a
  fresh-encoder case matching the write-group lifecycle. These changes live in
  `src/mito2/src/wal/encoder.rs`, `src/mito2/src/memtable/{time_series,simple_bulk_memtable}.rs`
  and `src/mito2/benches/bench_wal_encode.rs`.
- **Renamed to Pulse.** Every upstream name in the code is now a Pulse name:
  crates (`common-pulse-telemetry`), types, modules and files, the `pulse`
  binary and the image's entrypoint, comments, and the names Pulse stores or
  speaks on the wire: the default catalog `pulse` and its `pulse_private`
  schema (and so the object-store paths under them), the `pulse_timestamp`,
  `pulse_value` and `pulse_native_histogram` columns, the `pulse_identity` and
  `pulse_trace_v*` pipelines, the `x-pulse-*` HTTP headers and the
  `x-pulse-*` gRPC metadata nodes send each other, the `PULSE_*`
  configuration environment prefix, the `pulse_v1` response format, the
  `pulse_*` self-metrics, the `pulse_data`, `pulse_wal_topic` and
  `pulse_metakv` defaults, the `pulse:` column and parquet metadata keys, the
  `pulse.json`, `pulse.json2` and `pulse.histogram` extension types,
  `pulse.series_index`, the `pulse.semantic.*` table options, the `pulse-*`
  puffin index blob types, the fulltext index's `pulse_fulltext_*` field
  names, and the `__pulse_*` flow and DDL options. Releases before the rename
  wrote other names, which a renamed release does not read (see
  [Rolling out the rename](#rolling-out-the-rename)). Comments no longer link
  to upstream issues or documentation, tests start the Bitnami images
  upstream mirrored, and usage telemetry, which reported to upstream's
  collector, has no URL to report to. `tests/compatibility` and `tests/perf` compare against
  released binaries and images that Pulse does not publish; Tuist's CI runs
  neither.
  These keep upstream names:
  - The upstream copyright lines in the license headers and `LICENSE`, which
    Apache-2.0 requires us to keep.
  - Dependencies: the protobuf crate and what it generates (the request and
    response types, the gRPC services, and their packages on the wire), and
    the other upstream crates `Cargo.toml` fetches from GitHub, until Tuist
    forks them.
- **No enterprise feature.** The `enterprise` Cargo feature and every code path
  it gated are gone, as is the license tooling for enterprise files. Undrop and
  purge of dropped tables, and `gc.experimental_soft_drop`, which needs them,
  are rejected as unsupported, as they were in the default build.
- **No upstream docs or release tooling.** The code is the documentation:
  `docs/`, the READMEs and other Markdown guides in the source and test trees,
  the Grafana dashboards, the `cyborg` bot, upstream's README, contribution and
  security guides, changelog and coverage configuration, the generated
  configuration reference, the Docker builds other than `docker/buildx/ubuntu`,
  and the Makefile targets that used them are gone. The `AGENTS.md` guides are
  kept for agents working in those crates.
- **Clippy on the pinned toolchain.** `ScanInput::uses_scan_memory_limit` and
  `ScanInput::total_rows` in `src/mito2/src/read/scan_region.rs` return their
  expressions directly instead of through a `let` binding, which
  `clippy::let_and_return` rejects. Behavior is unchanged.

- **Query nesting limits** ([`src/sql/src/nesting.rs`](src/sql/src/nesting.rs)).
  Upstream v1.3.0 aborts the whole process with a stack overflow on short,
  deeply nested queries, and any reader can send them: a PromQL chain of about
  80 binary operators (`vector(1)+vector(1)+…`, around 800 bytes), 48 nested
  subqueries, a SQL chain of about 4,000 operators (`SELECT 1+1+…`) or 256
  chained `UNION ALL`s. Parsing now rejects, with an ordinary syntax error:
  - PromQL nested more than 32 levels, or with more than 4,096 operators,
    parentheses and brackets. Every PromQL parse in the query path goes through
    `sql::nesting::parse_promql`: the HTTP API, TQL, and the format, parse and
    series endpoints. The deepest query in Tuist's dashboards and alerts is 14
    levels deep.
  - SQL expressions nested more than 128 levels and queries chaining more than
    64 set operations, checked in `ParserContext::create_with_dialect`. This is
    stricter than the query analyzer's later limit of the same number: depth
    carries across subqueries and parentheses count, so a `WHERE` with about
    130 chained `AND`s is rejected. MySQL `EXECUTE … USING` arguments bypass
    this check; Tuist's deployments do not expose the MySQL port.
  - SQL texts over 8 MiB. Parsing runs on a stack sized to the input, so a long
    statement cannot overflow the parser or its drop.
- **Sentry envelope ingestion** ([`src/servers/src/http/sentry.rs`](src/servers/src/http/sentry.rs)).
  Sentry SDKs report errors to Pulse with a DSN such as
  `http://<user>:<password>@pulse.observability:4000/v1/sentry/<service>/1`:
  they post envelopes to `/v1/sentry/<service>/api/1/envelope/`, and the DSN's
  key and secret (`X-Sentry-Auth`, or the `sentry_key` and `sentry_secret`
  query parameters) authenticate as that Pulse user (`http/authorize.rs`).
  Every `event` item becomes a `{"service", "event"}` row for the
  `sentry_errors` pipeline and `errors` table that
  [`infra/helm/pulse`](../infra/helm/pulse) installs; other items
  are dropped. Responses carry the envelope's event ID, as Sentry's do.
  Envelopes are held to 1 MiB once decompressed (`sentry::ENVELOPE_LIMIT`,
  a route-level body limit in `http.rs`), which the server-wide 64 MiB
  `body_limit` would otherwise allow.
  `tests-integration`'s `test_sentry_envelope` sends envelopes captured from
  sentry-elixir, sentry-rust, sentry-python 2.75.0 and @sentry/node 11.16.0.

  Beyond errors (`SentryState`, wired by `HttpServerBuilder::with_sentry_handler`):

  - **Rate limiting.** Each frontend counts every service's error events in
    one-minute windows, up to `http.sentry_events_per_minute` (default 600, 0
    disables it; documented in the example configs). Events past the quota are
    dropped and answered as Relay does: an envelope with nothing else gets
    `429` with `Retry-After` and
    `X-Sentry-Rate-Limits: <seconds>:error;default:project:event_limit`, which
    SDKs obey by holding back error events for that long; an envelope whose
    other items were stored gets `200` with the same `X-Sentry-Rate-Limits`.
    Logs, spans and sessions are not limited. The count is per frontend, so a
    cluster admits up to the quota times its frontends.
  - **Logs.** `log` items become OpenTelemetry log records written through the
    OTLP logs handler into `opentelemetry_logs`, with `service.name` set to the
    service. Levels become upper-case severity texts, as the collectors store
    them; typed attributes keep their types; the span comes from `span_id` or,
    from older SDKs, `sentry.trace.parent_span_id`. `otel_log` items are dropped.
  - **Spans.** Spans v2 `span` items and the root and child spans of
    `transaction` events become OpenTelemetry spans written through the
    `pulse_trace_v1` pipeline into `opentelemetry_traces`. Lossy: Sentry has no
    span kind, so `sentry.op` implies one (`http.server`, `http.client`, `db.*`,
    `queue.*`) and is otherwise unspecified; transaction statuses other than
    `ok` become `STATUS_CODE_ERROR` with the Sentry status as the message;
    `is_segment` becomes the `sentry.is_segment` attribute; a transaction's
    measurements, breakdowns, contexts other than `trace`, and the rest of the
    event are dropped, and its `data` and `tags` become span attributes.
  - **Personal data.** Attributes SDKs add only with `sendDefaultPii`
    (`user.*`, `client.address`, `http.request.header.*`) are dropped from logs
    and spans.
  - **Release health.** `session` and `sessions` items become rows of the
    `sessions` table ([`infra/helm/pulse/sessions.sql`](../infra/helm/pulse/sessions.sql)):
    append-only raw session updates carrying Sentry's `seq` and update timestamp,
    or one per pre-aggregated group. Release-health queries select the latest
    logical state by immutable session identity, sequence and timestamp, so
    stale initial updates and replays cannot erase crashes across replicas.
    `init` forces sequence zero; omitted sequence/timestamp use receipt time.
    Aggregate IDs remain independent of individual/distinct identities.
    Each row counts `sessions` and splits them
    into `errored`, `crashed`, `abnormal` and `unhandled`; the distinct ID is
    stored as a truncated SHA-256. Pulse writes sessions only into that table,
    never one it creates on write, and drops
    sessions without a release, as Sentry does. `servers` depends on `sha2`
    (already in the tree through `auth`) for that hash.
  - **Error grouping and issues.** No fork code: the `sentry_errors` pipeline
    groups on the normalized message and every exception in the chain, the
    same rules as Atlas (`sentry-errors-cases.json`). The `errors` table is
    append-only, because its primary key `(service, fingerprint)` would
    otherwise merge two events of one issue at one timestamp, so readers count
    `DISTINCT event_id`. The stock `error_issues` flow on the chart's flownode
    keeps lifetime first seen, last seen and counts in `error_issue_hours`
    ([`infra/helm/pulse/error-issues.sql`](../infra/helm/pulse/error-issues.sql)).
- **rust-protobuf 3** ([`src/log-store`](src/log-store), [`third-party/raft-engine`](third-party/raft-engine)).
  `log-store` generates its raft-engine messages with `protobuf-codegen` 3.7.2
  instead of `protoc-rust` 2.28. Published `raft-engine` 0.4.2 requires
  `protobuf` 2 and `prometheus` 0.13, and 2.28.0 is the last 2.x release, so
  Pulse vendors that crate at the same version with those two dependencies
  moved to `protobuf` 3.7.2 and `prometheus` 0.14. `tokio-metrics-collector`
  0.2 also required `prometheus` 0.13, so the unstable runtime metrics path
  uses 0.3 (and `tokio-metrics` 0.4, which that release requires). The
  log-store messages are proto3 scalars and bytes, which both protobuf
  libraries write in the standard wire format.
- **Release image protoc** ([`docker/buildx/ubuntu/Dockerfile`](docker/buildx/ubuntu/Dockerfile)).
  The image `pulse-build-publish.yml` builds installed Ubuntu 22.04's protoc 3.12,
  which cannot compile `substrait`'s proto3 optional fields. It now installs
  protoc 29.3 from GitHub, checksum-pinned, as upstream's dev-builder does.
- **`and`/`unless` across label sets** ([`src/query/src/promql/planner/set_operator.rs`](src/query/src/promql/planner/set_operator.rs)).
  Prometheus matches a label a series lacks as the empty value, so `a unless
  on(node) b` keeps every `a` when `b`'s metric does not exist or its labels
  were aggregated away. Upstream rejected operands whose label columns
  differ ("Attempt to combine two tables with different column sets"). Pulse
  adds each operand's missing labels as NULL columns, which the join already
  treats as equal, and matches on the union. As `or` does, those labels use
  the decoded string type on both sides, because a dictionary-typed NULL
  literal loses its type when the plan is distributed. `set_operation.sql`
  covers it.
  This is a compatibility fix with no Tuist-specific behavior; offer it
  upstream and drop it when upstream has an equivalent.
- **libzstd 1.6.0** (`Cargo.lock`). `zstd-sys` is pinned to
  `2.2.0+zstd.1.6.0` or later for CVE-2026-124851: with libzstd 1.5.1 to
  1.5.7, crafted zstd bodies on remote write and the Sentry route decode to
  output holding up to 64 KiB of the decoder's uninitialised or stale buffer,
  which is then stored. libzstd 1.6.0 dropped `ZSTD_copyDCtx`, which
  `zstd-safe` below 7.4.2 calls under the `experimental` feature that
  `tantivy-sstable` enables, so `zstd` 0.13.6 and `zstd-safe` 7.4.2 moved with
  it. Keep those versions when importing upstream's lockfile;
  `prom_store.rs`'s `test_zstd_decoder_includes_the_cve_2026_124851_fix` fails
  below libzstd 1.6.0.

## Build, release and deploy

- [`pulse.yml`](../.github/workflows/pulse.yml) checks formatting, runs the
  `sql` crate's tests (where the limits live), and type-checks the `pulse`
  binary, which covers the other changed crates.
- Pulse owns its versions and releases through the same channels as Kura
  (`kura-release.yml`, `kura-rc.yml`, `kura-promote.yml`): every `pulse/`
  change on main publishes a canary `X.Y.0-canary.N`
  ([`pulse-release.yml`](../.github/workflows/pulse-release.yml)); each Monday
  [`pulse-promote.yml`](../.github/workflows/pulse-promote.yml) promotes the
  previous week's `releases/pulse-X.Y.x` line to stable `X.Y.0`, and
  [`pulse-rc.yml`](../.github/workflows/pulse-rc.yml) cuts the next line as
  `X.Y.0-rc.1`. Versions continue the Elixir Pulse's line (`1.43.6`), so the
  first canary is `1.44.0-canary.1`; the upstream version stays in
  `Cargo.toml`'s `[workspace.package]` and the [table above](#upstream-base).
  The earlier `pulse@1.3.0-1` and `pulse@1.3.0-2` tags used the retired
  `<upstream>-<n>` scheme.
- [`pulse-build-publish.yml`](../.github/workflows/pulse-build-publish.yml)
  does each build: it stamps the version into `[workspace.metadata.pulse]`
  (what `pulse --version` and SQL `version()` report), builds the image with
  upstream's `docker/buildx/ubuntu/Dockerfile` and release profile (`nightly`)
  without the embedded web dashboard (`servers/dashboard`), smoke-tests it,
  and publishes `ghcr.io/tuist/pulse:<version>` (stable releases also move
  `:latest`), the `pulse@<version>` tag and a GitHub prerelease or release
  with git-cliff notes ([`cliff.toml`](cliff.toml)). Pulse releases never take
  the repository's GitHub "Latest" release, which the CLI, server and Kura use.
- Canaries deploy continuously, as Kura's do.
  [`pulse-production-deployment.yml`](../.github/workflows/pulse-production-deployment.yml)
  runs on every push to main that changes `pulse/`, the chart or its
  deployment: it publishes a canary when `pulse/` changed, then deploys
  staging, canary and production in turn through `pulse-deployment.yml`,
  each leg only after the previous one qualified. In each cluster's
  `observability` namespace the `pulse` release
  ([`infra/helm/pulse`](../infra/helm/pulse), Service `pulse`) runs the newest
  `pulse@*-canary.*` the deployed commit contains, or the image pinned in its
  `values.yaml` for a commit without one. RCs and stable releases deploy
  nothing. Dispatch `pulse-deployment.yml` to redeploy or roll back one
  environment. `.github/scripts/pulse-readiness.sh`, the gate every server
  deploy runs, accepts any published `ghcr.io/tuist/pulse` version.

## Rolling out the rename

The infrastructure around Pulse uses Pulse's names: the chart
([`infra/helm/pulse`](../infra/helm/pulse)), its deployment workflow
(`pulse-deployment.yml`) and smoke scripts, the storage credentials
(`PULSE_STANDALONE__*`, `PULSE_DATANODE__*`), and the `X-Pulse-*` headers and
`pulse_trace_v1` pipeline the collectors in `infra/helm/k8s-monitoring` and the
server's `Tuist.Pulse` send.

The rename changed the names Pulse writes to disk and sends between its own
nodes (metadata keys, extension types, index blob types, table options and
internal gRPC metadata), and Pulse reads only the new ones. A renamed release
therefore neither opens data an earlier release wrote nor talks to its nodes,
so every cluster (staging, canary, production and management) is reinstalled
from empty (storage, metadata and WAL) when it moves to a renamed release, and
nothing is migrated.

## Moving to a newer upstream version

1. Import the new upstream tag's tree over `pulse/` with the same exclusions,
   using that version's `licenserc-enterprise.toml` for the enterprise list.
2. Reapply the Tuist changes above (the commits touching `pulse/` since the
   previous import), including the rename, the enterprise removal and the
   removed docs, and update this file's upstream table. Keep
   `[workspace.metadata.pulse]` out of `Cargo.toml`: the release build stamps
   it and refuses to run when it is already set. The Pulse version is not tied
   to upstream's; the next canary continues the current line.
3. Check that every PromQL parse still goes through `sql::nesting::parse_promql`
   (`rg 'promql_parser::parser::parse\(' src` outside tests), and repeat the
   overflow checks against the new planner before trusting the limits.
