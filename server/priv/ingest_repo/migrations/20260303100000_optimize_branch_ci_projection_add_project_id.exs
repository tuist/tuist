defmodule Tuist.IngestRepo.Migrations.OptimizeBranchCiProjectionAddProjectId do
  @moduledoc """
  Recreates `proj_by_branch_ci` with `project_id` as the first column in the
  ORDER BY key.

  The existing projection uses ORDER BY (git_branch, is_ci, ran_at, test_case_id)
  but the `get_test_case_ids_with_ci_runs_on_branch` query filters by
  `project_id` first:

      SELECT DISTINCT test_case_id
      FROM test_case_runs
      WHERE project_id = ?
        AND git_branch = ?
        AND is_ci = 1
        AND ran_at >= ?

  Without `project_id` in the sort key, ClickHouse scans all rows matching the
  branch across ALL projects (~8.5M rows read on average). Adding `project_id`
  as the first sort key column lets ClickHouse skip directly to the target
  project's data before narrowing by branch, is_ci, and ran_at.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_branch_ci SETTINGS alter_sync = 2"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION IF NOT EXISTS proj_by_branch_ci (
      SELECT project_id, git_branch, is_ci, ran_at, test_case_id
      ORDER BY project_id, git_branch, is_ci, ran_at, test_case_id
    )
    SETTINGS alter_sync = 2
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_branch_ci SETTINGS alter_sync = 2"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION IF NOT EXISTS proj_by_branch_ci (
      SELECT git_branch, is_ci, ran_at, test_case_id
      ORDER BY git_branch, is_ci, ran_at, test_case_id
    )
    SETTINGS alter_sync = 2
    """
  end
end
