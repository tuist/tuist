defmodule Tuist.IngestRepo.Migrations.CreateCommandEventsByNameRanAtMv do
  @moduledoc """
  Creates `command_events_by_name_ran_at`, sorted by `(project_id, name, ran_at)`
  for the name-filtered "recent runs" list queries (cache runs, generate runs,
  the `/runs` API when a name filter is present).

  These queries filter a single `name` (e.g. `name = 'cache'`) and page by
  `ran_at DESC`. `command_events_by_ran_at` is sorted by `(project_id, ran_at)`
  only, so `name` is applied as a predicate while ClickHouse scans in `ran_at`
  order. When the filtered command is a small fraction of a project's events
  (e.g. `cache` is ~0.08% of a high-volume project), collecting a page of N rows
  scans deep into history — up to the whole project. Production showed a single
  page reading ~16M rows / ~12 GiB (p90 ~7.6s).

  With `name` in the sort key, `(project_id, name)` is a contiguous range and
  `ran_at` is ordered within it, so `ran_at DESC LIMIT N` reads ~one granule via
  reverse read-in-order regardless of how sparse the command is.

  The target table is intentionally NOT partitioned. `command_events` is
  partitioned by `toYYYYMM(ran_at)`, which fans a reverse read-in-order scan
  across every monthly part (a tail granule each); an unpartitioned table keeps
  the `(project_id, name)` range in one contiguous run of parts.

  `command_events_by_ran_at` (project_id, ran_at) is kept for the no-name
  `ran_at`-ordered queries (e.g. ModuleCacheLive recent runs, the `/runs` API
  without a name filter), which rely on read-in-order over `ran_at` directly.

  ## Gap-free, memory-bounded backfill (no POPULATE, one partition at a time)

  `POPULATE`/a single full-table `INSERT ... SELECT *` are both avoided. The
  first misses rows inserted while it runs; the second copies all ~27M wide rows
  (with the large `Array(String)` columns) in one statement, which exceeded the
  shared ClickHouse memory ceiling under live load (`Code: 241
  MEMORY_LIMIT_EXCEEDED`). Instead:

    1. Drop any leftovers from a previous failed attempt so we start from an
       empty, consistent table.
    2. Create the empty target (`EMPTY AS SELECT *` copies the column types only,
       no data, indexes, or projections).
    3. Create the materialized view with `TO` and no `POPULATE`. From here every
       insert into `command_events` is written to the target synchronously.
    4. Backfill one `toYYYYMM(ran_at)` partition at a time (single-threaded), so
       each statement's memory is bounded by one month of data rather than the
       whole table. The per-partition `id` anti-join excludes rows the view
       already captured since creation, so no row is dropped or duplicated even
       while ingestion continues.
  """

  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS command_events_by_name_ran_at_mv SYNC")
    IngestRepo.query!("DROP TABLE IF EXISTS command_events_by_name_ran_at SYNC")

    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS command_events_by_name_ran_at
    ENGINE = MergeTree
    ORDER BY (project_id, name, ran_at)
    EMPTY AS SELECT * FROM command_events
    """)

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_name_ran_at_mv
    TO command_events_by_name_ran_at
    AS SELECT * FROM command_events
    """)

    %{rows: partitions} =
      IngestRepo.query!(
        "SELECT DISTINCT toYYYYMM(ran_at) AS partition FROM command_events ORDER BY partition"
      )

    for [partition] <- partitions, is_integer(partition) do
      Logger.info("Backfilling command_events_by_name_ran_at partition #{partition}")

      IngestRepo.query!(
        """
        INSERT INTO command_events_by_name_ran_at
        SELECT * FROM command_events
        WHERE toYYYYMM(ran_at) = #{partition}
          AND id NOT IN (
            SELECT id FROM command_events_by_name_ran_at WHERE toYYYYMM(ran_at) = #{partition}
          )
        SETTINGS max_threads = 1, max_insert_threads = 1
        """,
        [],
        timeout: :infinity
      )
    end
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS command_events_by_name_ran_at_mv SYNC")
    IngestRepo.query!("DROP TABLE IF EXISTS command_events_by_name_ran_at SYNC")
  end
end
