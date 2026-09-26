defmodule Tuist.IngestRepo.Migrations.AddGitCommitShaIndexToTestRuns do
  @moduledoc """
  Adds a skipping index on the commit a test run ran on.

  A commit's coverage fold reads the commit's runs by SHA, those that
  measured nothing included (`Coverage.Reported`: the schemes selective
  testing skipped whole, and the runs of a commit no run measured). The
  table is ordered by project and run, so without the index each of those
  reads scanned the project's whole run history. Run ids are time-ordered,
  so the runs of a commit sit in few granules and the bloom filter skips the
  rest, as `20260923130000_add_git_commit_sha_index_to_coverage_runs` does
  for `coverage_runs`.

  `ADD INDEX` is metadata-only. `MATERIALIZE INDEX` builds it for existing
  parts as a background mutation and returns at once, so it does not block
  the deploy.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    ADD INDEX IF NOT EXISTS idx_git_commit_sha git_commit_sha
    TYPE bloom_filter GRANULARITY 1
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_runs MATERIALIZE INDEX idx_git_commit_sha"
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_runs DROP INDEX IF EXISTS idx_git_commit_sha"
  end
end
