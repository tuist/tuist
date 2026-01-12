defmodule Tuist.IngestRepo.Migrations.ChangeTestCasesLastStatusToLowCardinalityString do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE test_cases
    MODIFY COLUMN last_status LowCardinality(String)
    """)
  end

  def down do
    execute("""
    ALTER TABLE test_cases
    MODIFY COLUMN last_status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2, 'flaky' = 3)
    """)
  end
end
