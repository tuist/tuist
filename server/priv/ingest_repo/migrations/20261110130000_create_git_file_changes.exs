defmodule Tuist.IngestRepo.Migrations.CreateGitFileChanges do
  @moduledoc """
  The files a commit changed against the nearest listed commit below it on
  the first-parent tree (`Tuist.GitHistory.FileChanges`), written from the
  commit's uploaded listing (`git_commit_files`) so the listing itself need
  not be kept per commit.

  A row is keyed by where the commit sits on the tree (`ref_id`, `position`,
  as `git_commits` has them), so a path's blob at a commit is its newest row
  at or below the commit along its ref and the refs it forks from, and what
  changed between two commits is the rows between them. Position comes
  before path in the sort key: a range of commits, one commit's rows and
  the rows above a position are then ranges of the table, where path first
  made each of them a scan of the ref's whole history. An
  empty `git_blob_id` marks a path the commit no longer has. A row whose key
  moved (a fast-forward, a rebuild of the refs) is retired with
  `is_deleted`, which `FINAL` drops.

  The default branch's rows are kept (`expires_at` far in the future): every
  later commit's files are read through them. A ref that forks expires its
  rows together, the file retention after the last write that renewed them
  (one that found less than half of it left).
  """
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS git_file_changes
    (
      `repository_id` Int64,
      `ref_id` Int64,
      `position` UInt32,
      `generation` UInt32,
      `sha` String,
      `path` String CODEC(ZSTD(1)),
      `git_blob_id` String,
      `mode` UInt32,
      `expires_at` DateTime,
      `row_version` UInt64,
      `is_deleted` UInt8 DEFAULT 0
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(row_version, is_deleted)")}
    ORDER BY (repository_id, ref_id, position, path)
    TTL expires_at
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS git_file_changes")
  end
end
