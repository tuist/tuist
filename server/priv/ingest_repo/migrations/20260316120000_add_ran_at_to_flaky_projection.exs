defmodule Tuist.IngestRepo.Migrations.AddRanAtToFlakyProjection do
  @moduledoc """
  Adds `ran_at` to the `proj_by_project_flaky` projection on `test_case_runs`.

  The flaky tests page now filters by time range using `ran_at`, but the existing
  projection doesn't include this column. This can cause ClickHouse to return
  incorrect results when the projection is used with lazy materialization.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_flaky SETTINGS alter_sync = 2"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION IF NOT EXISTS proj_by_project_flaky (
      SELECT id, project_id, is_flaky, is_ci, test_case_id, test_run_id, ran_at, inserted_at
      ORDER BY project_id, is_flaky, test_case_id, inserted_at
    )
    SETTINGS alter_sync = 2
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_flaky SETTINGS alter_sync = 2"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION IF NOT EXISTS proj_by_project_flaky (
      SELECT id, project_id, is_flaky, test_case_id, test_run_id, inserted_at
      ORDER BY project_id, is_flaky, test_case_id, inserted_at
    )
    SETTINGS alter_sync = 2
    """
  end
end
