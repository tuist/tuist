defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsByCommitMv do
  @moduledoc """
  Creates a lightweight MV to optimize the cross-run flakiness lookup used by
  `Tuist.Tests.get_existing_ci_runs_for_commit/3`:

      SELECT * FROM test_case_runs
      WHERE project_id = ? AND git_commit_sha = ? AND is_ci = 1
        AND status IN ('success', 'failure')

  The main table ORDER BY `(project_id, test_case_id, ran_at, id)` can binary
  search on `project_id` but then has to scan the full per-project range
  because `git_commit_sha` is not part of the sort key. The bloom filter index
  on `git_commit_sha` only prunes whole granules and in production this still
  reads 4-6M rows per execution (p90 ~4.2s). Projections cannot be used
  because the main table is a `ReplacingMergeTree` (ClickHouse issue #46968).

  This MV stores only the columns needed for the lookup (id, test_case_id,
  status) plus the filter columns, ordered by
  `(project_id, git_commit_sha, is_ci, status, id)`. A typical lookup
  narrows on the first three prefix columns and reads a small range. The
  caller re-fetches full rows from the main table by `id` (leveraging the
  `idx_id` bloom filter) only for the small subset of test cases that turned
  out to be cross-run flaky.

  Uses the explicit TO-table pattern so backfills target the storage table
  directly and avoid the ZooKeeper "TABLE_IS_READ_ONLY" race on ClickHouse
  Cloud (same pattern as `flaky_test_case_runs_mv`).
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(project_id git_commit_sha is_ci status id test_case_id inserted_at)

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_commit_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_commit")

    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_by_commit (
      project_id Int64,
      git_commit_sha String,
      is_ci Bool DEFAULT false,
      status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
      id UUID,
      test_case_id Nullable(UUID),
      inserted_at DateTime64(6)
    ) ENGINE = ReplacingMergeTree(inserted_at)
    ORDER BY (project_id, git_commit_sha, is_ci, status, id)
    """)

    backfill_by_partition()

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_commit_mv
    TO test_case_runs_by_commit
    AS SELECT
      project_id,
      git_commit_sha,
      is_ci,
      status,
      id,
      test_case_id,
      inserted_at
    FROM test_case_runs
    """)
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_commit_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_commit")
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
      Logger.info("Backfilling partition #{partition} into test_case_runs_by_commit")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO test_case_runs_by_commit (#{Enum.join(@columns, ", ")})
          SELECT #{Enum.join(@columns, ", ")}
          FROM test_case_runs
          WHERE toYYYYMM(inserted_at) = {partition:UInt32}
          """,
          %{partition: String.to_integer(partition)},
          timeout: 1_200_000
        )
      end)
    end
  end

  defp retry_on_shutting_down(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      if attempts > 1 and String.contains?(to_string(e.message), "TABLE_IS_READ_ONLY") do
        Logger.warning("Table is shutting down, retrying in 5s (#{attempts - 1} attempts left)")
        Process.sleep(:timer.seconds(5))
        retry_on_shutting_down(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
