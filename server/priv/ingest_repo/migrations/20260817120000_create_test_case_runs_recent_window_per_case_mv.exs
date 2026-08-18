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
      states compress heavily, so the byte-based merge block limiter sizes
      blocks from on-disk bytes and under-counts the in-memory arena.

  This keeps plain `Int64` run keys (`-ran_at_micros`) instead, which take
  `groupArraySorted`'s specialised numeric path, and splits the two flags into
  conditional aggregates over the same key. Reading a 1000-run window across a
  2000-test-case range measured at 186 MiB and 249ms.

  ## Why `Distinct`

  `test_case_runs` is a ReplacingMergeTree and flaky detection re-inserts a run
  to set `is_flaky`, so one logical run reaches the view as several physical
  rows. `groupArraySortedDistinct` collapses them on the run key, and the
  collapse survives state merges, so a logical run occupies exactly one slot
  however many times it was re-inserted. The bucket is therefore sized at the
  window cap rather than at a multiple of it, and the reader needs no
  de-duplication pass.

  Membership carries each flag, which removes flag reconciliation entirely. A
  correction is the only row of its run with `is_flaky` set, so the run key
  lands in `flaky_runs` exactly once; successes are never re-marked, so
  `successful_runs` is likewise one entry per run. Each column is filled by its
  own view over the same source, mirroring how the 100-run bucket already pairs
  a flaky view with a success view against one table.

  `flaky_runs` and `successful_runs` are bounded at the same cap and hold the
  most recent keys of their kind. A run inside the window is among the most
  recent runs overall, so if it carries a flag it is also among the most recent
  runs carrying that flag, and it cannot be missed.

  `PARTITION BY intHash32(project_id) % 16` is what the retired aggregates
  lacked. It bounds a merge to a sixteenth of the table and prunes a read that
  filters on `project_id` to a single partition. `merge_max_block_size` is
  pinned low as well, because the byte-based limiter cannot see the size of an
  aggregate state arena.

  No backfill runs here, matching `test_case_runs_validated_on_branch`: a
  synchronous scan of a multi-billion-row fact table blocks the deploy's
  migration hook. A separate migration seeds this from the 100-run bucket.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @bucket_size 1000

  def up do
    drop_views!()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_recent_window_per_case (
      project_id Int64,
      test_case_id UUID,
      recent_runs AggregateFunction(groupArraySortedDistinct(#{@bucket_size}), Int64),
      flaky_runs AggregateFunction(groupArraySortedDistinct(#{@bucket_size}), Int64),
      successful_runs AggregateFunction(groupArraySortedDistinct(#{@bucket_size}), Int64)
    ) ENGINE = AggregatingMergeTree
    PARTITION BY intHash32(project_id) % 16
    ORDER BY (project_id, test_case_id)
    SETTINGS merge_max_block_size = 256
    """)

    for {view, column, filter} <- [
          {"test_case_runs_recent_window_per_case_mv", "recent_runs", ""},
          {"test_case_runs_recent_window_flaky_per_case_mv", "flaky_runs", "AND is_flaky"},
          {"test_case_runs_recent_window_success_per_case_mv", "successful_runs",
           "AND status = 'success'"}
        ] do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("""
      CREATE MATERIALIZED VIEW IF NOT EXISTS #{view}
      TO test_case_runs_recent_window_per_case
      AS SELECT
        project_id,
        assumeNotNull(test_case_id) AS test_case_id,
        groupArraySortedDistinctState(#{@bucket_size})(-toUnixTimestamp64Micro(ran_at)) AS #{column}
      FROM test_case_runs
      WHERE test_case_id IS NOT NULL #{filter}
      GROUP BY project_id, test_case_id
      """)
    end
  end

  def down do
    drop_views!()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_recent_window_per_case")
  end

  defp drop_views! do
    for view <- [
          "test_case_runs_recent_window_per_case_mv",
          "test_case_runs_recent_window_flaky_per_case_mv",
          "test_case_runs_recent_window_success_per_case_mv"
        ] do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("DROP VIEW IF EXISTS #{view}")
    end
  end
end
