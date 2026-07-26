defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunProjects do
  @moduledoc """
  Creates an identifier-keyed lookup for resolving a test case run's project.

  The source `test_case_runs` table is ordered by
  `(project_id, test_case_id, ran_at, id)`, so looking up random run
  identifiers reads most of that table even with its bloom filter. This slim
  table is ordered by `id`, which lets ClickHouse seek directly to the small
  set of granules needed by retention and other identifier-based lookups.

  The materialized view is created before the partition-wise backfill. New
  writes are therefore captured while historical partitions are copied, and
  `ReplacingMergeTree(inserted_at)` collapses overlap between the two paths.
  """

  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "test_case_run_projects"
  @view "test_case_run_projects_mv"

  def up do
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS #{@table} (
      id UUID,
      project_id Int64,
      inserted_at DateTime64(6)
    ) ENGINE = ReplacingMergeTree(inserted_at)
    ORDER BY id
    """)

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS #{@view}
    TO #{@table}
    AS SELECT id, project_id, inserted_at
    FROM test_case_runs
    """)

    backfill_by_partition()
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS #{@view}")
    IngestRepo.query!("DROP TABLE IF EXISTS #{@table}")
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
      Logger.info("Backfilling partition #{partition} into #{@table}")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO #{@table} (id, project_id, inserted_at)
          SELECT id, project_id, inserted_at
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
    error in Ch.Error ->
      if attempts > 1 and String.contains?(to_string(error.message), "TABLE_IS_READ_ONLY") do
        Logger.warning("Table is shutting down, retrying in 5s (#{attempts - 1} attempts left)")
        Process.sleep(:timer.seconds(5))
        retry_on_shutting_down(fun, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
