# Oban arguments index: investigation and maintenance plan

## Decision and scope

The first maintenance candidate is a **concurrent rebuild of the existing
`jsonb_ops` arguments index**, after an isolated restore establishes the expected
size and resource budget. Keep its definition and Oban's retention and uniqueness
semantics unchanged. Measure subsequent growth before adopting a recurring
rebuild schedule. For a durable reduction, qualify a full-arguments
`jsonb_path_ops` index against representative traffic and consider reducing runner
webhook payloads separately.

The October 27, 2026 investigation used read-only production metadata, bounded
aggregate samples, non-executing EXPLAIN and existing vacuum logs. All writes,
extension installation, vacuum and reindex experiments were confined to a
disposable local PostgreSQL instance with synthetic data. **No production
maintenance, schema/configuration changes, job deletion or extension installation
was performed.** No admin credentials or JIT elevation were retrieved.

This change provides executable diagnostics and an experiment, not an automatic
production migration. Exact production reclaimable bytes, pending-list occupancy
and throughput under a replacement index remain unmeasured. Automatically
deploying an index replacement would turn those open questions into production
risk. No stored application data or retention policy changes, so no data-export
documentation change is required.

Dedicated storage architecture, durable-write latency detection and switchover
RBAC belong to separate follow-ups. The maintenance cost below is an amplifier
of storage degradation, not evidence that vacuum triggered the incident.

## Production evidence

Catalog observations at 11:22 UTC on October 27 used Atlas's
`query_tuist_postgres`: a read-only transaction, five-second statement timeout
and bounded results, against the primary `tuist` database on PostgreSQL 16.6.
The incident identified cluster `tuist-tuist-pg`, namespace `tuist`, primary
`tuist-tuist-pg-3`, CNPG 1.29.1. The source checkout was
`17593a55b825ad9e1754978dfbfd6f3c8dc54dbb`.

| Relation | Bytes | Definition / observation |
| --- | ---: | --- |
| `oban_jobs` heap | 102,383,616 | 12,498 pages, estimated 147,879 rows |
| Associated TOAST, including its index | 200,892,416 | Heap size alone understates stored arguments |
| `oban_jobs_args_index` | 18,789,105,664 | GIN `(args)`, explicitly verified `jsonb_ops`, valid and ready |
| Primary key | 286,138,368 | B-tree `(id)` |
| Fetch index | 776,462,336 | B-tree `(state, queue, priority, scheduled_at, id)` |
| Cancelled index | 9,707,520 | B-tree `(state, cancelled_at)` |
| Discarded index | 8,814,592 | B-tree `(state, discarded_at)` |

The table and indexes have no storage-parameter overrides. The Oban table
comment is `14`, consistent with the repository's schema upgrade. The args
index is 17.50 GiB; this is not by itself a measurement of bloat.

Counters increased or stayed constant across these two observations:

| Table counter | 11:22:18.375 UTC | 11:31:15.480 UTC | Observed interval rate |
| --- | ---: | ---: | ---: |
| Inserts | 161,034,798 | 161,047,145 | 23.0/s |
| Updates | 339,830,545 | 339,855,759 | 46.9/s |
| HOT updates | 124,257 | 124,257 | 0/s |
| Deletes | 161,060,482 | 161,071,883 | 21.2/s |

The args-index scan count rose from 626,229,567 at 11:22:02.956 to 626,265,651
at 11:31:15.480: about 65.3 scans/s in that interval. These are short-window
observations, not historical averages or peak capacity. `stats_reset` returned
NULL and the connector lacks `pg_read_all_stats`; the reset epoch is unknown.
The original incident's cumulative scan counts must not be interpreted as rates.
No visible progress rows through that role does not establish that vacuum is idle.

### Payload and retention sample

