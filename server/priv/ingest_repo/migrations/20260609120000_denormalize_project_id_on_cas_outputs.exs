defmodule Tuist.IngestRepo.Migrations.DenormalizeProjectIdOnCasOutputs do
  @moduledoc """
  Adds and backfills `project_id` on `cas_outputs` for project-level cache
  analytics.

  This table is written continuously in production, so the migration keeps
  `cas_outputs` as the canonical table instead of copying into a shadow table
  and swapping. The backfill is an in-place ClickHouse mutation backed by a
  dictionary lookup, and the project-ordered access path is provided by a
  materialized projection.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true
  @dict_name "build_runs_project_ids_for_cas_outputs"
  @projection_name "proj_by_project_operation_inserted_at"

  def up do
    IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")

    create_project_ids_dictionary()
    add_project_id_column()

    try do
      backfill_project_id()
      add_project_ordered_projection()
      materialize_project_ordered_projection()
    after
      IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")
    end
  end

  def down do
    IngestRepo.query!("ALTER TABLE cas_outputs DROP PROJECTION IF EXISTS #{@projection_name}")
    IngestRepo.query!("ALTER TABLE cas_outputs DROP COLUMN IF EXISTS project_id")
  end

  defp create_project_ids_dictionary do
    IngestRepo.query!("""
    CREATE DICTIONARY #{@dict_name} (
      id UUID,
      project_id Int64
    )
    PRIMARY KEY id
    SOURCE(CLICKHOUSE(TABLE 'build_runs'))
    LAYOUT(HASHED())
    LIFETIME(0)
    """)
  end

  defp add_project_id_column do
    IngestRepo.query!("""
    ALTER TABLE cas_outputs
    ADD COLUMN IF NOT EXISTS project_id Int64 DEFAULT 0 AFTER operation
    """)
  end

  defp backfill_project_id do
    Logger.info("Starting cas_outputs project_id backfill mutation")

    IngestRepo.query!(
      """
      ALTER TABLE cas_outputs
      UPDATE project_id = dictGetOrDefault('#{@dict_name}', 'project_id', build_run_id, toInt64(0))
      WHERE project_id = 0
      SETTINGS mutations_sync = 1
      """,
      [],
      timeout: :infinity
    )

    Logger.info("Finished cas_outputs project_id backfill mutation")
  end

  defp add_project_ordered_projection do
    IngestRepo.query!("""
    ALTER TABLE cas_outputs
    ADD PROJECTION IF NOT EXISTS #{@projection_name}
    (
      SELECT
        project_id,
        operation,
        inserted_at,
        size,
        duration,
        compressed_size
      ORDER BY (project_id, operation, inserted_at)
    )
    """)
  end

  defp materialize_project_ordered_projection do
    Logger.info("Starting cas_outputs project-ordered projection materialization")

    IngestRepo.query!(
      """
      ALTER TABLE cas_outputs
      MATERIALIZE PROJECTION #{@projection_name}
      SETTINGS mutations_sync = 1
      """,
      [],
      timeout: :infinity
    )

    Logger.info("Finished cas_outputs project-ordered projection materialization")
  end
end
