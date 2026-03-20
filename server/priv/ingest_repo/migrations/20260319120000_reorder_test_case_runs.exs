defmodule Tuist.IngestRepo.Migrations.ReorderTestCaseRuns do
  @moduledoc """
  Reorders the test_case_runs table from ORDER BY (test_run_id, test_module_run_id, id)
  to ORDER BY (project_id, test_case_id, ran_at, id).

  The original ORDER BY was chosen for ReplacingMergeTree deduplication, but since `id`
  is unique per row, any ORDER BY containing `id` correctly deduplicates. The new ordering
  matches dominant query patterns: most queries filter by project_id, test_case_id, or
  ran_at — enabling PrimaryKey binary search instead of full scans with bloom filters.

  Projections are intentionally NOT recreated because they don't work with
  ReplacingMergeTree (ClickHouse issue #46968).
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        "SELECT sorting_key FROM system.tables WHERE database = currentDatabase() AND name = {table:String}",
        %{table: "test_case_runs"}
      )

    case rows do
      [["project_id, test_case_id, ran_at, id"]] ->
        Logger.info("test_case_runs already has the new ORDER BY, skipping")

      _ ->
        columns = get_column_definitions("test_case_runs")

        indexes = """
        INDEX idx_id (id) TYPE bloom_filter GRANULARITY 4,
          INDEX idx_git_commit_sha (git_commit_sha) TYPE bloom_filter GRANULARITY 1,
          INDEX idx_test_run_id (test_run_id) TYPE bloom_filter GRANULARITY 4,
          INDEX idx_is_ci (is_ci) TYPE set(2) GRANULARITY 1,
          INDEX idx_status (status) TYPE set(3) GRANULARITY 1,
          INDEX idx_git_branch (git_branch) TYPE bloom_filter GRANULARITY 1,
          INDEX idx_is_flaky (is_flaky) TYPE set(2) GRANULARITY 1\
        """

        IngestRepo.query!("""
        CREATE TABLE IF NOT EXISTS test_case_runs_new (
          #{columns},
          #{indexes}
        ) ENGINE = ReplacingMergeTree(inserted_at)
        PARTITION BY toYYYYMM(inserted_at)
        ORDER BY (project_id, test_case_id, ran_at, id)
        SETTINGS allow_nullable_key = 1
        """)

        copy_data_by_partition("test_case_runs", "test_case_runs_new")

        IngestRepo.query!("EXCHANGE TABLES test_case_runs AND test_case_runs_new")

        # MVs reference the source table by internal UUID, so after the exchange
        # the old MVs still point at test_case_runs_new (which now holds the old
        # data). Drop and recreate them to point at the new table. This is done
        # after the swap so that if the data copy fails, the MVs remain intact.
        IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_inserted_at")
        IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_daily_stats")

        IngestRepo.query!("""
        CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_inserted_at
        ENGINE = MergeTree
        ORDER BY (project_id, inserted_at)
        POPULATE
        AS SELECT * FROM test_case_runs
        """)

        IngestRepo.query!("""
        CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_daily_stats
        ENGINE = AggregatingMergeTree
        ORDER BY (project_id, date, status, is_ci, is_flaky)
        POPULATE
        AS SELECT
          project_id,
          toDate(inserted_at) AS date,
          status,
          is_ci,
          is_flaky,
          countState() AS count_state,
          avgState(duration) AS avg_duration_state,
          quantileState(0.50)(duration) AS p50_duration_state,
          quantileState(0.90)(duration) AS p90_duration_state,
          quantileState(0.99)(duration) AS p99_duration_state
        FROM test_case_runs
        GROUP BY project_id, toDate(inserted_at), status, is_ci, is_flaky
        """)

        Logger.info(
          "Completed reordering test_case_runs to (project_id, test_case_id, ran_at, id)"
        )
    end
  end

  def down do
    :ok
  end

  defp copy_data_by_partition(source, destination) do
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

    {:ok, %{rows: existing_partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
        """,
        %{table: destination}
      )

    existing_set = MapSet.new(existing_partitions, fn [p] -> p end)

    for [partition] <- partitions, not MapSet.member?(existing_set, partition) do
      Logger.info("Copying partition #{partition} from #{source} to #{destination}")

      IngestRepo.query!(
        "INSERT INTO #{destination} SELECT * FROM #{source} WHERE toYYYYMM(inserted_at) = {partition:UInt32}",
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end

  defp get_column_definitions(table_name) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT name, type, default_kind, default_expression
        FROM system.columns
        WHERE database = currentDatabase() AND table = {table:String}
        ORDER BY position
        """,
        %{table: table_name}
      )

    rows
    |> Enum.map(fn [name, type, default_kind, default_expression] ->
      default_clause =
        case default_kind do
          "DEFAULT" -> " DEFAULT #{default_expression}"
          _ -> ""
        end

      "#{name} #{type}#{default_clause}"
    end)
    |> Enum.join(",\n  ")
  end
end