`TABLESAMPLE SYSTEM (1) REPEATABLE (2710)` with an inner `LIMIT 2500` returned
1,548 rows in the first sample around 11:23 UTC. Aggregation happened inside
PostgreSQL; no payloads, IDs, URLs or argument values were retrieved. Page sampling
is clustered, and the limit can introduce bias. Rare oversized jobs may be absent.

| Worker suffix | Sampled rows | Mean JSON text bytes | Maximum JSON text bytes |
| --- | ---: | ---: | ---: |
| `AlertEvaluationWorker` | 1,015 | 52 | 52 |
| `DispatchWorker` | 346 | 9,367 | 14,751 |
| `CommentWorker` | 54 | 181 | 240 |
| `ProcessBuildWorker` | 33 | 1,089 | 1,305 |
| `BroadcastTestCreatedWorker` | 23 | 75 | 75 |
| `ProcessXcresultWorker` | 13 | 1,656 | 1,736 |

Dispatch args averaged 3,299 stored bytes after compression. A second bounded
sample at 11:24 UTC found the same 346 dispatch rows averaged just 87 JSON text
bytes after subtracting the top-level `payload` field. This identifies a promising
source of index entries; it does not attribute a percentage of the production
index to that worker. The six largest sampled worker groups had no rows eligible
for the configured pruner at that instant. Scheduled cache-volume maintenance
jobs were also present and must not be deleted merely because they are old.

### Recurring vacuum work

Existing Loki logs confirm the supplied 08:40:35 UTC vacuum: 2,851.09 s,
4,047,933 buffer misses and 157,163,088 WAL bytes. The supplied preceding
07:51:43 completion took 1,360.09 s for comparable work. Six additional complete
vacuum records after recovery show the recurring baseline:

| Completion UTC | Elapsed seconds | Buffer misses | WAL bytes | Args-index pages |
| --- | ---: | ---: | ---: | ---: |
| 09:06:37 | 1,472.84 | 4,076,703 | 241,270,382 | 2,288,934 |
| 09:30:45 | 1,360.26 | 4,079,736 | 185,170,624 | 2,289,673 |
| 09:54:47 | 1,362.51 | 4,072,552 | 177,345,250 | 2,290,107 |
| 10:19:20 | 1,395.40 | 4,085,248 | 178,822,545 | 2,291,212 |
| 10:43:22 | 1,376.16 | 4,082,008 | 196,408,064 | 2,291,917 |
| 11:08:02 | 1,415.74 | 4,072,880 | 186,105,422 | 2,292,955 |

Across 08:42:04–11:08:02, these consumed 8,382.91 s of the approximately
8,759 s window: about 96% duty time, 186.7 GiB of buffer-miss reads and
1,111 MiB of WAL. Each logged one index scan, not repeated passes caused by
running out of dead-tuple memory. These are whole-table vacuum totals covering
all indexes; they do not attribute every read to args. A buffer miss can be
satisfied by the OS cache and is not a measured physical volume read.

The 11:08 log is especially informative: 34,304 of 34,929 primary-key pages and
92,702 of 94,783 fetch-index pages were reusable, versus only 805 of 2,292,955
args-index pages. Thus the B-trees have substantial demonstrated reusable space,
while treating most of the GIN file as empty reusable pages would be incorrect.
Only 219 heap tuples were dead but not yet removable in that vacuum. This record
does not support a large old-snapshot backlog as the immediate explanation.

Reproduce the bounded log retrieval in `grafanacloud-logs` with a fixed time
range and at most 10 records:

```logql
{cluster="tuist-production",namespace="tuist",container="postgres",service_name="postgresql"}
  |= "automatic vacuum" |= "tuist.public.oban_jobs"
```

Use 09:00–11:20 UTC for the six records above. `pod` is structured metadata in
these streams, not an indexed label; filtering it as a stream label yielded no
records. The narrowed successful request scanned 2,516 log lines.

### Vacuum and GIN settings

