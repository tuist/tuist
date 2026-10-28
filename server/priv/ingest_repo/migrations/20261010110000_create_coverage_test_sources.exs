defmodule Tuist.IngestRepo.Migrations.CreateCoverageTestSources do
  @moduledoc """
  The versions of each test, by what it executed
  (`Tuist.Tests.Coverage.TestSources`): a fingerprint of the repository
  files a run's evidence says the test and its suite executed, with their
  blobs, and the latest run that recorded that version. A commit whose run
  skipped the test carries it from the run whose fingerprint its own blobs
  reproduce, read by test, without walking its history. Merges keep one row
  per repository, test and version; each run that records it again
  refreshes its insertion time. Rows expire with the evidence they point to,
  `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90 by default) after insertion.
  """
  use Ecto.Migration

  alias Tuist.Environment
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    retention = Environment.coverage_retention_days().files

    execute("""
    CREATE TABLE IF NOT EXISTS coverage_test_sources
    (
      `project_id` Int64,
      `git_repository_id` Int64,
      `test_case_id` UUID,
      `fingerprint` String,
      `paths` Array(String) CODEC(ZSTD(1)),
      `unlined_paths` Array(String),
      `passed` Bool,
      `test_run_id` UUID,
      `git_commit_sha` String,
      `ran_at` DateTime64(6),
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(ran_at)")}
    ORDER BY (project_id, git_repository_id, test_case_id, fingerprint)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS coverage_test_sources")
  end
end
