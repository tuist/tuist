defmodule Tuist.IngestRepo.Migrations.AddGitCommitShaIndexToCoverageRuns do
  @moduledoc """
  Adds a skipping index on the commit a coverage run measured.

  A commit's coverage is read through its runs, found by SHA. The table is
  ordered by project and run, so without the index every read of one commit
  scanned the project's whole run history. Run ids are time-ordered, so the
  runs of a commit sit in few granules and the bloom filter skips the rest.
  """
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE coverage_runs
    ADD INDEX IF NOT EXISTS idx_git_commit_sha git_commit_sha
    TYPE bloom_filter GRANULARITY 1
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE coverage_runs DROP INDEX IF EXISTS idx_git_commit_sha"
  end
end