Observed settings: vacuum threshold 50 plus scale factor 0.2; insert threshold
1,000 plus scale factor 0.2; naptime 60 s; three workers; cost delay 2 ms;
autovacuum cost limit -1, inheriting `vacuum_cost_limit=200`; autovacuum work
memory -1, inheriting maintenance memory 512 MiB; `gin_pending_list_limit=4096`
KiB; autovacuum log threshold 600 s; `track_io_timing=off`.

With no index override, GIN fast update is enabled. No `pgstattuple` or
`pageinspect` extension is installed in the application database, so live
pending pages/tuples and entry-page occupancy were **not measured**. The 4 MiB
pending-list setting is a cleanup threshold, not evidence of its current size or
a hard size cap. Do not confuse a 17.5 GiB main index with a pending list.

`pg_stat_statements` is also absent from `tuist`, but the chart installs it in
the **maintenance database `postgres`** and exports only read/write/other
aggregates. Its absence from `tuist` does not mean query statistics are absent
cluster-wide. The connector cannot switch databases. The optional
[query-statistics probe](oban-query-statistics.sql) is for an already-authorized
maintenance-database reader; it was not run in production. No extension was
installed to bridge this visibility gap.

## Query and correctness inventory

Reviewed repository `server/lib` and migrations, plus the locally cached exact
packages from `mix.lock`: Oban 2.21.1, Oban Web 2.12.6 and Oban Met 1.3.0.
`Tuist.Oban.Engine` delegates uniqueness and pruning to Basic; its customization
only retries transaction rollbacks. Schema v10 created the args GIN; the
repository's June migration deliberately retained it when removing the meta GIN.
The August migration advances Oban to v14.

| Consumer | Predicate / dependency | Consequence |
| --- | --- | --- |
| Basic unique insertion | Worker/queue/state/time plus `args @> selected_keys`; whole-map uniqueness also adds `<@`; empty maps use `<@` | Keep containment support and type semantics; neither current GIN nor path_ops accelerates `<@` alone |
| Automation scheduler | `alert_id`, per-alert cadence, includes `completed` | Excluding completed jobs breaks the cadence lookup's index coverage |
| Runner dispatch | `delivery_guid`, two-hour uniqueness, default unique states | Preserve duplicate delivery behavior and the full worker payload |
| Origin webhook | `delivery_id`, includes completed/retryable | Active-only index is insufficient |
| Other unique workers | Build ID; test run/shard/attempt/revision; project/commit or git ref; registry package/version/options; invoice/user; account/server/registration/session/workflow-job/connection/installation/batch IDs | A two-key replacement does not cover the inventory; retain dynamic per-insertion `unique:` options |
| Worker-only sweeps and cron | Worker/queue; sometimes empty args | Full args GIN is not useful for every unique check; do not change uniqueness semantics to optimize it |
| VCS comment cancellation | `args->>'project_id'`, `args->>'git_ref'` | Whole-column GIN does not directly accelerate these extraction equalities |
| Air usage notifications | Extracted notification ID `IN`, worker and nonterminal state | Candidate for a separately measured expression B-tree |
| Coverage deltas | Extracted project ID cast to bigint; git SHA inequality | Different expression shape from containment |
| Registry repair | Lowercased extracted repository handle, or scope/name; version matched in Elixir | Preserve case normalization and package scoping |
| Bundle threshold cancellation | Worker/state/ID in SQL, args comparison in Elixir | Not an args-index lookup |
| Coverage commit rescheduling | ID/state/scheduled time | Not an args-index lookup |
| Oban Web JobQuery | Arbitrary nested `args @> ...`; hints use JSON extraction/unnesting | Payload searches are part of the operator interface; a projection index loses their coverage |
| Oban Met and Tuist PromEx | Queue/state counts and durations | No args-containment predicate found |

The inventory is source-based, not proof that every low-frequency operator
query has been observed. Before dropping index/operator coverage, inspect
maintenance-database statement statistics over representative intervals and
exercise Oban Web. Do not infer usage from a single `pg_stat_activity` snapshot.

