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
    ADD COLUMN IF NOT EXISTS is_flaky Bool DEFAULT false
    """)

    execute("""
    ALTER TABLE test_runs
    ADD COLUMN IF NOT EXISTS is_flaky Bool DEFAULT false
    """)

    execute("""
    ALTER TABLE test_case_runs
    ADD INDEX IF NOT EXISTS idx_cross_run_flaky (test_case_id, git_commit_sha, is_ci)
    TYPE bloom_filter() GRANULARITY 1
    """)

    execute("""
    ALTER TABLE test_case_runs MATERIALIZE INDEX idx_cross_run_flaky
    """)
  end

  def down do
    execute("""
    ALTER TABLE test_case_runs
    DROP INDEX IF EXISTS idx_cross_run_flaky
    """)

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
    DROP COLUMN IF EXISTS is_flaky
    """)

    execute("""
    ALTER TABLE test_runs
    DROP COLUMN IF EXISTS is_flaky
    """)
  end
end
