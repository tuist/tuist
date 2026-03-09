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
    # Ensure the is_new column exists — it may be missing if migration
    # 20260119100000 was recorded but the ALTER TABLE did not take effect.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs ADD COLUMN IF NOT EXISTS is_new Bool DEFAULT false"

    # Kill any stuck mutations from previous failed attempts so the new
    # MATERIALIZE mutations can proceed.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    KILL MUTATION
    WHERE database = currentDatabase()
      AND table = 'test_case_runs'
      AND is_done = 0
    """

    # Force-merge all data parts so every part includes the is_new column.
    # Old parts created before the ADD COLUMN lack the column file, causing
    # MATERIALIZE mutations to fail with "Missing columns: 'is_new'".
    # OPTIMIZE TABLE FINAL rewrites parts with the current schema.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "OPTIMIZE TABLE test_case_runs FINAL"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE INDEX idx_id SETTINGS mutations_sync = 1"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_by_project_flaky SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
