defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunDailyStatsPerCaseDefaultBranchMv do
  @moduledoc """
  Per-test-case daily aggregate of `test_case_runs`, restricted to runs on the
  project's default branch.

  Reliability answers "is this test trustworthy", which is a question about the
  trunk. Measuring it over every branch lets a work-in-progress failure on a
  pull request move the same number that decides whether an established test
  gets quarantined, which is what
  `test_case_run_daily_stats_per_case` does today.

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

  So this is a parallel table carrying only default-branch runs. Alerts that opt
  out read the existing aggregate untouched, and the two never have to agree
  about anything but their own grain.

  ## What the seed covers

  The live view reads `test_case_runs.is_default_branch`, denormalized at
  ingestion. The seed cannot: rows written before that column existed carry its
  `false` default. It compares `git_branch` against the project's default branch
  name read from Postgres instead, one project at a time, which is the same
  comparison the ingestion path makes and needs no rewrite of a multi-billion
  row fact table to reproduce.

  The seed covers a trailing `@backfill_window_days` window rather than all
  history. `FlakyTestsMonitor` clamps a scoped calendar window to the oldest
  date this table holds for the project, so an alert configured with a longer
  window measures over what exists rather than reporting a rate off a partially
  seeded range. The clamp lifts on its own as the view fills forward.

  The memory discipline, the per-project ranges and the halving-by-date retry
  are carried over from `20260818130000` unchanged; the reasoning there applies
  here for the same reasons.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "test_case_run_daily_stats_per_case_default_branch"
  @backfill_window_days 90
  @attempt_throttle_ms 250
  @range_attempts 2
  @max_memory_usage 1_073_741_824
  @max_bytes_before_external_group_by 268_435_456

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

    {boundary, window_start, window_end} = backfill_bounds()

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

    backfill(boundary, window_start, window_end)
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

  # Read from ClickHouse so the boundary is on the same clock as the
  # `inserted_at` values it is compared against. The view is created after this
  # instant is read, so a run inserted in between is seen by neither rather than
  # by both: a run counted twice moves a reliability rate, a run missed for a
  # few milliseconds does not.
  defp backfill_bounds do
    {:ok, %{rows: [[boundary, window_start, window_end]]}} =
      IngestRepo.query(
        """
        SELECT
          now64(6) AS boundary,
          toDate(boundary) - {days:UInt16} AS window_start,
          toDate(boundary) AS window_end
        """,
        %{days: @backfill_window_days}
      )

    Logger.info("Backfilling #{@table} over #{window_start}..#{window_end}, up to #{boundary}")

    {boundary, window_start, window_end}
  end

  # The migration task boots only the ingest repo, so Postgres is started for
  # the length of this read and stopped again rather than being linked to it.
  defp default_branches do
    Ecto.Migrator.with_repo(Repo, fn _repo ->
      Repo.query!(
        "SELECT id, default_branch FROM projects WHERE default_branch IS NOT NULL AND default_branch <> ''"
      )
    end)
    |> case do
      {:ok, %{rows: rows}, _apps} -> Map.new(rows, fn [id, branch] -> {id, branch} end)
      {:ok, result, _apps} -> Map.new(result.rows, fn [id, branch] -> {id, branch} end)
    end
  end

  defp backfill(boundary, window_start, window_end) do
    branches = default_branches()

    Logger.info("Seeding #{@table} for #{map_size(branches)} projects with a default branch")

    for partition <- partitions_since(window_start) do
      project_ids =
        partition
        |> project_ids_for_partition(window_start)
        |> Enum.filter(&Map.has_key?(branches, &1))

      Logger.info(
        "Backfilling partition #{partition} into #{@table} (#{length(project_ids)} projects)"
      )

      Enum.each(project_ids, fn project_id ->
        backfill_range(
          partition,
          project_id,
          Map.fetch!(branches, project_id),
          window_start,
          window_end,
          boundary
        )
      end)
    end
  end

  defp partitions_since(window_start) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
          AND toUInt32(partition) >= {min_partition:UInt32}
        ORDER BY partition DESC
        """,
        %{table: "test_case_runs", min_partition: year_month(window_start)}
      )

    Enum.map(rows, fn [partition] -> String.to_integer(partition) end)
  end

  defp project_ids_for_partition(partition, window_start) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT project_id
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
          AND toDate(inserted_at) >= {window_start:Date}
          AND project_id IS NOT NULL
          AND test_case_id IS NOT NULL
        ORDER BY project_id
        """,
        %{partition: partition, window_start: window_start},
        timeout: 600_000
      )

    Enum.map(rows, fn [project_id] -> project_id end)
  end

  defp backfill_range(
         partition,
         project_id,
         branch,
         from_date,
         to_date,
         boundary,
         attempts \\ @range_attempts
       ) do
    Process.sleep(@attempt_throttle_ms)

    insert_range(partition, project_id, branch, from_date, to_date, boundary)
  rescue
    e in Ch.Error ->
      cond do
        not overrun?(e) ->
          reraise e, __STACKTRACE__

        attempts > 1 ->
          Logger.warning(
            "ClickHouse could not fit #{describe(project_id, from_date, to_date)}; " <>
              "retrying in 5s (#{attempts - 1} attempts left)"
          )

          Process.sleep(:timer.seconds(5))

          backfill_range(
            partition,
            project_id,
            branch,
            from_date,
            to_date,
            boundary,
            attempts - 1
          )

        Date.compare(from_date, to_date) == :lt ->
          midpoint = Date.add(from_date, div(Date.diff(to_date, from_date), 2))

          Logger.warning(
            "ClickHouse could not fit #{describe(project_id, from_date, to_date)}; splitting at #{midpoint}"
          )

          backfill_range(partition, project_id, branch, from_date, midpoint, boundary)
          backfill_range(partition, project_id, branch, Date.add(midpoint, 1), to_date, boundary)

        true ->
          Logger.warning(
            "ClickHouse could not fit #{describe(project_id, from_date, to_date)}, " <>
              "the smallest range there is; skipping it"
          )
      end
  end

  # `date` groups on `inserted_at` to match the live view and the table this
  # parallels. `is_default_branch` is deliberately not read here: rows written
  # before that column existed carry its `false` default, so the seed makes the
  # comparison the ingestion path makes instead.
  defp insert_range(partition, project_id, branch, from_date, to_date, boundary) do
    IngestRepo.query!(
      """
      INSERT INTO #{@table}
        (project_id, date, test_case_id, run_count, flaky_run_count, successful_run_count)
      SELECT
        project_id,
        toDate(inserted_at) AS date,
        assumeNotNull(test_case_id) AS test_case_id,
        countState() AS run_count,
        sumState(toUInt8(is_flaky)) AS flaky_run_count,
        sumState(toUInt8(status = 'success')) AS successful_run_count
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND inserted_at < {boundary:DateTime64(6)}
        AND project_id = {project_id:Int64}
        AND toDate(inserted_at) >= {from_date:Date}
        AND toDate(inserted_at) <= {to_date:Date}
        AND git_branch = {branch:String}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, date, test_case_id
      SETTINGS
        optimize_aggregation_in_order = 1,
        max_threads = 1,
        max_memory_usage = #{@max_memory_usage},
        max_bytes_before_external_group_by = #{@max_bytes_before_external_group_by}
      """,
      %{
        partition: partition,
        project_id: project_id,
        branch: branch,
        from_date: from_date,
        to_date: to_date,
        boundary: boundary
      },
      timeout: 1_200_000
    )
  end

  defp overrun?(%Ch.Error{} = error) do
    message = to_string(error.message)

    String.contains?(message, "MEMORY_LIMIT_EXCEEDED") or
      String.contains?(message, "TABLE_IS_READ_ONLY")
  end

  defp describe(project_id, from_date, to_date),
    do: "project #{project_id} over #{from_date}..#{to_date}"

  defp year_month(%Date{year: year, month: month}), do: year * 100 + month
end
