defmodule Tuist.IngestRepo.Migrations.CreateCommandEventsByNameRanAtMv do
  @moduledoc """
  Creates `command_events_by_name_ran_at`, a materialized view sorted by
  `(project_id, name, ran_at)` for the name-filtered "recent runs" list queries
  (cache runs, generate runs, the `/runs` API when a name filter is present).

  These queries filter a single `name` (e.g. `name = 'cache'`) and page by
  `ran_at DESC`. `command_events_by_ran_at` is sorted by `(project_id, ran_at)`
  only, so `name` is applied as a predicate while ClickHouse scans in `ran_at`
  order. When the filtered command is a small fraction of a project's events
  (e.g. `cache` is ~0.08% of a high-volume project), collecting a page of N rows
  scans deep into history — up to the whole project. Production showed a single
  page reading ~16M rows / ~12 GiB (p90 ~7.6s).

  With `name` in the sort key, `(project_id, name)` is a contiguous range and
  `ran_at` is ordered within it, so `ran_at DESC LIMIT N` reads ~one granule via
  reverse read-in-order regardless of how sparse the command is. The same
  production page reads ~75K rows / ~127 MiB (~209ms) against this layout.

  The view is intentionally NOT partitioned. `command_events` is partitioned by
  `toYYYYMM(ran_at)`, which fans a reverse read-in-order scan across every
  monthly part (a tail granule each); an unpartitioned view keeps the
  `(project_id, name)` range in one contiguous run of parts.

  `command_events_by_ran_at` (project_id, ran_at) is kept for the no-name
  `ran_at`-ordered queries (e.g. ModuleCacheLive recent runs, the `/runs` API
  without a name filter), which rely on read-in-order over `ran_at` directly.

  No secondary indexes are defined. `command_events_by_ran_at` carries
  minmax/bloom indexes (is_ci, user_id, cacheable_targets_count) because its
  `(project_id, ran_at)` working set is a whole project (millions of rows). Here
  `(project_id, name)` already isolates a small contiguous range, so the runs
  list's secondary filters (`is_ci`/`user_id` via "ran by", status, branch, …)
  are cheap to apply as plain predicates over it; skip indexes would add write
  and storage cost for negligible pruning. This also lets the view use the
  implicit `SELECT *` schema instead of restating every column.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_name_ran_at
    ENGINE = MergeTree
    ORDER BY (project_id, name, ran_at)
    POPULATE
    AS SELECT * FROM command_events
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_name_ran_at SYNC"
  end
end
