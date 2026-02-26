defmodule Tuist.IngestRepo.Migrations.RematerializeBranchCiProjection do
  @moduledoc """
  Ensures `proj_by_branch_ci` exists and is materialized.

  Migration 100002 drops and re-adds this projection. On ClickHouse 25.10
  the `SETTINGS mutations_sync = 1` on the DROP caused the ADD to not register
  the projection correctly, so this migration uses ADD IF NOT EXISTS before
  materializing to recover from that state without a redundant drop.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION IF NOT EXISTS proj_by_branch_ci (
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
