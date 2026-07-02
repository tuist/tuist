defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsValidatedOnBranchMv do
  @moduledoc """
  Per-`(project, branch, test_case)` "validated on this branch" marker.

  `AlertEvaluationWorker.reject_unvalidated_test_cases/2` filters a flaky
  alert's triggered test cases down to those with at least one successful,
  non-flaky run on the project's default branch, via
  `Tests.test_case_ids_with_successful_default_branch_run/3`. That check used to
  scan raw `test_case_runs` for the whole triggered set — filtering by
  `status = 'success' AND is_flaky = false AND git_branch = <default>` and
  reading every matching run per test case, chunked 2000 ids at a time. On busy
  projects with large triggered sets this became the single most CPU-expensive
  ClickHouse query (multi-second raw-table scans reading millions of rows per
  evaluation).

  This collapses each `(project_id, git_branch, test_case_id)` that has ever had
  a successful, non-flaky run into one marker row in a ReplacingMergeTree keyed
  the same way. The validation check then becomes a bounded primary-key point
  lookup per test case instead of a raw-run scan. The MV pre-applies the
  `status = 'success' AND is_flaky = false` filter, so the read only needs
  `project_id`, `git_branch`, and the `test_case_id IN (...)` set.

  Mirrors the established explicit-storage-table + MV-trigger + partition
  backfill pattern used by the other per-case aggregates.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Throttle between partition backfills to give live ClickHouse traffic
  # (background merges, MV writes, automation queries) breathing room.
  @chunk_throttle_ms 100

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_validated_on_branch_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_validated_on_branch (
      project_id Int64,
      git_branch String,
      test_case_id UUID
    ) ENGINE = ReplacingMergeTree
    ORDER BY (project_id, git_branch, test_case_id)
    """)

    backfill_by_partition()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_validated_on_branch_mv
    TO test_case_runs_validated_on_branch
    AS SELECT
      project_id,
      git_branch,
      assumeNotNull(test_case_id) AS test_case_id
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL AND status = 'success' AND is_flaky = false
    GROUP BY project_id, git_branch, test_case_id
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_validated_on_branch_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_validated_on_branch")
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
      Logger.info("Backfilling partition #{partition} into test_case_runs_validated_on_branch")

      retry_on_transient_failure(fn -> backfill_partition(String.to_integer(partition)) end)

      Process.sleep(@chunk_throttle_ms)
    end
  end

  # `GROUP BY` collapses the partition's runs to distinct
  # `(project_id, git_branch, test_case_id)` keys before insert, so the marker
  # table stays one row per validated test case per branch rather than one per
  # run. `max_bytes_before_external_group_by` lets the group-by spill to disk,
  # bounding memory regardless of how many distinct keys a busy month holds.
  defp backfill_partition(partition) do
    IngestRepo.query!(
      """
      INSERT INTO test_case_runs_validated_on_branch (project_id, git_branch, test_case_id)
      SELECT
        project_id,
        git_branch,
        assumeNotNull(test_case_id) AS test_case_id
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND test_case_id IS NOT NULL
        AND status = 'success'
        AND is_flaky = false
      GROUP BY project_id, git_branch, test_case_id
      SETTINGS
        max_threads = 2,
        max_memory_usage = 6000000000,
        max_bytes_before_external_group_by = 3000000000
      """,
      %{partition: partition},
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

        Process.sleep(to_timeout(second: 5))
        retry_on_transient_failure(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
