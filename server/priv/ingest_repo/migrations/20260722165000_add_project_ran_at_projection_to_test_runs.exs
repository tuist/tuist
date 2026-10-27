defmodule Tuist.IngestRepo.Migrations.AddProjectRanAtProjectionToTestRuns do
  @moduledoc """
  Adds a narrow projection for the overview's recent completed test runs.

  The base table is ordered by `(project_id, id)`, so fetching the latest runs
  for a project by `ran_at` reads and sorts every run for that project. This
  projection stores only the five fields needed by the overview and orders them
  by `(project_id, ran_at)`.

  Materialization happens in the follow-up migration so the projection metadata
  can propagate before existing parts are rewritten.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    ADD PROJECTION IF NOT EXISTS proj_by_project_ran_at (
      SELECT project_id, id, duration, status, ran_at
      ORDER BY project_id, ran_at
    )
    SETTINGS alter_sync = 2
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_runs DROP PROJECTION IF EXISTS proj_by_project_ran_at"
  end
end
