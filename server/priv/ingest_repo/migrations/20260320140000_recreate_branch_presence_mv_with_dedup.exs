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

  To avoid downtime, the new MV is created under a temporary name, backfilled,
  then atomically swapped with the old one via EXCHANGE TABLES.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_branch_presence_new")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_branch_presence_new
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

    backfill("test_case_runs", "test_case_branch_presence_new")

    IngestRepo.query!("EXCHANGE TABLES test_case_branch_presence AND test_case_branch_presence_new")
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_branch_presence_new")
  end

  def down do
    :ok
  end

  defp backfill(source, destination) do
    {:ok, %{rows: partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
        ORDER BY partition
        """,
        %{table: source}
      )

    for [partition] <- partitions do
      Logger.info("Backfilling partition #{partition} from #{source} into #{destination}")

      IngestRepo.query!(
        """
        INSERT INTO #{destination}
        SELECT project_id, git_branch, is_ci, test_case_id, ran_at
        FROM #{source}
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        """,
        %{partition: String.to_integer(partition)},
        timeout: 600_000
      )
    end
  end
end
