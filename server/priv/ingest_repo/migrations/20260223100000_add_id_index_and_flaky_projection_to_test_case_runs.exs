defmodule Tuist.IngestRepo.Migrations.AddIdIndexAndFlakyProjectionToTestCaseRuns do
  @moduledoc """
  Adds a bloom filter index on `id` and a projection for flaky test case queries
  to optimize slow queries on the test_case_runs table.

  The bloom filter index on `id` helps queries like `WHERE id IN (...)` avoid
  full table scans (the ordering key starts with test_run_id, not id).

  The projection `proj_by_project_flaky` optimizes the flaky test cases page
  query which filters by `project_id` and `is_flaky` and groups by `test_case_id`.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_case_runs ADD INDEX idx_id (id) TYPE bloom_filter GRANULARITY 4")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_project_flaky (
      SELECT id, project_id, is_flaky, test_case_id, test_run_id, inserted_at
      ORDER BY project_id, is_flaky, test_case_id, inserted_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_flaky"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP INDEX IF EXISTS idx_id"
  end
end
