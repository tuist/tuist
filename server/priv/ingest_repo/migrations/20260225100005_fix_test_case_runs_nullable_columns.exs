defmodule Tuist.IngestRepo.Migrations.FixTestCaseRunsNullableColumns do
  @moduledoc """
  Ensures test_case_runs columns are non-nullable.

  Migration 100001 handles this, but in CI the MODIFY COLUMN statements
  may be skipped due to stale _build cache loading an old version of that
  migration module. Running them here (in a fresh module) guarantees they
  execute. If the columns are already non-nullable, these are no-ops.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN project_id Int64 DEFAULT 0 SETTINGS mutations_sync = 1"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN project_id REMOVE DEFAULT SETTINGS mutations_sync = 1"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN ran_at DateTime64(6) DEFAULT toDateTime64('1970-01-01 00:00:00', 6) SETTINGS mutations_sync = 1"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN ran_at REMOVE DEFAULT SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
