defmodule Tuist.IngestRepo.Migrations.AddArtifactRetentionProjections do
  @moduledoc """
  Adds the projections the artifact retention sweeps scan by.

  `build_runs` and `test_runs` are ReplacingMergeTree, and ClickHouse rejects
  `ADD PROJECTION` on a non-plain MergeTree while the table still carries the
  default `deduplicate_merge_projection_mode = 'throw'`. Both tables were
  switched to `'rebuild'` by the migrations that added their `proj_by_id`
  projections, but that setting lives in the table's `SETTINGS` clause, so any
  instance whose table metadata was recreated without it (a restore from a
  schema dump, say) arrives here with `'throw'` and fails on error 344. Set the
  mode here rather than inherit it, so this migration stands on its own.

  `shard_plans` and `test_case_run_attachments` are plain MergeTree, which
  ignores the setting entirely.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'rebuild'
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'rebuild'
    """

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
