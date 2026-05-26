defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsByProjectMv do
  @moduledoc """
  Slim materialized view ordered by `(project_id, ran_at, id)` to support
  efficient listing of test case runs scoped to a project, sorted by `ran_at`.

  The main `test_case_runs` table's primary key is
  `(project_id, test_case_id, ran_at, id)`. Queries that filter by
  `project_id` alone and sort by `ran_at DESC` cannot stream rows in `ran_at`
  order — `ran_at` is only sorted within each `test_case_id`. ClickHouse
  therefore reads every row for the project before applying the LIMIT.
  On busy projects this scans 100M+ rows and times out at 15s.

  Projections on the parent table cannot be used to fix this:
  `test_case_runs` is a ReplacingMergeTree and ClickHouse projections do not
  work with it (issue #46968), which is why the historical
  `proj_test_case_runs_by_project_ran_at` was dropped in
  `20260319120000_reorder_test_case_runs.exs`.

  Uses the explicit TO-table pattern with `ReplacingMergeTree(inserted_at)` so
  re-inserts in `test_case_runs` (e.g. flaky-flag updates) deduplicate here
  too. Query reads use the `FINAL` hint to collapse pending duplicates,
  matching `test_case_runs_by_test_run`.

  Full rows are fetched from the main table for the page-sized result set,
  mirroring the pattern used by `test_case_runs_by_test_run` and
  `test_case_runs_by_shard_id`.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(id project_id ran_at inserted_at name status is_flaky is_new is_ci is_quarantined duration test_case_id account_id scheme git_branch)

  def up do
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_by_project (
      id UUID,
      project_id Int64,
      ran_at DateTime64(6),
      inserted_at DateTime64(6),
      name String,
      status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
      is_flaky Bool DEFAULT false,
      is_new Bool DEFAULT false,
      is_ci Bool DEFAULT false,
      is_quarantined Bool DEFAULT false,
      duration Int32,
      test_case_id Nullable(UUID),
      account_id Nullable(Int64),
      scheme String DEFAULT '',
      git_branch String DEFAULT ''
    ) ENGINE = ReplacingMergeTree(inserted_at)
    ORDER BY (project_id, ran_at, id)
    """)

    backfill_by_partition()

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_project_mv
    TO test_case_runs_by_project
    AS SELECT #{Enum.join(@columns, ", ")}
    FROM test_case_runs
    """)
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_project_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_project")
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
      Logger.info("Backfilling partition #{partition} into test_case_runs_by_project")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO test_case_runs_by_project (#{Enum.join(@columns, ", ")})
          SELECT #{Enum.join(@columns, ", ")}
          FROM test_case_runs FINAL
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
