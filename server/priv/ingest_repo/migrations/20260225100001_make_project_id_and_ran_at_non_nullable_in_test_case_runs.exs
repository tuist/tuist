defmodule Tuist.IngestRepo.Migrations.MakeProjectIdAndRanAtNonNullableInTestCaseRuns do
  @moduledoc """
  Makes `project_id` and `ran_at` non-nullable in the `test_case_runs` table.

  Projections that reference these columns must be dropped first because
  ClickHouse does not allow MODIFY COLUMN while projections depend on the column.
  They are recreated in subsequent migrations after the column type change.

  The previous migration backfilled all NULL values, so no data is lost.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_test_case_runs_by_project_ran_at"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_flaky"

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
