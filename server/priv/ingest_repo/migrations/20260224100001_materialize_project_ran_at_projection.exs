defmodule Tuist.IngestRepo.Migrations.MaterializeProjectRanAtProjection do
  @moduledoc """
  Materializes the `proj_test_case_runs_by_project_ran_at` projection for existing data parts.
  This is a separate migration so that the DDL change is applied first and new
  data immediately benefits from the projection.

  Materialization rebuilds the projection for all existing data parts and may
  take time on large tables.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_test_case_runs_by_project_ran_at SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
