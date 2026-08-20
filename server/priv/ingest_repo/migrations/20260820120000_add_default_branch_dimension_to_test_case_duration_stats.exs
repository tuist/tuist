defmodule Tuist.IngestRepo.Migrations.AddDefaultBranchDimensionToTestCaseDurationStats do
  @moduledoc """
  Splits the per-test-case duration aggregate by whether a run happened on the
  project's default branch.

  The listing's duration figures mixed runs from every branch. One production
  test case reported a 10-minute average against a 2 ms default-branch median:
  five of its eight runs sat on one feature branch and the largest was 78
  minutes, which is a paused debugger rather than a slow test. No calendar
  window or last-N average separates that from real slowness, because the
  outlier is genuinely a run that happened. The branch is what the outliers
  have in common.

  This rebuilds the table `20260818130000` created, with `is_default_branch` in
  the sort key, and otherwise keeps that migration's shape: the bounded seed
  window, the per-project ranges, the memory ceiling and the halving retry are
  all load-bearing and are not re-derived here.

  ## Why a boolean and not the branch name

  Carrying `git_branch` would also answer "how long does this take on my
  branch", so it is worth recording that it was rejected on cost.

  Keying a per-day aggregate on the name multiplies its rows by the branches a
  test case touched that day, which on CI is one row per pull request that ran
  it. Measured on production over a trailing window, comparing
  `uniqExact((test_case_id, date, is_ci))` against the same tuple with
  `git_branch` added:

      project 2289    54 branches    25,095 ->    26,401 rows    1.05x
      project 5096    91 branches   116,883 ->   770,014 rows    6.59x
      project 3592    91 branches    70,995 -> 1,350,613 rows   19.02x
      project 2509   233 branches   107,317 -> 3,256,391 rows   30.34x

  The multiplier is not a property of the branch count but of how much CI runs
  per branch, so it cannot be bounded by capping branches. It is near 1 on the
  project that reported the problem and 30x on the heaviest measured, and it
  lands on quantile states, which are reservoirs rather than counters, on a
  table whose seed already carries a 1 GiB ceiling and subdivides by date to
  fit at 1x.

  The read is the sharper half. `Tuist.Tests.list_test_cases/3` merges every
  state in the window per test case, so a branch-keyed table would merge orders
  of magnitude more states per row on every page load, including the common
  case where nobody asked about branches. The boolean does the opposite:
  scoping to the default branch narrows the scan below what the listing reads
  today.

  The cost is that an arbitrary-branch picker becomes another migration rather
  than a query change. The request this serves was explicitly satisfied by a
  default-branch-only view.

  ## Why the table is rebuilt rather than altered

  `is_default_branch` has to be in the sort key for the dashboard control to
  narrow the read rather than filter after it, and a sort key cannot be
  extended in place without lying about the rows already written: every
  existing row would claim `is_default_branch = false` while holding runs from
  every branch. That is the grain corruption `20260818130000` cites for not
  adding `is_ci` to `test_case_run_daily_stats_per_case`.

  Rebuilding is cheap here because that migration already drops and recreates
  on every run, and already seeds a trailing window rather than all history.

  ## Where the default branch comes from

  It lives in Postgres, and a materialized view cannot reach across to resolve
  it. The two halves solve that differently, on purpose:

    * The view reads `test_case_runs.is_default_branch`, denormalized at
      ingestion by `20260818140000`, which shipped in an earlier release. That
      ordering is the point: managed migrations complete before workload pods
      roll, so a view keyed on a column introduced in its own release would
      record every run written during the rollout as off-default and never
      revisit it.
    * The seed compares `git_branch` against the branch name read from
      Postgres. The ranges are already one project each, so there is exactly
      one name to compare against and it travels as a query parameter.

  That is what keeps this off the fact table. Backfilling `is_default_branch`
  across historical `test_case_runs` rows would be a multi-billion-row rewrite
  to produce a value the seed computes from a string comparison it is already
  positioned to make.

  A project that renames its default branch has runs written before the rename
  classified against the old name on the fact table. Nothing corrects them: the
  listing reads this table over a trailing window only, so a rename heals once
  the window has moved past it.

  A project that exists in ClickHouse but no longer in Postgres has no name to
  compare against, so none of its runs are marked as being on the default
  branch. They still aggregate under "any branch", which is the only honest
  answer once the project that defined the branch is gone.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.Repo

  import Ecto.Query

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @backfill_window_days 16
  @attempt_throttle_ms 250
  @range_attempts 2
  @max_memory_usage 1_073_741_824
  @max_bytes_before_external_group_by 268_435_456

  def up do
    default_branches = default_branches_by_project_id()

    drop_objects()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE test_case_duration_daily_stats_per_case (
      project_id Int64,
      date Date,
      test_case_id UUID,
      is_ci Bool,
      is_default_branch Bool,
      run_count AggregateFunction(uniqExact, UUID),
      avg_duration AggregateFunction(avg, Int32),
      p50_duration AggregateFunction(quantile(0.5), Int32),
      p90_duration AggregateFunction(quantile(0.9), Int32),
      p99_duration AggregateFunction(quantile(0.99), Int32)
    ) ENGINE = AggregatingMergeTree
    PARTITION BY toYYYYMM(date)
    ORDER BY (project_id, test_case_id, date, is_ci, is_default_branch)
    """)

    # The bounds are read from ClickHouse, not from the Elixir node, so they are
    # on the same clock as the `inserted_at` values they are compared against.
    {boundary, window_start, window_end} = backfill_bounds()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW test_case_duration_daily_stats_per_case_mv
    TO test_case_duration_daily_stats_per_case
    AS SELECT
      project_id,
      toDate(ran_at) AS date,
      assumeNotNull(test_case_id) AS test_case_id,
      is_ci,
      is_default_branch,
      uniqExactState(id) AS run_count,
      avgState(duration) AS avg_duration,
      quantileState(0.5)(duration) AS p50_duration,
      quantileState(0.9)(duration) AS p90_duration,
      quantileState(0.99)(duration) AS p99_duration
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, date, test_case_id, is_ci, is_default_branch
    """)

    backfill(boundary, window_start, window_end, default_branches)
  end

  def down do
    drop_objects()
  end

  # One row per project, read once and held for the pass. The PostgreSQL repo is
  # not started during ClickHouse migrations and Ecto discards the task each
  # migration runs in, so it is started through `Ecto.Migrator.with_repo/2`
  # rather than linked to that task, and only for as long as this read takes.
  defp default_branches_by_project_id do
    {:ok, default_branches, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo ->
        "projects"
        |> from(select: [:id, :default_branch])
        |> Repo.all(timeout: :infinity, log: false)
        |> Map.new(fn %{id: id, default_branch: default_branch} -> {id, default_branch} end)
      end)

    Logger.info("Read default branches for #{map_size(default_branches)} projects")
    default_branches
  end

  defp drop_objects do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_duration_daily_stats_per_case_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_duration_daily_stats_per_case")
  end

  # Every run inserted from here on is picked up by the materialized view, so
  # the backfill covers exactly what came before and the two never overlap.
  #
  # The view is created after this instant is read, so runs inserted in the
  # moment between the two are seen by neither. That is deliberate: the reverse
  # order would have them seen by both, and a run counted twice can push a test
  # case over the minimum-sample floor, while a run missed for a few
  # milliseconds cannot.
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

    Logger.info(
      "Backfilling test_case_duration_daily_stats_per_case over " <>
        "#{window_start}..#{window_end}, up to #{boundary}"
    )

    {boundary, window_start, window_end}
  end

  # Newest partition first. The listing reads the most recent days hardest, so
  # the feature is at its most complete as early as possible; an older
  # partition that needs several subdivisions delays nothing user-visible.
  #
  # A run whose `ran_at` falls in the window cannot have been ingested before
  # it, so partitions older than the window's own month hold nothing the window
  # admits.
  defp backfill(boundary, window_start, window_end, default_branches) do
    for partition <- partitions_since(window_start) do
      project_ids = project_ids_for_partition(partition, window_start)

      Logger.info(
        "Backfilling partition #{partition} into test_case_duration_daily_stats_per_case " <>
          "(#{length(project_ids)} projects)"
      )

      Enum.each(project_ids, fn project_id ->
        default_branch = Map.get(default_branches, project_id) || ""
        backfill_range(partition, project_id, window_start, window_end, boundary, default_branch)
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
          AND toDate(ran_at) >= {window_start:Date}
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
         from_date,
         to_date,
         boundary,
         default_branch,
         attempts \\ @range_attempts
       ) do
    # Ahead of every attempt rather than between projects: the halves a split
    # produces are fired at a replica that has just refused the range they came
    # from, which is when leaving it room matters most.
    Process.sleep(@attempt_throttle_ms)

    insert_range(partition, project_id, from_date, to_date, boundary, default_branch)
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
            from_date,
            to_date,
            boundary,
            default_branch,
            attempts - 1
          )

        Date.compare(from_date, to_date) == :lt ->
          midpoint = Date.add(from_date, div(Date.diff(to_date, from_date), 2))

          Logger.warning(
            "ClickHouse could not fit #{describe(project_id, from_date, to_date)}; " <>
              "splitting at #{midpoint}"
          )

          backfill_range(partition, project_id, from_date, midpoint, boundary, default_branch)

          backfill_range(
            partition,
            project_id,
            Date.add(midpoint, 1),
            to_date,
            boundary,
            default_branch
          )

        true ->
          Logger.warning(
            "ClickHouse could not fit #{describe(project_id, from_date, to_date)}, " <>
              "the smallest range there is; skipping it"
          )
      end
  end

  # `toYYYYMM(inserted_at)` selects the source partition while `date` groups on
  # `ran_at`. Runs whose execution and ingestion fall on opposite sides of a
  # month boundary are therefore written from the partition that holds them,
  # into the destination partition their `ran_at` belongs to, so no run is
  # visited twice and none is skipped.
  defp insert_range(partition, project_id, from_date, to_date, boundary, default_branch) do
    IngestRepo.query!(
      """
      INSERT INTO test_case_duration_daily_stats_per_case
        (project_id, date, test_case_id, is_ci, is_default_branch, run_count,
         avg_duration, p50_duration, p90_duration, p99_duration)
      SELECT
        project_id,
        toDate(ran_at) AS date,
        assumeNotNull(test_case_id) AS test_case_id,
        is_ci,
        (({default_branch:String} != '') AND (git_branch = {default_branch:String})) AS is_default_branch,
        uniqExactState(id) AS run_count,
        avgState(duration) AS avg_duration,
        quantileState(0.5)(duration) AS p50_duration,
        quantileState(0.9)(duration) AS p90_duration,
        quantileState(0.99)(duration) AS p99_duration
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND inserted_at < {boundary:DateTime64(6)}
        AND project_id = {project_id:Int64}
        AND toDate(ran_at) >= {from_date:Date}
        AND toDate(ran_at) <= {to_date:Date}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, date, test_case_id, is_ci, is_default_branch
      SETTINGS
        optimize_aggregation_in_order = 1,
        max_threads = 1,
        max_memory_usage = #{@max_memory_usage},
        max_bytes_before_external_group_by = #{@max_bytes_before_external_group_by}
      """,
      %{
        partition: partition,
        project_id: project_id,
        from_date: from_date,
        to_date: to_date,
        boundary: boundary,
        default_branch: default_branch
      },
      timeout: 1_200_000
    )
  end

  # `TABLE_IS_READ_ONLY` is the replica briefly refusing writes rather than a
  # range that is too large, so it is worth the same retry and is harmless to
  # subdivide when the retry does not clear it.
  defp overrun?(%Ch.Error{} = error) do
    message = to_string(error.message)

    String.contains?(message, "MEMORY_LIMIT_EXCEEDED") or
      String.contains?(message, "TABLE_IS_READ_ONLY")
  end

  defp describe(project_id, from_date, to_date) do
    "project #{project_id} over #{from_date}..#{to_date}"
  end

  defp year_month(%Date{year: year, month: month}), do: year * 100 + month
end
