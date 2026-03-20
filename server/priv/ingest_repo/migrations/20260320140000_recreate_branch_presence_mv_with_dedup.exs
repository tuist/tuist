defmodule Tuist.IngestRepo.Migrations.RecreateBranchPresenceMvWithDedup do
  @moduledoc """
  Recreates test_case_branch_presence as ReplacingMergeTree(ran_at) with
  ORDER BY (project_id, git_branch, is_ci, test_case_id).

  The original MergeTree MV stored every row from test_case_runs (~50M rows),
  making queries just as slow as the source table. ReplacingMergeTree deduplicates
  to one row per (project_id, git_branch, is_ci, test_case_id), keeping the
  latest ran_at. This dramatically reduces the MV size.

  The query uses ran_at >= ? as a filter (not in ORDER BY), so it's applied
  after the PrimaryKey binary search on (project_id, git_branch, is_ci).
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_branch_presence")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_branch_presence
    ENGINE = ReplacingMergeTree(ran_at)
    ORDER BY (project_id, git_branch, is_ci, test_case_id)
    SETTINGS allow_nullable_key = 1
    AS SELECT
      project_id,
      git_branch,
      is_ci,
      test_case_id,
      ran_at
    FROM test_case_runs
    """)
  end

  def down do
    :ok
  end
end
