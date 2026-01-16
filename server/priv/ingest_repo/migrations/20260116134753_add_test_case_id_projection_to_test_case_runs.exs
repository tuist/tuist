defmodule Tuist.IngestRepo.Migrations.AddTestCaseIdProjectionToTestCaseRuns do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_test_case_id (
      SELECT *
      ORDER BY test_case_id, ran_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_test_case_id"
  end
end
