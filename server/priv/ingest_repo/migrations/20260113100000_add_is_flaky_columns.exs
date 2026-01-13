defmodule Tuist.IngestRepo.Migrations.AddIsFlakyColumns do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE test_case_runs
    ADD COLUMN IF NOT EXISTS is_flaky Bool DEFAULT false
    """)

    execute("""
    ALTER TABLE test_suite_runs
    ADD COLUMN IF NOT EXISTS is_flaky Bool DEFAULT false
    """)

    execute("""
    ALTER TABLE test_module_runs
    ADD COLUMN IF NOT EXISTS is_flaky Bool DEFAULT false
    """)

    execute("""
    ALTER TABLE test_cases
    ADD COLUMN IF NOT EXISTS last_is_flaky Bool DEFAULT false
    """)

    execute("""
    ALTER TABLE test_runs
    ADD COLUMN IF NOT EXISTS is_flaky Bool DEFAULT false
    """)
  end

  def down do
    execute("""
    ALTER TABLE test_case_runs
    DROP COLUMN IF EXISTS is_flaky
    """)

    execute("""
    ALTER TABLE test_suite_runs
    DROP COLUMN IF EXISTS is_flaky
    """)

    execute("""
    ALTER TABLE test_module_runs
    DROP COLUMN IF EXISTS is_flaky
    """)

    execute("""
    ALTER TABLE test_cases
    DROP COLUMN IF EXISTS last_is_flaky
    """)

    execute("""
    ALTER TABLE test_runs
    DROP COLUMN IF EXISTS is_flaky
    """)
  end
end
