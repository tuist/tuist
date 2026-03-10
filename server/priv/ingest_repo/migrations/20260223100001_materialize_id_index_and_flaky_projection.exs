defmodule Tuist.IngestRepo.Migrations.MaterializeIdIndexAndFlakyProjection do
  @moduledoc """
  Materializes the bloom filter index on `id` and the `proj_by_project_flaky`
  projection for existing data parts. This is a separate migration so that the
  DDL changes are applied first, and new data immediately benefits.

  Materialization rebuilds the index/projection for all existing data parts and
  may take time on large tables.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE INDEX idx_id SETTINGS mutations_sync = 1"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_by_project_flaky SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
