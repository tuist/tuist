defmodule Tuist.IngestRepo.Migrations.AddProjectAnalyticsProjectionToTestCaseRuns do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_project_analytics (
      SELECT
        id,
        project_id,
        inserted_at,
        is_ci,
        status,
        duration
      ORDER BY project_id, inserted_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_analytics"
  end
end
