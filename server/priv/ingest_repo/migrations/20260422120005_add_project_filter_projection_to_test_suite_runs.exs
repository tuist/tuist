defmodule Tuist.IngestRepo.Migrations.AddProjectFilterProjectionToTestSuiteRuns do
  @moduledoc """
  Adds the `proj_by_project_is_ci_branch_ran_at` projection definition to
  `test_suite_runs`. Mirrors the `test_module_runs` migration; materialization
  is done in the follow-up migration.
  """
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'rebuild'
    """

    # IF NOT EXISTS so re-runs are no-ops (CH DDL isn't transactional; see
    # 20260410120000 for context).
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    ADD PROJECTION IF NOT EXISTS proj_by_project_is_ci_branch_ran_at (
      SELECT *
      ORDER BY project_id, is_ci, git_branch, ran_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    DROP PROJECTION IF EXISTS proj_by_project_is_ci_branch_ran_at
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'throw'
    """
  end
end
