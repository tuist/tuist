defmodule Tuist.IngestRepo.Migrations.MaterializeProjectRanAtProjectionOnTestRuns do
  @moduledoc """
  Materializes `test_runs.proj_by_project_ran_at` for existing parts.

  The preceding migration adds the projection metadata. This migration starts
  the part rewrite separately to avoid racing replica metadata propagation.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    MATERIALIZE PROJECTION proj_by_project_ran_at
    """
  end

  def down do
    :ok
  end
end
