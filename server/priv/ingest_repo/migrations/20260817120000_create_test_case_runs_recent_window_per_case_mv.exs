defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsRecentWindowPerCaseMv do
  @moduledoc """
  Rolling-window aggregate that can serve the full 1000-run product cap.

  The bucketed aggregates this replaces stored
  `AggregateFunction(groupArraySorted(N), Tuple(Int64, UInt8))` — one column of
  `(-ran_at_micros, is_flaky)` for flakiness monitors and a parallel column of
  `(-ran_at_micros, is_success)` for reliability monitors. That shape does not
  scale with N on either side:

    * Reading it puts `groupArraySorted` on ClickHouse's generic tuple
      comparator. Merging a 1000-entry state across a 2000-test-case evaluation
      range measured at 650 MiB and 1.7s, against the 1 GiB per-query ceiling
      the monitor sets so concurrent evaluations leave headroom for runner
      lifecycle writes.
    * Merging it exhausted the production memory limit at 750 entries. The
      states compress ~59x (38 MiB of tuple state landed as 665 KiB on disk), so
      the byte-based merge block limiter sizes blocks from on-disk bytes and
      under-counts the in-memory arena by the same factor.

  Packing each run into a single `Int64` fixes both. `groupArraySorted` takes
  its specialized numeric path, and the two flags fit in the low bits, so one
  column serves flakiness, flaky-run-count, and reliability instead of two
  columns each serving one monitor:

      -toUnixTimestamp64Micro(ran_at) * 4 + is_flaky * 2 + is_success

  A 2000-entry packed state serving a 1000-run window measured at 61 MiB and
  154ms — under the 100-entry tuple aggregate's 73 MiB and 152ms for a 75-run
  window, which is what production reads today.

  Ordering falls out of the packing. The timestamp is negated, so ascending
  order is latest-first and `groupArraySortedMerge` keeps the newest entries.
  Within one logical run the flaky correction row raises `is_flaky` from 0 to 1,
  so it sorts after the original and the reader's linear de-duplication keeps
  it. The low bits never perturb ordering across runs because the timestamp is
  scaled past them.

  The bucket is sized at twice the 1000-run cap on purpose. `test_case_runs` is
  a ReplacingMergeTree and flaky detection re-inserts a run to set `is_flaky`,
  so a logical run can occupy more than one physical slot.
  `Tests.report_test_case_run_multiplicity/3` enforces and alerts on at most two
  physical rows per logical run, so 2000 slots hold 1000 distinct runs even when
  every run in the window was corrected. Windows up to the cap are exact rather
  than relying on a fractional headroom margin.

  `PARTITION BY intHash32(project_id) % 16` is what the retired aggregates
  lacked. It bounds a merge to a sixteenth of the table and prunes a read that
  filters on `project_id` to a single partition. `merge_max_block_size` is
  pinned low as well, because the byte-based limiter cannot see the size of an
  aggregate state arena.

  No backfill runs here, matching `test_case_runs_validated_on_branch`: a
  synchronous scan of a multi-billion-row fact table blocks the deploy's
  migration hook, and past backfills of this table family exhausted production
  memory. The monitor requires a large window to be completely filled before it
  evaluates, so a window converges as runs accrue rather than measuring against
  a partial one.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @bucket_size 2000

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_recent_window_per_case_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_recent_window_per_case (
      project_id Int64,
      test_case_id UUID,
      recent_runs AggregateFunction(groupArraySorted(#{@bucket_size}), Int64)
    ) ENGINE = AggregatingMergeTree
    PARTITION BY intHash32(project_id) % 16
    ORDER BY (project_id, test_case_id)
    SETTINGS merge_max_block_size = 256
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_recent_window_per_case_mv
    TO test_case_runs_recent_window_per_case
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArraySortedState(#{@bucket_size})(
        -toUnixTimestamp64Micro(ran_at) * 4 + toUInt8(is_flaky) * 2 + toUInt8(status = 'success')
      ) AS recent_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, test_case_id
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_recent_window_per_case_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_recent_window_per_case")
  end
end
