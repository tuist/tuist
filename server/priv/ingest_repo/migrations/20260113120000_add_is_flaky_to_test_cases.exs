defmodule Tuist.IngestRepo.Migrations.AddIsFlakyToTestCases do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE test_cases
    ADD COLUMN IF NOT EXISTS is_flaky Bool DEFAULT false
    """)

    execute("""
    ALTER TABLE test_cases
    DROP COLUMN IF EXISTS last_is_flaky
    """)
  end

  def down do
    execute("""
    ALTER TABLE test_cases
    DROP COLUMN IF EXISTS is_flaky
    """)

    execute("""
    ALTER TABLE test_cases
    ADD COLUMN IF NOT EXISTS last_is_flaky Bool DEFAULT false
    """)
  end
end
