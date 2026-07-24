Code.require_file(
  Path.expand(
    "../../../priv/ingest_repo/migrations/20260724140000_stop_unused_recent_test_case_run_aggregates.exs",
    __DIR__
  )
)

defmodule Tuist.IngestRepo.Migrations.StopUnusedRecentTestCaseRunAggregatesTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migrations.StopUnusedRecentTestCaseRunAggregates

  @active_views [
    "test_case_runs_recent_100_per_case_mv",
    "test_case_runs_recent_100_success_per_case_mv"
  ]

  @retired_tables [
    "test_case_runs_recent_250_per_case",
    "test_case_runs_recent_500_per_case",
    "test_case_runs_recent_750_per_case",
    "test_case_runs_recent_per_case"
  ]

  setup do
    query_log = start_supervised!({Agent, fn -> [] end}, id: :query_log)
    merge_responses = start_supervised!({Agent, fn -> [[], []] end}, id: :merge_responses)

    stub(IngestRepo, :query!, fn sql ->
      Agent.update(query_log, &[sql | &1])
      query_result(sql, merge_responses)
    end)

    %{merge_responses: merge_responses, query_log: query_log}
  end

  test "stops before changing tables when a retired table is merging", %{
    merge_responses: merge_responses,
    query_log: query_log
  } do
    Agent.update(merge_responses, fn _responses ->
      [[["test_case_runs_recent_750_per_case"]]]
    end)

    assert_raise Ecto.MigrationError,
                 "active background merges must finish before retiring rolling aggregates: test_case_runs_recent_750_per_case",
                 fn ->
                   StopUnusedRecentTestCaseRunAggregates.up()
                 end

    queries = recorded_queries(query_log)

    assert length(queries) == 2
    refute Enum.any?(queries, &String.starts_with?(&1, "ALTER TABLE"))
    refute Enum.any?(queries, &String.starts_with?(&1, "DROP VIEW"))
  end

  test "keeps views active when a merge starts while automatic merges are being stopped", %{
    merge_responses: merge_responses,
    query_log: query_log
  } do
    Agent.update(merge_responses, fn _responses ->
      [[], [["test_case_runs_recent_500_per_case"]]]
    end)

    assert_raise Ecto.MigrationError,
                 "active background merges must finish before retiring rolling aggregates: test_case_runs_recent_500_per_case",
                 fn ->
                   StopUnusedRecentTestCaseRunAggregates.up()
                 end

    queries = recorded_queries(query_log)

    assert Enum.count(queries, &String.starts_with?(&1, "ALTER TABLE")) == 4
    assert Enum.count(queries, &String.contains?(&1, "FROM system.merges")) == 2
    refute Enum.any?(queries, &String.starts_with?(&1, "DROP VIEW"))
  end

  test "stops automatic merges and rechecks before dropping views", %{query_log: query_log} do
    StopUnusedRecentTestCaseRunAggregates.up()

    queries = recorded_queries(query_log)
    alter_positions = query_positions(queries, "ALTER TABLE")
    merge_check_positions = query_positions(queries, "FROM system.merges")
    drop_positions = query_positions(queries, "DROP VIEW")

    assert length(alter_positions) == 4
    assert length(merge_check_positions) == 2
    assert length(drop_positions) == 8
    assert Enum.at(merge_check_positions, 0) < Enum.min(alter_positions)
    assert Enum.max(alter_positions) < Enum.at(merge_check_positions, 1)
    assert Enum.at(merge_check_positions, 1) < Enum.min(drop_positions)
  end

  defp query_result(sql, merge_responses) do
    cond do
      String.contains?(sql, "FROM system.merges") ->
        rows =
          Agent.get_and_update(merge_responses, fn [rows | remaining_responses] ->
            {rows, remaining_responses}
          end)

        %{rows: rows}

      String.contains?(sql, "FROM system.tables") and
          String.contains?(sql, "test_case_runs_recent_100_per_case_mv") ->
        %{rows: Enum.map(@active_views, &[&1, "CREATE MATERIALIZED VIEW #{&1}"])}

      String.contains?(sql, "FROM system.tables") and
          String.contains?(sql, "test_case_runs_recent_250_per_case_mv") ->
        %{rows: []}

      String.contains?(sql, "FROM system.tables") ->
        %{
          rows:
            Enum.map(
              @retired_tables,
              &[&1, "CREATE TABLE #{&1} SETTINGS max_bytes_to_merge_at_max_space_in_pool = 1"]
            )
        }

      true ->
        %{rows: []}
    end
  end

  defp recorded_queries(query_log) do
    query_log
    |> Agent.get(& &1)
    |> Enum.reverse()
  end

  defp query_positions(queries, marker) do
    queries
    |> Enum.with_index()
    |> Enum.filter(fn {query, _index} -> String.contains?(query, marker) end)
    |> Enum.map(fn {_query, index} -> index end)
  end
end
