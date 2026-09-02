defmodule Tuist.IngestRepo.Migrations.MaterializeTestAttachmentRetentionProjection do
  @moduledoc """
  Materializes `proj_artifact_retention_by_inserted_at` across the existing
  parts of `test_case_run_attachments`. The preceding migration only recorded
  the projection definition; this one does the part rewrite.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_run_attachments
    MATERIALIZE PROJECTION proj_artifact_retention_by_inserted_at
    """
  end

  def down do
    :ok
  end
end
