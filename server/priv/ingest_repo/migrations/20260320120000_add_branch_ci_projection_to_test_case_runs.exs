defmodule Tuist.IngestRepo.Migrations.AddBranchCiProjectionToTestCaseRuns do
  @moduledoc """
  Adds a projection to `test_case_runs` optimized for the
  `get_test_case_ids_with_ci_runs_on_branch` query pattern:

    SELECT DISTINCT test_case_id FROM test_case_runs
    WHERE project_id = ? AND git_branch = ? AND is_ci = ? AND ran_at >= ?

  The main table ORDER BY `(project_id, test_case_id, ran_at, id)` can only
  binary search on `project_id` for this query since `test_case_id` (2nd key)
  is not filtered. This projection reorders data by
  `(project_id, git_branch, is_ci, ran_at)` enabling a full prefix match.

  Stale rows from ReplacingMergeTree are acceptable here because the query
  uses DISTINCT — duplicates are collapsed in the result.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("""
    ALTER TABLE test_case_runs
    ADD PROJECTION IF NOT EXISTS proj_by_branch_ci (
      SELECT test_case_id, project_id, git_branch, is_ci, ran_at
      ORDER BY (project_id, git_branch, is_ci, ran_at)
    )
    """)
  end

  def down do
    IngestRepo.query!("ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_branch_ci")
  end
end