A production **EXPLAIN without ANALYZE**, using a synthetic alert UUID and the
scheduler's state/queue/worker/time filters, selected a bitmap scan of
`oban_jobs_args_index` for containment. This supports current use independently
of the cumulative counters; it does not measure execution latency.

Runtime configuration sets Pruner to two hours and 50,000 jobs per pass. In
2.21.1 its default interval is 30 seconds. Basic prunes completed jobs by
**scheduled_at**, cancelled jobs by cancelled_at, discarded jobs by discarded_at;
it does not prune incomplete jobs. Two hours must not be described as two hours
after completion. The automation cadence is capped at one hour, and dispatch
deduplication uses two hours. Shortening retention needs a separate correctness
review and data-export update, and cannot erase existing GIN history by itself.

## Mechanism and local experiment

Indexed state changes prevent HOT updates, so even unchanged args receive new
index references. The large dispatch envelope adds many indexed scalar values.
Pruning removes jobs, but GIN vacuum does not simply remove every historical
entry key: PostgreSQL 16.6's `ginVacuumEntryPage` rebuilds an entry even when its
posting count becomes zero. Entry-tree history, posting trees, reusable pages
and pending entries must be distinguished. This is a plausible explanation for
the production footprint, supported by churn and the experiment, not a measured
production attribution or reclaim percentage.

[The experiment](oban-index-lab.sql) retains 3,000 synthetic jobs after each of
six generations (18,000 inserted, 36,000 state updates, 15,000 deleted per
variant), vacuuming every generation. It uses 70% repeated alert keys, 20%
dispatch envelopes with 60 unique strings, and 10% build references. All variants
retain identical full args; the projection variant changes only the index.

Executed on PostgreSQL **16.9**, Apple Silicon, 128 MiB shared buffers and
64 MiB maintenance memory; production is 16.6 on Linux. The results are a
mechanism test, not production sizing or a concurrent throughput benchmark.

| Index variant | After generation 6 and VACUUM | After concurrent REINDEX | Pending pages after VACUUM |
| --- | ---: | ---: | ---: |
| Full `jsonb_ops` | 42,958,848 B | 9,248,768 B | 0 |
| Full `jsonb_path_ops` | 10,174,464 B | 2,113,536 B | 0 |
| `(args - 'payload') jsonb_ops` | 1,433,600 B | 180,224 B | 0 |
| Full `jsonb_ops`, fastupdate off | 38,780,928 B | 9,248,768 B | 0 |

The current opclass grew from 12,173,312 B after the first vacuum to 42,958,848 B
after the sixth, despite a constant live row count and zero pending pages after
each vacuum. Disabling fast update did not prevent historical growth. The same
opclass rebuild reclaimed 78.5% **in this fixture only**. Path ops was smaller
but still grew. Local warm-cache lookup plans used the full GIN variants. The
projection index required rewriting the query to `(args - 'payload') @> ...`;
the unmodified query sequentially scanned 2,998 rows to find the target (2,065
shared-buffer hits, versus 11 with full jsonb_ops). This demonstrates why simply
replacing the index with that expression is not safe for Basic's existing SQL.

The script asserts matching top-level and nested containment results for all
four variants and exercises local concurrent rebuilds. Its database/version/
local-address guard fails with exit 3 outside the designated database, and an
existing experiment schema causes an error instead of destructive cleanup.

Run against a fresh **disposable local** PostgreSQL 16 instance:

```sh
createdb -h /tmp -p 55439 oban_index_lab
psql -X -h /tmp -p 55439 -d oban_index_lab \
  -f infra/cnpg/oban-index-lab.sql > /tmp/oban-index-lab-output.txt 2>&1
```

Port 55439 was an isolated local instance for this investigation, not an
application or shared staging database. The script installs `pgstattuple` only
there. No production data is copied. Keep verbose output to compare vacuum
buffers/WAL and statement timings; do not extrapolate local cache-hit timings to
Cloud Volume latency.

