defmodule Tuist.IngestRepo.Migrations.CreateCoverageFileDeltas do
  @moduledoc """
  A complete commit's per-file coverage, stored once per change instead of
  merged from its runs' `coverage_files` rows on every read
  (`Tuist.Tests.Coverage.Deltas`), and its per-target totals.

  `coverage_file_deltas` holds a row for a file only where the commit's
  figures differ from those of its previous complete commit, keyed by where
  the commit sits on the first-parent tree (`ref_id`, `position`, copied from
  `coverage_commits`), so a commit's files are a range read up its ref and
  the refs it forks from. `executable_lines = 0` marks a file the commit no
  longer has. A `checkpoint` row set is a full snapshot that reads start
  from. A row whose key moved (a fast-forward, a rebuild of the refs) is
  retired with `is_deleted`, which `FINAL` drops. The bloom filter finds a
  commit's rows by SHA when it moves.

  `coverage_commit_targets` holds each complete commit's targets whole. Its
  rows also say which version of the commit, and which place (`ref_id`,
  `position`; 0 when it has no ref), its file rows were written for, so a
  reader knows when they are current.

  Both expire with the commit totals they belong to,
  `TUIST_COVERAGE_COMMIT_RETENTION_DAYS` (1095 by default) after the commit
  was made, rather than with the 90-day file detail.
  """
  use Ecto.Migration

  alias Tuist.Environment
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    retention = Environment.coverage_commit_retention_days().commits

    execute("""
    CREATE TABLE IF NOT EXISTS coverage_file_deltas
    (
      `project_id` Int64,
      `ref_id` Int64,
      `position` UInt32,
      `path` String CODEC(ZSTD(1)),
      `git_commit_sha` String,
      `base_sha` String DEFAULT '',
      `kind` Enum8('delta' = 1, 'checkpoint' = 2),
      `covered_lines` UInt32,
      `executable_lines` UInt32,
      `commit_version` UInt64,
      `committed_at` DateTime64(6),
      `row_version` UInt64,
      `is_deleted` UInt8 DEFAULT 0,
      INDEX idx_git_commit_sha git_commit_sha TYPE bloom_filter GRANULARITY 1
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(row_version, is_deleted)")}
    ORDER BY (project_id, ref_id, position, path)
    TTL toDateTime(committed_at) + INTERVAL #{retention} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS coverage_commit_targets
    (
      `project_id` Int64,
      `git_commit_sha` String,
      `target` String,
      `files_count` UInt32,
      `covered_lines` UInt64,
      `executable_lines` UInt64,
      `commit_version` UInt64,
      `ref_id` Int64 DEFAULT 0,
      `position` UInt32 DEFAULT 0,
      `committed_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(commit_version)")}
    ORDER BY (project_id, git_commit_sha, target)
    TTL toDateTime(committed_at) + INTERVAL #{retention} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS coverage_commit_targets")
    execute("DROP TABLE IF EXISTS coverage_file_deltas")
  end
end
