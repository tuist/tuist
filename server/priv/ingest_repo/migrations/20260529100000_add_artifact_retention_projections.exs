defmodule Tuist.IngestRepo.Migrations.AddArtifactRetentionProjections do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_runs
    ADD PROJECTION IF NOT EXISTS proj_artifact_retention_by_project_inserted_at (
      SELECT id, project_id, inserted_at
      ORDER BY project_id, inserted_at
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    ADD PROJECTION IF NOT EXISTS proj_artifact_retention_by_project_inserted_at (
      SELECT id, project_id, inserted_at
      ORDER BY project_id, inserted_at
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_run_attachments
    ADD PROJECTION IF NOT EXISTS proj_artifact_retention_by_test_run_inserted_at (
      SELECT id, assumeNotNull(test_run_id) AS test_run_id, test_case_run_id, file_name, inserted_at
      ORDER BY test_run_id, inserted_at
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE shard_plans
    ADD PROJECTION IF NOT EXISTS proj_artifact_retention_by_project_inserted_at (
      SELECT id, project_id, inserted_at
      ORDER BY project_id, inserted_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_runs DROP PROJECTION IF EXISTS proj_artifact_retention_by_project_inserted_at"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_runs DROP PROJECTION IF EXISTS proj_artifact_retention_by_project_inserted_at"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_run_attachments DROP PROJECTION IF EXISTS proj_artifact_retention_by_test_run_inserted_at"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE shard_plans DROP PROJECTION IF EXISTS proj_artifact_retention_by_project_inserted_at"
  end
end