## Remediation comparison

| Option | Benefit | Cost / decision |
| --- | --- | --- |
| Same-definition concurrent rebuild | Reclaims historical structure while preserving every current predicate and application binary | Preferred first maintenance candidate; resource-heavy, may regrow; production savings require a restored-data measurement |
| Full `jsonb_path_ops` GIN | Smaller scalar representation in the fixture, retains nested containment without an engine fork | Leading durable index candidate; still indexes every payload value, no key-existence `?`/`?|`/`?&` support, empty structures can require a full index search; qualify before replacement |
| Targeted expression B-trees or projected GIN | Potentially much less indexing work | Basic's containment SQL will not automatically use extraction/projection indexes; requires coordinated query/engine changes and broader worker/dashboard coverage |
| Partial index over incomplete jobs | Removes terminal rows from indexed live set | Misses completed-state deduplication; reject as a blanket replacement |
| Reduce dispatch payload to fields actually consumed | Fewer indexed values, smaller TOAST/WAL without weakening uniqueness | Audit every queued/waiting/in-progress/completed handler, steps, fallback and replay path; test old queued payloads with new workers and new payloads with rollback binaries; update data-export docs |
| Move payload to separate durable storage | Keep dedup keys small while retaining replay body | Adds ownership, atomic enqueue, retry and cleanup contracts; do not replace durable args with ephemeral memory or a short-lived signed URL |
| Shorter retention / bigger prune batches | Smaller live population if backlog exists | Sample does not establish a prune backlog; deletion adds churn, does not reclaim historical entry keys; protect cadence and delivery dedup windows |
| More frequent/faster vacuum | May shorten dead-reference and pending-list lifetime | Already near-continuous work; lower thresholds or higher cost limits can increase storage competition; memory increase is not justified by the observed single index scan |
| Fastupdate off / pending-limit tuning | Changes foreground/background work distribution | Local growth persists with fastupdate off; risks insert latency. Measure actual pending-list cycles and enqueue p95/p99 before changing |

## Rollout and rollback gates

1. **Qualify on an isolated restore first.** An authorized operator restores a
   recent backup into an isolated environment with the same PostgreSQL minor
   version and settings. Do not move production payloads into a laptop fixture.
   Record old and freshly rebuilt identical-index bytes, elapsed time, peak disk
   usage, WAL generated, lock waits and vacuum work. Keep production read-only
   until the maintenance budget is reviewed. Repeat representative insertion,
   processing, pruning and dashboard queries; a restore with idle writers only
   measures reclaimability, not loaded throughput.
2. **Prepare the production window.** Confirm storage is healthy, backups and WAL
   archiving are healthy, replicas caught up, no conflicting DDL/builds, and no
   long transactions/snapshots that would extend a concurrent build. Budget room
   for old and new index copies together, build scratch space and retained WAL
   on every replica. Derive the budget from the restore, with an explicit safety
   margin; do not assume the new index will be tiny. Rebuild only args first so
   its effect can be measured. B-tree rebuilds are separate candidates.
3. **Use human-authorized database-owner maintenance.** The commands below are
   proposed, **not executed**. Kubernetes execution requires a matching,
   human-initiated JIT window; it does not authorize fetching admin credentials.
   Use the established operator access path, not the Atlas read-only connector.
   In a dedicated session, outside any transaction:

   ```sql
   SET application_name = 'oban-args-index-maintenance';
   SET lock_timeout = '2s';
   SET statement_timeout = '30min';
   REINDEX (VERBOSE) INDEX CONCURRENTLY public.oban_jobs_args_index;
   ```

   Proceed only if the restore fits comfortably inside that timeout. This keeps
   the same opclass and index name and permits concurrent DML, but introduces
   extra scans, writes and snapshot waits. Monitor `pg_stat_progress_create_index`
   using an authorized statistics reader, plus free space, replica replay lag,
   archiver health, DB pool waits, enqueue/fetch latency and queue age. Agree
   numerical abort thresholds against the pre-window baseline and existing SLOs
   before starting. Cancel the maintenance session if those gates fail; do not
   disable vacuum or kill application transactions to make it finish.
