defmodule Tuist.IngestRepo.Migrations.AddIsFlakyToTestCaseRunsByCommit do
  @moduledoc """
  Adds the latest flaky state to the commit-scoped test case run lookup.

  The target table can be extended in place. Updating the materialized view
  query is atomic, so ingestion has no drop-and-recreate gap. Historical flaky
  rows are then copied by source partition. Stable insert tokens make a
  restarted backfill safe without rebuilding or exchanging the lookup table.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @canonical_table "test_case_runs_by_commit"
  @canonical_view "test_case_runs_by_commit_mv"
  @source_table "test_case_runs"
  @columns ~w(project_id git_commit_sha scheme is_ci status id test_case_id is_flaky inserted_at)
  @legacy_columns ~w(project_id git_commit_sha scheme is_ci status id test_case_id inserted_at)
  @backfill_select_columns [
    "project_id",
    "git_commit_sha",
    "scheme",
    "is_ci",
    "status",
    "id",
    "test_case_id",
    "is_flaky",
    "addMicroseconds(inserted_at, 1) AS inserted_at"
  ]
  @deduplication_window 1000

  def up do
    enable_insert_deduplication(@source_table)
    enable_insert_deduplication(@canonical_table)

    IngestRepo.query!("""
    ALTER TABLE #{@canonical_table}
    ADD COLUMN IF NOT EXISTS is_flaky Bool DEFAULT false AFTER test_case_id
    """)

    modify_materialized_view_query(@columns)
    backfill_flaky_rows_by_partition()
  end

  def down do
    modify_materialized_view_query(@legacy_columns)

    IngestRepo.query!("""
    ALTER TABLE #{@canonical_table}
    DROP COLUMN IF EXISTS is_flaky
    """)
  end

  defp enable_insert_deduplication(table) do
    IngestRepo.query!("""
    ALTER TABLE #{table}
    MODIFY SETTING
      non_replicated_deduplication_window = #{@deduplication_window},
      replicated_deduplication_window = #{@deduplication_window}
    """)
  end

  defp modify_materialized_view_query(columns) do
    IngestRepo.query!("""
    ALTER TABLE #{@canonical_view}
    MODIFY QUERY
    SELECT #{Enum.join(columns, ", ")}
    FROM #{@source_table}
    """)
  end

  defp backfill_flaky_rows_by_partition do
    {:ok, %{rows: partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase()
          AND table = {table:String}
          AND active
        ORDER BY partition
        """,
        %{table: @source_table}
      )

    for [partition] <- partitions do
      Logger.info("Backfilling flaky rows from partition #{partition} into #{@canonical_table}")

      retry_on_transient_failure(fn ->
        IngestRepo.query(
          """
          INSERT INTO #{@canonical_table} (#{Enum.join(@columns, ", ")})
          SELECT #{Enum.join(@backfill_select_columns, ", ")}
          FROM #{@source_table}
          WHERE toYYYYMM(inserted_at) = {partition:UInt32}
            AND is_flaky = true
          ORDER BY ALL
          """,
          %{partition: String.to_integer(partition)},
          timeout: 1_200_000,
          settings: [
            insert_deduplication_token: "test-case-runs-by-commit-is-flaky-backfill:#{partition}",
            deduplicate_insert_select: "force_enable"
          ]
        )
      end)
    end
  end

  defp retry_on_transient_failure(fun, attempts \\ 5) do
    case fun.() do
      {:ok, _result} ->
        :ok

      {:error, %Ch.Error{} = error} ->
        if attempts > 1 and String.contains?(to_string(error.message), "TABLE_IS_READ_ONLY") do
          Logger.warning(
            "Table is read-only, retrying in 5 seconds (#{attempts - 1} attempts left)"
          )

          Process.sleep(:timer.seconds(5))
          retry_on_transient_failure(fun, attempts - 1)
        else
          raise error
        end

      {:error, error} ->
        Logger.warning("Flaky-state backfill failed with an unexpected result: #{inspect(error)}")

        raise error
    end
  end
end
