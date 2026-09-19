defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsDefaultBranchRecentWindowMv do
  @moduledoc """
  Rolling-window aggregate of `test_case_runs`, restricted to runs on the
  project's default branch.

  This is the `rolling` counterpart to
  `test_case_run_daily_stats_per_case_default_branch`, and it exists as its own
  bucket for a reason the calendar aggregate does not have.

  ## Why filtering the shared bucket does not work

  `test_case_runs_recent_window_per_case` holds the latest 2000 entries per test
  case across every branch, and `FlakyTestsMonitor` refuses to evaluate a window
  until it is completely filled. Reading the default-branch subset out of that
  bucket after the merge therefore depends on the default branch being a large
  enough share of a test case's recent runs to fill the window on its own.

  Measured against production, it is not. On project 1227 the default branch is
  13.3% of a day's runs, the rest spread across feature branches, so a
  2000-entry all-branch bucket carries roughly 266 default-branch entries. Every
  window above that size would stop evaluating, silently, with no signal
  distinguishing "measured and healthy" from "not measurable" — and on the
  recovery path that reads as "the condition cleared", which un-quarantines a
  test that never recovered.

  Filtering at insert instead gives the window 2000 default-branch entries to
  work with, so a configured window means the same thing on this bucket as it
  does on the shared one.

  ## Encoding

  Identical to `test_case_runs_recent_window_per_case`: one `Int64` per run,

      -toUnixTimestamp64Micro(ran_at) * 4 + is_flaky * 2 + is_success

  No third bit is added for the branch. The table already holds only
  default-branch runs, so a bit distinguishing them would be constant, and
  keeping the packing identical lets both buckets share every reader expression
  in `FlakyTestsMonitor` including the linear de-duplication pass.

  The bucket is sized at twice the 1000-run product cap for the same reason as
  the shared one: `test_case_runs` is a ReplacingMergeTree and flaky detection
  re-inserts a run to set `is_flaky`, and
  `Tests.report_test_case_run_multiplicity/3` bounds that at two physical rows
  per logical run.

  ## No backfill

  Nothing seeds this table, matching `20260817120000`, which shipped the shared
  bucket the same way: a synchronous scan of a multi-billion row fact table
  blocks the deploy's migration hook, and backfills over this table family have
  exhausted production memory before. Building `groupArraySorted(2000)` states
  is the most memory-hungry shape of the lot, so this is the seed least worth
  attempting.

  Going without one costs nothing but time here, because the window-filled
  requirement already separates "not measurable" from "measured and healthy".
  An alert on a partially accrued window is not evaluated at all rather than
  evaluated against a short one, so there is no period during which it can be
  wrong — only a period during which it is quiet, ending per test case as its
  own runs accrue.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "test_case_runs_default_branch_recent_window_per_case"
  @bucket_size 2000

  def up do
    drop_objects()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE #{@table} (
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
    CREATE MATERIALIZED VIEW #{@table}_mv
    TO #{@table}
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArraySortedState(#{@bucket_size})(
        -toUnixTimestamp64Micro(ran_at) * 4 + toUInt8(is_flaky) * 2 + toUInt8(status = 'success')
      ) AS recent_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL AND is_default_branch
    GROUP BY project_id, test_case_id
    """)
  end

  def down do
    drop_objects()
  end

  defp drop_objects do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS #{@table}_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS #{@table}")
  end
end
