defmodule Tuist.IngestRepo.Migrations.AddProjectFilterProjectionToTestModuleRuns do
  @moduledoc """
  Adds the `proj_by_project_is_ci_branch_ran_at` projection definition to
  `test_module_runs`, ordered by `(project_id, is_ci, git_branch, ran_at)`.
  This supports the shard-plan timing query in
  `Tuist.Shards.fetch_timing_data/2`.

  Only adds the projection metadata; the follow-up migration materializes
  it. Split to match the pattern established by
  `20260116134753_add_test_case_id_projection_to_test_case_runs.exs` +
  `20260116134754_materialize_test_case_runs_projection.exs`.
  """
  use Ecto.Migration

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
    ALTER TABLE test_module_runs
    ADD PROJECTION proj_by_project_is_ci_branch_ran_at (
      SELECT *
      ORDER BY project_id, is_ci, git_branch, ran_at
    )
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
    ALTER TABLE test_module_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'throw'
    """
  end
end
