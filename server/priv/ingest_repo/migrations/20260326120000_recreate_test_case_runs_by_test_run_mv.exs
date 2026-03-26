defmodule Tuist.IngestRepo.Migrations.RecreateTestCaseRunsByTestRunMv do
  @moduledoc """
  Recreates `test_case_runs_by_test_run` with additional columns needed for
  filtering, sorting, and pagination directly on the MV.

  Previously, the MV only had 6 columns (id, test_run_id, status, is_flaky,
  duration, inserted_at) and was used solely for ID lookups. All filtering
  (status, is_flaky) and sorting (ran_at) happened on the main table, reading
  ~4.3M rows on average.

  By adding ran_at, name, is_new, and project_id, the Elixir code can run
  Flop queries entirely on the MV (filter + sort + paginate), then fetch full
  rows from the main table only for the ~20 result IDs.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(id test_run_id status is_flaky is_new duration inserted_at ran_at name project_id)

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run SYNC")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run
    ENGINE = MergeTree
    ORDER BY (test_run_id, ran_at, id)
    AS SELECT #{Enum.join(@columns, ", ")}
    FROM test_case_runs
    """)

    IngestRepo.query!("SYSTEM SYNC DATABASE REPLICA")

    backfill_by_partition()
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run SYNC")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run
    ENGINE = MergeTree
    ORDER BY (test_run_id, id)
    AS SELECT id, test_run_id, status, is_flaky, duration, inserted_at
    FROM test_case_runs
    """)
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
      Logger.info("Backfilling partition #{partition} into test_case_runs_by_test_run")

      IngestRepo.query!(
        """
        INSERT INTO test_case_runs_by_test_run (#{Enum.join(@columns, ", ")})
        SELECT #{Enum.join(@columns, ", ")}
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
