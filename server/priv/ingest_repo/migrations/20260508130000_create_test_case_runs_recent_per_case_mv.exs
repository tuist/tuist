defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsRecentPerCaseMv do
  @moduledoc """
  Per-test-case rolling-window aggregate of `test_case_runs`.

  The flaky-tests automation engine's "rolling window" mode evaluates the last
  N runs per `(project_id, test_case_id)` ordered by `ran_at`. Reading raw
  `test_case_runs` for that pattern scans every run in the project's lookback
  range — measured at 200M+ rows for 30 days on busy projects, with no primary
  key prefix that fits "last N per test case per project."

  This MV maintains a `groupArrayLast(N)` aggregate of `(ran_at, is_flaky)`
  tuples per test case, capped at 1000 entries to match the changeset's
  `rolling_window_size` cap. A later migration adds a parallel
  `(ran_at, status == 'success')` aggregate for reliability-rate automations.
  A project's whole rolling-window scan becomes one row per test case —
  bounded by `active_test_cases`, regardless of run volume.

  Ordering caveat: `groupArrayLast(N)` keeps the last N values by
  *aggregation order*, not by `ran_at`. The backfill query orders source
  rows by the table's primary key via `optimize_aggregation_in_order`, so
  the initial state is exactly the last N runs by `ran_at` per
  `(project_id, test_case_id)`. For live inserts the MV trigger sees each
  INSERT block in arrival order — typically a single CI run with one row
  per test case, so per-group ordering is trivially preserved — and the
  state stays approximately chronological. The query layer
  `arrayReverseSort`s by `ran_at` before slicing, so even if `is_flaky`
  re-inserts of older runs leave a few older entries inside the 1000-cap
  state, the user-facing window is still "last N by `ran_at`" up to N = 1000.

  Mirrors the `test_case_run_daily_stats_per_case` pattern (explicit storage
  table + MV trigger + partition-by-partition backfill) so it survives the
  ClickHouse Cloud `TABLE_IS_READ_ONLY` race during compaction churn.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @max_window_size 1000
  # Chunk size for the backfill query: each INSERT covers this many
  # `project_id` values within a partition. Per-query memory scales with
  # the number of unique `(project_id, test_case_id)` groups it produces,
  # so a small chunk keeps the worst-case aggregation memory well below
  # ClickHouse Cloud's 18 GiB process ceiling regardless of how heavy any
  # one project's test_case_id cardinality turns out to be.
  @project_chunk_size 1
  # Throttle between chunks to give live ClickHouse traffic (background
  # merges, MV writes, automation queries) breathing room and avoid
  # piling concurrent allocations against the global memory ceiling.
  @chunk_throttle_ms 250

  def up do
    # Prior production attempts at this migration partially populated the
    # storage table before OOM'ing the backfill. Reset cleanly so the new
    # chunked backfill below produces the canonical state. The MV is also
    # dropped to keep the recreate order strict (storage, then backfill,
    # then MV).

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_recent_per_case_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_recent_per_case")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE test_case_runs_recent_per_case (
      project_id Int64,
      test_case_id UUID,
      recent_runs AggregateFunction(groupArrayLast(#{@max_window_size}), Tuple(DateTime64(6), UInt8))
    ) ENGINE = AggregatingMergeTree
    ORDER BY (project_id, test_case_id)
    """)

    backfill_by_partition()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_recent_per_case_mv
    TO test_case_runs_recent_per_case
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArrayLastState(#{@max_window_size})((ran_at, toUInt8(is_flaky))) AS recent_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, test_case_id
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_recent_per_case_mv")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_recent_per_case")
  end

  defp backfill_by_partition do
    {:ok, %{rows: partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
        ORDER BY partition
        """,
        %{table: "test_case_runs"}
      )

    for [partition] <- partitions do
      partition_int = String.to_integer(partition)
      project_ids = project_ids_for_partition(partition_int)

      Logger.info(
        "Backfilling partition #{partition} into test_case_runs_recent_per_case " <>
          "(#{length(project_ids)} projects in #{div(length(project_ids) + @project_chunk_size - 1, @project_chunk_size)} chunk(s))"
      )

      project_ids
      |> Enum.chunk_every(@project_chunk_size)
      |> Enum.with_index(1)
      |> Enum.each(fn {chunk, idx} ->
        retry_on_transient_failure(fn ->
          backfill_chunk(partition_int, chunk, idx)
        end)

        Process.sleep(@chunk_throttle_ms)
      end)
    end
  end

  defp project_ids_for_partition(partition) do
    # `project_id` is the leading column of `test_case_runs`' primary key,
    # so `SELECT DISTINCT project_id` is a cheap PK-prefix scan: it does
    # not materialize a hash table of all rows.
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT project_id
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        ORDER BY project_id
        """,
        %{partition: partition},
        timeout: 600_000
      )

    Enum.map(rows, fn [project_id] -> project_id end)
  end

  # `optimize_aggregation_in_order = 1` plus the matching primary key
  # `(project_id, test_case_id, ran_at, id)` makes the aggregator see
  # rows in `ran_at` order within each `(project_id, test_case_id)`
  # group, so `groupArrayLast(N)` captures the actual last N runs by
  # `ran_at`. `max_threads = 1` forces a single ordered read so the
  # aggregator emits group states as soon as the next group key arrives,
  # bounding memory to one in-flight state instead of per-thread hash
  # tables.
  #
  # The `project_id IN (...)` chunking caps the size of the result the
  # query has to produce regardless of how many unique test_case_ids the
  # selected projects accumulate.
  #
  # `max_memory_usage = 12 GiB` is the budget per backfill INSERT. The
  # ClickHouse server itself has no `max_memory_usage` set
  # (verified via `system.settings`), so this is purely a self-imposed
  # ceiling. Prior attempts at 4 GiB OOM'd at ~3.74 GiB on the heaviest
  # `(partition, chunk-of-5)` for partition 202602; the dominant cost
  # is not the chunk size but `groupArrayLast(1000)`'s per-state
  # capacity-preallocation, which barely changes between chunks of 5
  # and chunks of 20. 12 GiB gives ~3× headroom over the observed peak
  # while leaving ~6 GiB free under the cluster's 18 GiB process
  # ceiling for live traffic during the brief (~6 s) burst per chunk.
  defp backfill_chunk(partition, project_ids, idx) do
    Logger.debug(
      "Backfilling chunk #{idx} of partition #{partition} " <>
        "(#{length(project_ids)} projects: #{Enum.at(project_ids, 0)}..#{List.last(project_ids)})"
    )

    IngestRepo.query!(
      """
      INSERT INTO test_case_runs_recent_per_case
      SELECT
        project_id,
        assumeNotNull(test_case_id) AS test_case_id,
        groupArrayLastState(#{@max_window_size})((ran_at, toUInt8(is_flaky))) AS recent_runs
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND project_id IN {project_ids:Array(Int64)}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, test_case_id
      SETTINGS
        optimize_aggregation_in_order = 1,
        max_threads = 1,
        max_memory_usage = 12000000000,
        max_bytes_before_external_group_by = 5000000000
      """,
      %{partition: partition, project_ids: project_ids},
      timeout: 1_200_000
    )
  end

  defp retry_on_transient_failure(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      message = to_string(e.message)

      transient? =
        String.contains?(message, "TABLE_IS_READ_ONLY") or
          String.contains?(message, "MEMORY_LIMIT_EXCEEDED")

      if attempts > 1 and transient? do
        Logger.warning(
          "ClickHouse returned a transient error (#{String.slice(message, 0, 80)}...); " <>
            "retrying in 5s (#{attempts - 1} attempts left)"
        )

        Process.sleep(:timer.seconds(5))
        retry_on_transient_failure(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
