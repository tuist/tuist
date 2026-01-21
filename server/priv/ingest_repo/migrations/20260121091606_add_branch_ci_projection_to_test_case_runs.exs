defmodule Tuist.IngestRepo.Migrations.AddBranchCiProjectionToTestCaseRuns do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_branch_ci (
      SELECT git_branch, is_ci, ran_at, test_case_id
      ORDER BY git_branch, is_ci, ran_at, test_case_id
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_branch_ci"
  end
end
