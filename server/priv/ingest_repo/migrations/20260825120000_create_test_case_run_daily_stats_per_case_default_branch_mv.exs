defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunDailyStatsPerCaseDefaultBranchMv do
  @moduledoc """
  Per-test-case daily aggregate of `test_case_runs`, restricted to runs on the
  project's default branch.

  Reliability answers "is this test trustworthy", which is a question about the
  trunk. Measuring it over every branch lets a work-in-progress failure on a pull
  request move the same number that decides whether an established test gets
  quarantined, which is what `test_case_run_daily_stats_per_case` does today.

  ## Why a second table rather than a branch dimension

  Keying the existing aggregate on `git_branch` was measured against production
  before this was written. Distinct `(test_case_id, git_branch)` pairs over a
  single day, against distinct test cases:

      project 2785   35,018 test cases   156 branches    86.1x
      project 1227   48,593 test cases    49 branches    31.9x
      project 1078   40,853 test cases    66 branches    25.9x
      project 2382   38,898 test cases    36 branches    14.3x

  `test_case_run_daily_stats_per_case` holds 74.2M rows, and `FlakyTestsMonitor`
  merges a calendar window of it on every evaluation. A branch dimension
  multiplies both by those factors. That the states are counters rather than
  quantile reservoirs lowers the per-row cost, not the multiplier, and the
  multiplier is what does not fit.

  A boolean split would only double the table, but it cannot be added to the
  existing one's sort key in place: every row already written would claim
  `is_default_branch = false` while holding runs from every branch, which is the
  grain corruption `20260818130000` cites for not adding `is_ci` there either.
  Rebuilding that table instead would put every flakiness alert in production on
  a freshly seeded aggregate to deliver a change none of them asked for.

  So this is a parallel table carrying only default-branch runs. Flakiness alerts
  read the existing aggregate untouched, and the two never have to agree about
  anything but their own grain.

  ## No backfill

  Nothing seeds this table; the view fills it forward from the moment it exists.

  A seed here would scan 742M runs across 266 projects to cover a 30-day window,
  and backfills over this table family are the part of this work with a history
  of exhausting production memory — `20260817120000` shipped without one for that
  reason, and `20260818130000` carries a halving-by-date retry because a bounded
  window still did not reliably fit.

  What makes going without one safe is the sample floor in
  `FlakyTestsMonitor`. A calendar window has no natural minimum the way a rolling
  window does, so a scoped alert reading a table with one day in it would
  otherwise compute a reliability rate off a single run and act on it. The floor
  makes a test case unmeasurable until the window holds enough runs to describe,
  which is the same answer it gives a genuinely quiet test case, and it is needed
  whether or not this table is seeded: scoping to one branch already cuts every
  sample to a fraction of what the alert used to see.

  So the convergence is not a period of wrong answers, it is a period of
  "not enough data yet", and it resolves per test case as runs accrue rather than
  on a deploy's schedule.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "test_case_run_daily_stats_per_case_default_branch"

  def up do
    drop_objects()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE #{@table} (
      project_id Int64,
      date Date,
      test_case_id UUID,
      run_count AggregateFunction(count),
      flaky_run_count AggregateFunction(sum, UInt8),
      successful_run_count AggregateFunction(sum, UInt8)
    ) ENGINE = AggregatingMergeTree
    ORDER BY (project_id, date, test_case_id)
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW #{@table}_mv
    TO #{@table}
    AS SELECT
      project_id,
      toDate(inserted_at) AS date,
      assumeNotNull(test_case_id) AS test_case_id,
      countState() AS run_count,
      sumState(toUInt8(is_flaky)) AS flaky_run_count,
      sumState(toUInt8(status = 'success')) AS successful_run_count
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL AND is_default_branch
    GROUP BY project_id, date, test_case_id
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
