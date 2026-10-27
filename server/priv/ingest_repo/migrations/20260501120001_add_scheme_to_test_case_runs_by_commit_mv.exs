defmodule Tuist.IngestRepo.Migrations.AddSchemeToTestCaseRunsByCommitMv do
  @moduledoc """
  Adds `scheme` to the cross-run flakiness lookup so two CI runs on the
  same commit but different schemes are treated as separate execution
  variants and do not flag each other as flaky.

  Builds a new-schema table under a temporary name, backfills it from
  `test_case_runs` partitions, then atomically swaps it into the canonical
  `test_case_runs_by_commit` name via `EXCHANGE TABLES`. The previous
  legacy data ends up parked under `test_case_runs_by_commit_v2` and is
  dropped in a follow-up migration once the rollout is stable. Keeping
  the canonical name means application code does not have to switch
  table identifiers across the deploy.

  The new ORDER BY puts `scheme` in the prefix
  `(project_id, git_commit_sha, scheme, is_ci, status, id)` so the lookup
  keyed by project + commit + scheme reads a small contiguous range.

  ## Catch-up against in-flight writes

  Naive sequence "backfill + drop legacy MV + EXCHANGE + create new MV"
  loses any row inserted into `test_case_runs` after that row's
  partition was backfilled but before the legacy MV was dropped: those
  rows go through the legacy MV into the legacy storage table, which
  ends up parked in `test_case_runs_by_commit_v2` after the swap and
  never make it into the canonical table.

  To close that hole, we capture a `cutoff` timestamp before backfill
  starts and, after the swap, re-insert any source rows with
  `inserted_at >= cutoff` directly into the canonical table. The
  destination is a `ReplacingMergeTree(inserted_at)` keyed on
  `(project_id, git_commit_sha, scheme, is_ci, status, id)`, so any
  overlap with rows already copied by the partition backfill or written
  by the new MV is collapsed by background merges. The lookup
  deduplicates by `id` in code as a defensive measure for the brief
  window before merges complete.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(project_id git_commit_sha scheme is_ci status id test_case_id inserted_at)

  def up do
    cutoff = NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())

    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_commit_new")

    IngestRepo.query!("""
    CREATE TABLE test_case_runs_by_commit_new (
      project_id Int64,
      git_commit_sha String,
      scheme String,
      is_ci Bool DEFAULT false,
      status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
      id UUID,
      test_case_id Nullable(UUID),
      inserted_at DateTime64(6)
    ) ENGINE = ReplacingMergeTree(inserted_at)
    ORDER BY (project_id, git_commit_sha, scheme, is_ci, status, id)
    """)

    backfill_by_partition()

    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_commit_mv")

    IngestRepo.query!("EXCHANGE TABLES test_case_runs_by_commit AND test_case_runs_by_commit_new")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW test_case_runs_by_commit_mv
    TO test_case_runs_by_commit
    AS SELECT
      project_id,
      git_commit_sha,
      scheme,
      is_ci,
      status,
      id,
      test_case_id,
      inserted_at
    FROM test_case_runs
    """)

    catch_up_inflight_writes(cutoff)

    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_commit_v2")

    IngestRepo.query!("RENAME TABLE test_case_runs_by_commit_new TO test_case_runs_by_commit_v2")
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_commit_mv")

    IngestRepo.query!("EXCHANGE TABLES test_case_runs_by_commit AND test_case_runs_by_commit_v2")

    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_commit_v2")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW test_case_runs_by_commit_mv
    TO test_case_runs_by_commit
    AS SELECT
      project_id,
      git_commit_sha,
      is_ci,
      status,
      id,
      test_case_id,
      inserted_at
    FROM test_case_runs
    """)
  end

  defp backfill_by_partition do
    {:ok, %{rows: partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
        ORDER BY partition
        """,
        %{table: "test_case_runs"}
      )

    for [partition] <- partitions do
      Logger.info("Backfilling partition #{partition} into test_case_runs_by_commit_new")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO test_case_runs_by_commit_new (#{Enum.join(@columns, ", ")})
          SELECT #{Enum.join(@columns, ", ")}
          FROM test_case_runs
          WHERE toYYYYMM(inserted_at) = {partition:UInt32}
          """,
          %{partition: String.to_integer(partition)},
          timeout: 1_200_000
        )
      end)
    end
  end

  defp catch_up_inflight_writes(cutoff) do
    Logger.info("Catching up test_case_runs writes since #{cutoff} into test_case_runs_by_commit")

    retry_on_shutting_down(fn ->
      IngestRepo.query!(
        """
        INSERT INTO test_case_runs_by_commit (#{Enum.join(@columns, ", ")})
        SELECT #{Enum.join(@columns, ", ")}
        FROM test_case_runs
        WHERE inserted_at >= toDateTime64({cutoff:String}, 6)
        """,
        %{cutoff: cutoff},
        timeout: 1_200_000
      )
    end)
  end

  defp retry_on_shutting_down(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      if attempts > 1 and String.contains?(to_string(e.message), "TABLE_IS_READ_ONLY") do
        Logger.warning("Table is shutting down, retrying in 5s (#{attempts - 1} attempts left)")
        Process.sleep(:timer.seconds(5))
        retry_on_shutting_down(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
