defmodule Tuist.IngestRepo.Migrations.RecreateFlakyTestCaseRunsMv do
  @moduledoc """
  Recreates `flaky_test_case_runs` with additional columns needed for the
  flaky test cases listing page, using the explicit TO-table pattern.

  Previously the MV only stored (test_case_id, inserted_at) for the
  `clear_stale_flaky_flags` query. The flaky listing page needs
  project_id, test_run_id, ran_at, and is_ci to aggregate flaky stats
  with time-range and environment filters — without scanning the full
  test_case_runs table (1.7M rows, p50 = 2.6s).

  New ORDER BY (project_id, ran_at, test_case_id) enables prefix scan
  on project_id + range scan on ran_at for the listing page.
  The clear_stale query loses its prefix match on inserted_at, but the
  MV only contains flaky rows so the full scan is negligible.

  Uses an explicit storage table (`flaky_test_case_runs`) with the MV
  trigger named `flaky_test_case_runs_mv`. Backfills go directly into
  the storage table, avoiding the ZooKeeper "table is shutting down"
  race on ClickHouse Cloud.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(project_id test_case_id test_run_id inserted_at ran_at is_ci)

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS flaky_test_case_runs")

    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS flaky_test_case_runs (
      project_id Int64,
      test_case_id UUID,
      test_run_id UUID,
      inserted_at DateTime64(6),
      ran_at DateTime64(6),
      is_ci Bool
    ) ENGINE = MergeTree
    ORDER BY (project_id, ran_at, test_case_id)
    """)

    backfill_by_partition()

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS flaky_test_case_runs_mv
    TO flaky_test_case_runs
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      test_run_id,
      inserted_at,
      ran_at,
      is_ci
    FROM test_case_runs
    WHERE is_flaky = 1 AND test_case_id IS NOT NULL
    """)
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS flaky_test_case_runs_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS flaky_test_case_runs")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS flaky_test_case_runs
    ENGINE = MergeTree
    ORDER BY (inserted_at, test_case_id)
    POPULATE
    AS SELECT
      assumeNotNull(test_case_id) AS test_case_id,
      inserted_at
    FROM test_case_runs
    WHERE is_flaky = 1 AND test_case_id IS NOT NULL
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
      Logger.info("Backfilling partition #{partition} into flaky_test_case_runs")

      IngestRepo.query!(
        """
        INSERT INTO flaky_test_case_runs (#{Enum.join(@columns, ", ")})
        SELECT
          project_id,
          assumeNotNull(test_case_id),
          test_run_id,
          inserted_at,
          ran_at,
          is_ci
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32} AND is_flaky = 1 AND test_case_id IS NOT NULL
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
