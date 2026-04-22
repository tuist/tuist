defmodule Tuist.IngestRepo.Migrations.AddProjectFilterProjectionToTestModuleAndSuiteRuns do
  @moduledoc """
  Adds `proj_by_project_is_ci_branch_ran_at` projections on `test_module_runs`
  and `test_suite_runs`, ordered by `(project_id, is_ci, git_branch, ran_at)`.

  This supports the timing query in `Tuist.Shards.fetch_timing_data/2`, which
  aggregates historical durations for a given project's default-branch CI
  runs. Without a projection the base table is sorted by
  `(test_run_id, test_module_run_id, id)`, so the query would fall back to a
  full scan of all rows.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # ReplacingMergeTree rejects ADD PROJECTION unless the table opts into
    # rebuilding projections when the merge engine deduplicates rows.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_module_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'rebuild'
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'rebuild'
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_module_runs
    ADD PROJECTION proj_by_project_is_ci_branch_ran_at (
      SELECT *
      ORDER BY project_id, is_ci, git_branch, ran_at
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_module_runs
    MATERIALIZE PROJECTION proj_by_project_is_ci_branch_ran_at
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    ADD PROJECTION proj_by_project_is_ci_branch_ran_at (
      SELECT *
      ORDER BY project_id, is_ci, git_branch, ran_at
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    MATERIALIZE PROJECTION proj_by_project_is_ci_branch_ran_at
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_module_runs
    DROP PROJECTION IF EXISTS proj_by_project_is_ci_branch_ran_at
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    DROP PROJECTION IF EXISTS proj_by_project_is_ci_branch_ran_at
    """
  end
end
