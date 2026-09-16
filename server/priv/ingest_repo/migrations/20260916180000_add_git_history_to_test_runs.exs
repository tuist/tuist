defmodule Tuist.IngestRepo.Migrations.AddGitHistoryToTestRuns do
  @moduledoc """
  Records each test run's place in the repository's history, and the files
  it changed.

  `test_runs` gains the base branch and merge base the run was compared
  against, whether it ran for a pull request (and which), the repository's
  Git object format, and where the history came from (`history_source`:
  `client`, `provider`, `mixed` or `none`) with the reason anything is
  missing. `test_run_changed_files` holds the files changed between the merge
  base and the head, with the line ranges of their hunks and the blob each
  had at the head, so patch coverage can be computed against the run's own
  coverage rows. It expires with the coverage file detail.
  """
  use Ecto.Migration

  alias Tuist.Environment

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    ALTER TABLE test_runs
      ADD COLUMN IF NOT EXISTS base_branch String DEFAULT '',
      ADD COLUMN IF NOT EXISTS merge_base_sha String DEFAULT '',
      ADD COLUMN IF NOT EXISTS is_pull_request Bool DEFAULT false,
      ADD COLUMN IF NOT EXISTS pull_request_number UInt32 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS git_object_format LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS history_source LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS history_fallback_reason String DEFAULT ''
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_run_changed_files
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `path` String,
      `previous_path` String DEFAULT '',
      `status` LowCardinality(String),
      `git_blob_id` String DEFAULT '',
      `hunk_starts` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `hunk_ends` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `truncated` Bool DEFAULT false,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, test_run_id, path)
    TTL toDateTime(inserted_at) + INTERVAL #{Environment.coverage_retention_days().files} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS test_run_changed_files")

    execute("""
    ALTER TABLE test_runs
      DROP COLUMN IF EXISTS base_branch,
      DROP COLUMN IF EXISTS merge_base_sha,
      DROP COLUMN IF EXISTS is_pull_request,
      DROP COLUMN IF EXISTS pull_request_number,
      DROP COLUMN IF EXISTS git_object_format,
      DROP COLUMN IF EXISTS history_source,
      DROP COLUMN IF EXISTS history_fallback_reason
    """)
  end
end
