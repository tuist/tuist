defmodule Tuist.IngestRepo.Migrations.RematerializeBranchCiProjection do
  @moduledoc """
  Ensures `proj_by_branch_ci` exists and is materialized.

  Migration 100002 drops and re-adds this projection, but on ClickHouse 25.10
  the `SETTINGS mutations_sync = 1` on the DROP caused the subsequent ADD to
  not register the projection correctly. This migration is self-contained:
  it drops (no-op if missing), re-adds, and materializes, so it recovers
  regardless of whether 100002 left the projection in a good or bad state.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_branch_ci"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_branch_ci (
      SELECT git_branch, is_ci, ran_at, test_case_id
      ORDER BY git_branch, is_ci, ran_at, test_case_id
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_by_branch_ci SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
