defmodule Tuist.IngestRepo.Migrations.MaterializeFlakyProjection do
  @moduledoc """
  Materializes the updated `proj_by_project_flaky` projection that now includes `ran_at` and `is_ci`.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_by_project_flaky SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
