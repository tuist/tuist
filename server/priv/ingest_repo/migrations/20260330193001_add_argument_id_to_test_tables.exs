defmodule Tuist.IngestRepo.Migrations.AddArgumentIdToTestTables do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_failures
    ADD COLUMN IF NOT EXISTS test_case_run_argument_id Nullable(UUID) DEFAULT NULL
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_run_repetitions
    ADD COLUMN IF NOT EXISTS test_case_run_argument_id Nullable(UUID) DEFAULT NULL
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_run_attachments
    ADD COLUMN IF NOT EXISTS test_case_run_argument_id Nullable(UUID) DEFAULT NULL
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_failures
    DROP COLUMN IF EXISTS test_case_run_argument_id
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_run_repetitions
    DROP COLUMN IF EXISTS test_case_run_argument_id
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_run_attachments
    DROP COLUMN IF EXISTS test_case_run_argument_id
    """)
  end
end
