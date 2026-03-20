defmodule Tuist.IngestRepo.Migrations.CreateTestCaseBranchPresenceMv do
  @moduledoc """
  Creates a lightweight MV to optimize the `get_test_case_ids_with_ci_runs_on_branch`
  query pattern:

    SELECT DISTINCT test_case_id FROM test_case_runs
    WHERE project_id = ? AND git_branch = ? AND is_ci = ? AND ran_at >= ?

  The main table ORDER BY `(project_id, test_case_id, ran_at, id)` can only
  binary search on `project_id` for this query since `test_case_id` (2nd key)
  is not filtered — resulting in ~14.5M rows scanned per call.

  This MV uses MergeTree with ORDER BY `(project_id, git_branch, is_ci,
  ran_at, test_case_id)` enabling a full prefix match on the query's WHERE
  clause. The query uses DISTINCT so duplicate rows don't matter.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_branch_presence
    ENGINE = MergeTree
    ORDER BY (project_id, git_branch, is_ci, ran_at, test_case_id)
    SETTINGS allow_nullable_key = 1
    AS SELECT
      project_id,
      git_branch,
      is_ci,
      test_case_id,
      ran_at
    FROM test_case_runs
    """)
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_branch_presence")
  end
end
