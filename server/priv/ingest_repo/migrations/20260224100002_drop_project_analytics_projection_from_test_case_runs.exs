defmodule Tuist.IngestRepo.Migrations.DropProjectAnalyticsProjectionFromTestCaseRuns do
  @moduledoc """
  Drops the old `proj_by_project_analytics` projection which is superseded by
  `proj_test_case_runs_by_project_ran_at`.

  This runs after the materialize migration which uses `mutations_sync = 1`,
  guaranteeing all pending mutations have completed before we attempt the drop.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_analytics"
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_project_analytics (
      SELECT
        id,
        project_id,
        inserted_at,
        is_ci,
        status,
        duration
      ORDER BY project_id, inserted_at
    )
    """
  end
end