4. **Verify the swap and subsequent vacuums.** Confirm index validity/readiness,
   opclass and definition, bytes, and no invalid leftover build indexes. Repeat
   the same EXPLAIN and bounded diagnostics. Exercise duplicate inserts from
   two application replicas for alert, dispatch, Origin, build/test, registry,
   billing and dynamically configured jobs, including completed/retryable states,
   infinite periods, empty args, null versus missing and numeric versus string
   values. Verify nested dashboard searches, worker throughput and retry behavior.
   Compare at least two subsequent vacuum completions with matched churn rates,
   including misses, WAL and elapsed time. Check regrowth after a day and a week
   before deciding whether another rebuild is justified. These observations are
   planned validation, not a scheduled automation or a completed production test.
5. **Handle failure without deleting the serving index.** Same-definition REINDEX
   changes no logical data and needs no application rollback. An interrupted
   concurrent operation may leave `_ccnew` or `_ccold` indexes. Inspect each
   object's OID, definition, validity and readiness and the original serving
   index before proposing cleanup. Do not blindly drop names by suffix or use
   `IF NOT EXISTS` to hide an invalid build. If cleanup is needed, it is a
   separately reviewed concurrent drop under the same human access rules.

For a later path-ops migration, first create a distinctly named candidate
concurrently on staging/restored data, then qualify representative traffic with
the old index absent **only there** so it cannot hide regressions. A production
build temporarily maintains both indexes and needs its own write/WAL budget.
Keep the old index through validation, remove it concurrently only after
acceptance, and test the down path by recreating a valid jsonb_ops index before
dropping path_ops. Never hold a DDL transaction around concurrent operations.
Any Ecto migration must disable the DDL transaction and migration lock, use a
unique version, run migration-safety checks, and have explicit interrupted-build
recovery. An automatic migration is intentionally deferred until these gates pass.

## Validation and remaining uncertainty

Completed: production catalog/settings reads, two counter observations, bounded
payload/retention samples, non-executing production plan, existing vacuum log
inspection, pinned package source inventory, four local synthetic churn/vacuum/
concurrent-reindex variants, containment assertions and experiment refusal check.
The read-only diagnostic script was exercised on a local Oban-shaped fixture;
the optional statistics probe completed against a local preloaded
`pg_stat_statements` instance (no matching application statements). The experiment
refusal check returned exit 3 before creating objects in the wrong database.
No application code changed and no ExUnit or application throughput test was run.

Still needed: representative restored-data size and rebuild resource measurements;
privileged existing statistics visibility (without retrieving credentials);
pending-list observations if an already-installed/authorized mechanism becomes
available; low-frequency query inventory; loaded multi-replica qualification;
post-maintenance growth and vacuum comparison. These gaps prevent an exact
production savings claim or a production-ready replacement migration.

References: [PostgreSQL 16 GIN implementation](https://www.postgresql.org/docs/16/gin-implementation.html),
[JSON indexing](https://www.postgresql.org/docs/16/datatype-json.html#JSON-INDEXING),
[concurrent REINDEX](https://www.postgresql.org/docs/16/sql-reindex.html#SQL-REINDEX-CONCURRENTLY),
[GIN pending-list statistics](https://www.postgresql.org/docs/16/pgstattuple.html),
[PostgreSQL 16.6 vacuum source](https://github.com/postgres/postgres/blob/REL_16_6/src/backend/access/gin/ginvacuum.c),
[Oban 2.21.1 Basic engine](https://github.com/oban-bg/oban/blob/v2.21.1/lib/oban/engines/basic.ex),
[runtime retention configuration](../../server/config/runtime.exs),
[custom engine](../../server/lib/tuist/oban/engine.ex).
