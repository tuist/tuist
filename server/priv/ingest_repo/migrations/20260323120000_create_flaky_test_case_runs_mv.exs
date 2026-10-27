defmodule Tuist.IngestRepo.Migrations.CreateFlakyTestCaseRunsMv do
  @moduledoc """
  Creates a lightweight MV to optimize the `clear_stale_flaky_flags` query:

    SELECT test_case_id FROM test_case_runs
    WHERE is_flaky = true AND inserted_at >= ?
    GROUP BY test_case_id

  The main table ORDER BY `(project_id, test_case_id, ran_at, id)` cannot
  binary-search on `is_flaky` or `inserted_at` — resulting in a full scan
  of ~34M rows (494 MiB, 4s p50).

  This MV stores only flaky rows with ORDER BY `(inserted_at, test_case_id)`,
  enabling a prefix range scan on `inserted_at` and efficient grouping by
  `test_case_id`. Because only flaky runs are stored, the MV is very small.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
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

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS flaky_test_case_runs")
  end
end
