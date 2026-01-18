defmodule Tuist.IngestRepo.Migrations.AddGitCommitShaToTestCaseRuns do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE test_case_runs
    ADD COLUMN IF NOT EXISTS git_commit_sha String DEFAULT ''
    """)
  end

  def down do
    execute("""
    ALTER TABLE test_case_runs
    DROP COLUMN IF EXISTS git_commit_sha
    """)
  end
end
