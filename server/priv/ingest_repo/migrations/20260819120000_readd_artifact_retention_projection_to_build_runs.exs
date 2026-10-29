defmodule Tuist.IngestRepo.Migrations.ReaddArtifactRetentionProjectionToBuildRuns do
  @moduledoc """
  Puts `proj_artifact_retention_by_project_inserted_at` back on `build_runs`.

  `20260529100000` added it, then the `updated_at` table swap in
  `20260812120000` rebuilt `build_runs` with a hardcoded `proj_by_id` as its
  only projection, so the retention projection was dropped on every instance
  that ran the swap. `Tuist.Storage.ExpiredArtifacts.delete_build_archives/3`
  scans `project_id IN (...) AND inserted_at < cutoff`, and the table sorts by
  `(project_id, id)`, so without it the `inserted_at` bound falls back to
  reading every part for the account's projects.

  The swap migration now reconstructs projections from `system.projections`,
  which keeps fresh installs whole; this one repairs the instances that already
  passed it. `IF NOT EXISTS` makes the two orderings agree.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # ClickHouse rejects ADD PROJECTION on a ReplacingMergeTree still carrying
    # the default `deduplicate_merge_projection_mode = 'throw'`.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_runs
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
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_runs DROP PROJECTION IF EXISTS proj_artifact_retention_by_project_inserted_at"
  end
end
