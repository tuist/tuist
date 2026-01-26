defmodule Tuist.IngestRepo.Migrations.MaterializeProjectAnalyticsProjection do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_by_project_analytics"
  end

  def down do
    :ok
  end
end
