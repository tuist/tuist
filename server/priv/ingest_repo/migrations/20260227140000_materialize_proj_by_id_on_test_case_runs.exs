defmodule Tuist.IngestRepo.Migrations.MaterializeProjByIdOnTestCaseRuns do
  @moduledoc """
  Materializes the `proj_by_id` projection for existing data parts. This is a
  separate migration so that the DDL change (ADD PROJECTION) is applied and
  propagated across replicas first.
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
