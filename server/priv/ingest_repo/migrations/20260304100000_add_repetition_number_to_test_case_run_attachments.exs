defmodule Tuist.IngestRepo.Migrations.AddRepetitionNumberToTestCaseRunAttachments do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_run_attachments
    ADD COLUMN IF NOT EXISTS repetition_number Nullable(Int32) DEFAULT NULL
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_run_attachments
    DROP COLUMN IF EXISTS repetition_number
    """)
  end
end
