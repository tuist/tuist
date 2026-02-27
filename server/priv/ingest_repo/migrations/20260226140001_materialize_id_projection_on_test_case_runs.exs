defmodule Tuist.IngestRepo.Migrations.MaterializeIdProjectionOnTestCaseRuns do
  @moduledoc """
  Materializes the `proj_by_id` projection for existing data.
  Separated from the projection creation so new inserts benefit immediately.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_by_id SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
