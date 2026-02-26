defmodule Tuist.IngestRepo.Migrations.FixBranchCiProjectionAfterNonNullableRanAt do
  @moduledoc """
  Recreates `proj_by_branch_ci` after `ran_at` was changed to non-nullable
  in migration 20260225100001.

  `proj_by_branch_ci` uses `ran_at` in its ORDER BY but was not included in
  the 20260225100002 recreation pass (which only covered
  `proj_test_case_runs_by_project_ran_at` and `proj_by_project_flaky`).
  A projection whose ORDER BY column changed type is stale, causing the
  ClickHouse optimizer to fall back to a less suitable projection and scan
  far more rows than necessary.

  This projection covers the `get_test_case_ids_with_ci_runs_on_branch` query:

      SELECT DISTINCT test_case_id
      FROM test_case_runs
      WHERE git_branch = ?
        AND is_ci = 1
        AND ran_at >= ?
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_branch_ci SETTINGS mutations_sync = 1"

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
