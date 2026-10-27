defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsByTestRunMv do
  @moduledoc """
  Creates a slim materialized view `test_case_runs_by_test_run` ordered by
  `(test_run_id, id)` to efficiently serve queries that filter test case
  runs by test_run_id — metrics aggregation, failure counts, and ID lookups
  for paginated listings.

  After the primary key of `test_case_runs` was reordered to
  `(project_id, test_case_id, ran_at, id)`, queries filtering only by
  `test_run_id` regressed to full scans (~24-30 M rows read).
  This MV restores O(log N) lookups for those queries.

  Only 6 columns are stored: id, test_run_id, status, is_flaky, duration,
  inserted_at.

  Historical data is backfilled partition-by-partition to avoid memory
  pressure on large tables (300 M+ rows).
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run
    ENGINE = MergeTree
    ORDER BY (test_run_id, id)
    AS SELECT id, test_run_id, status, is_flaky, duration, inserted_at
    FROM test_case_runs
    """)

    backfill_by_partition()
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run")
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
        INSERT INTO test_case_runs_by_test_run (id, test_run_id, status, is_flaky, duration, inserted_at)
        SELECT id, test_run_id, status, is_flaky, duration, inserted_at
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
