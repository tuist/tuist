defmodule Tuist.IngestRepo.Migrations.ModifyColumnsNonNullableInTestCaseRuns do
  @moduledoc """
  Makes `project_id` and `ran_at` non-nullable in the `test_case_runs` table.

  The previous migration dropped projections that depend on these columns.
  This is a separate migration so that retries don't re-queue DROP PROJECTION
  mutations.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # ClickHouse requires a DEFAULT when converting from Nullable to non-nullable,
    # even when no NULLs exist. We remove it immediately after so the column
    # ends up non-nullable with no default.
    # mutations_sync = 1 makes each ALTER wait for the mutation to complete
    # before returning, preventing concurrent mutation errors.
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
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN project_id Nullable(Int64)"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN ran_at Nullable(DateTime64(6))"
  end
end
