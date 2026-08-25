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

  ## Why this one seeds and the shared bucket did not

  `20260817120000` shipped with no backfill because a synchronous scan of a
  multi-billion row fact table blocks the deploy's migration hook, and past
  backfills of this table family exhausted production memory.

  Two things are different here. The filter admits only default-branch runs,
  which on the projects that drive the cost is a small fraction of the volume
  that made the unfiltered seed prohibitive. And reliability scoping is on by
  default, so an unseeded bucket does not mean "a new capability converges" —
  it means every existing rolling reliability alert stops evaluating until the
  window refills, which for a low-frequency project is weeks.

  Runs ingested during this release's own pod rollout are the one thing the seed
  does not cover: the outgoing pods do not set `is_default_branch`, so the view
  filters them out and the seed's boundary is already behind them. See
  `20260818140000` for why that window cannot be closed inside one release and
  why it heals as the read window moves past it.

  The seed is bounded to a trailing `@backfill_window_days` window and carries
  the per-project ranges, the 1 GiB ceiling and the halving-by-date retry from
  `20260818130000`. A window that is still not filled by what the seed found is
  not evaluated, which is the same answer the shared bucket gives a test case
  too young to measure.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "test_case_runs_default_branch_recent_window_per_case"
  @bucket_size 2000
  @backfill_window_days 30
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
      test_case_id UUID,
      recent_runs AggregateFunction(groupArraySorted(#{@bucket_size}), Int64)
    ) ENGINE = AggregatingMergeTree
    PARTITION BY intHash32(project_id) % 16
    ORDER BY (project_id, test_case_id)
    SETTINGS merge_max_block_size = 256
    """)

    {boundary, window_start, window_end} = backfill_bounds()

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

  defp default_branches do
    Ecto.Migrator.with_repo(Repo, fn _repo ->
      Repo.query!(
        "SELECT id, default_branch FROM projects WHERE default_branch IS NOT NULL AND default_branch <> ''"
      )
    end)
    |> case do
      {:ok, %{rows: rows}, _apps} -> Map.new(rows, fn [id, branch] -> {id, branch} end)
    end
  end

  # The aggregate keeps the newest entries whatever order they arrive in, so
  # partitions are walked oldest-first here rather than newest-first: the state
  # is bounded by the bucket, not by what it saw first.
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
        ORDER BY partition
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

  # Splitting is by `inserted_at` rather than by date-of-run because that is the
  # column the partition filter already uses here. Halves are disjoint, and
  # `groupArraySorted` merges partial states into the same bounded result
  # whichever order the halves are written in.
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

  defp describe(project_id, from_date, to_date),
    do: "project #{project_id} over #{from_date}..#{to_date}"

  defp insert_range(partition, project_id, branch, from_date, to_date, boundary) do
    IngestRepo.query!(
      """
      INSERT INTO #{@table} (project_id, test_case_id, recent_runs)
      SELECT
        project_id,
        assumeNotNull(test_case_id) AS test_case_id,
        groupArraySortedState(#{@bucket_size})(
          -toUnixTimestamp64Micro(ran_at) * 4 + toUInt8(is_flaky) * 2 + toUInt8(status = 'success')
        ) AS recent_runs
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND inserted_at < {boundary:DateTime64(6)}
        AND project_id = {project_id:Int64}
        AND toDate(inserted_at) >= {from_date:Date}
        AND toDate(inserted_at) <= {to_date:Date}
        AND git_branch = {branch:String}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, test_case_id
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

  defp year_month(%Date{year: year, month: month}), do: year * 100 + month
end
