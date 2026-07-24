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

  @active_table "test_case_runs_recent_100_per_case"
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

  @retired_views [
    "test_case_runs_recent_250_per_case_mv",
    "test_case_runs_recent_250_success_per_case_mv",
    "test_case_runs_recent_500_per_case_mv",
    "test_case_runs_recent_500_success_per_case_mv",
    "test_case_runs_recent_750_per_case_mv",
    "test_case_runs_recent_750_success_per_case_mv",
    "test_case_runs_recent_per_case_mv",
    "test_case_runs_recent_success_per_case_mv"
  ]

  setup do
    query_log = start_supervised!({Agent, fn -> [] end}, id: :query_log)

    state =
      start_supervised!(
        {Agent,
         fn ->
           %{
             active_views: @active_views,
             cluster_available?: true,
             drop_failure: nil,
             drop_failure_raised?: false,
             drop_noop: nil,
             initial_merge_settings: Map.new(@retired_tables, &{&1, :default}),
             merge_responses: List.duplicate([], 8),
             postcondition_setting: nil
           }
         end},
        id: :migration_state
      )

    stub(IngestRepo, :query!, fn sql ->
      maybe_fail_query!(sql, state)
      result = query_result(sql, state, query_log)
      Agent.update(query_log, &[sql | &1])
      result
    end)

    %{query_log: query_log, state: state}
  end

  test "stops before changing tables when a retired table is merging", %{
    query_log: query_log,
    state: state
  } do
    update_state(state, merge_responses: [[["test_case_runs_recent_750_per_case"]]])

    assert_raise Ecto.MigrationError,
                 "active background merges must finish before retiring rolling aggregates: test_case_runs_recent_750_per_case",
                 fn ->
                   StopUnusedRecentTestCaseRunAggregates.up()
                 end

    queries = recorded_queries(query_log)

    refute mutation_query?(queries)
    assert Enum.any?(queries, &String.contains?(&1, "clusterAllReplicas(default, system.merges)"))
  end

  test "restores merge settings when a merge starts before the views are removed", %{
    query_log: query_log,
    state: state
  } do
    update_state(state, merge_responses: [[], [["test_case_runs_recent_500_per_case"]]])

    assert_raise Ecto.MigrationError,
                 "active background merges must finish before retiring rolling aggregates: test_case_runs_recent_500_per_case",
                 fn ->
                   StopUnusedRecentTestCaseRunAggregates.up()
                 end

    queries = recorded_queries(query_log)

    assert Enum.count(queries, &modify_merge_setting_query?/1) == 4
    assert Enum.count(queries, &reset_merge_setting_query?/1) == 4
    refute Enum.any?(queries, &String.starts_with?(&1, "DROP VIEW"))
  end

  test "restores an explicit prior merge setting rather than resetting it", %{
    query_log: query_log,
    state: state
  } do
    previous_setting = 10_000

    update_state(state,
      initial_merge_settings: Map.new(@retired_tables, &{&1, {:explicit, previous_setting}}),
      merge_responses: [[], [["test_case_runs_recent_500_per_case"]]]
    )

    assert_raise Ecto.MigrationError, fn ->
      StopUnusedRecentTestCaseRunAggregates.up()
    end

    restoration_queries =
      query_log
      |> recorded_queries()
      |> Enum.filter(fn query ->
        modify_merge_setting_query?(query) and
          String.contains?(query, " = #{previous_setting}")
      end)

    assert length(restoration_queries) == 4
    refute Enum.any?(recorded_queries(query_log), &reset_merge_setting_query?/1)
  end

  test "stops automatic merges cluster-wide before dropping only retired views", %{query_log: query_log} do
    StopUnusedRecentTestCaseRunAggregates.up()

    queries = recorded_queries(query_log)
    alter_positions = query_positions(queries, "MODIFY SETTING")
    merge_check_positions = query_positions(queries, "system.merges")
    drop_positions = query_positions(queries, "DROP VIEW")

    assert length(alter_positions) == 4
    assert length(merge_check_positions) == 2
    assert length(drop_positions) == 8
    assert Enum.at(merge_check_positions, 0) < Enum.min(alter_positions)
    assert Enum.max(alter_positions) < Enum.at(merge_check_positions, 1)
    assert Enum.at(merge_check_positions, 1) < Enum.min(drop_positions)

    guard_queries = Enum.filter(queries, &String.contains?(&1, "system."))
    assert Enum.any?(guard_queries, &String.contains?(&1, "clusterAllReplicas(default, system.merges)"))
    assert Enum.any?(guard_queries, &String.contains?(&1, "clusterAllReplicas(default, system.tables)"))

    mutation_queries =
      Enum.filter(queries, &(String.starts_with?(&1, "ALTER TABLE") or String.starts_with?(&1, "DROP VIEW")))

    assert Enum.all?(mutation_queries, fn query ->
             refute String.contains?(query, @active_table)
             refute Enum.any?(@active_views, &String.contains?(query, &1))
             true
           end)
  end

  test "stops before mutations when an active 100-run view is missing", %{
    query_log: query_log,
    state: state
  } do
    update_state(state, active_views: [hd(@active_views)])

    assert_raise Ecto.MigrationError,
                 "required rolling materialized views are missing: test_case_runs_recent_100_success_per_case_mv",
                 fn ->
                   StopUnusedRecentTestCaseRunAggregates.up()
                 end

    refute mutation_query?(recorded_queries(query_log))
  end

  test "raises and restores merge settings when a dropped view remains present", %{
    query_log: query_log,
    state: state
  } do
    remaining_view = "test_case_runs_recent_500_per_case_mv"
    update_state(state, drop_noop: remaining_view)

    assert_raise Ecto.MigrationError,
                 "retired rolling materialized views remain present: #{remaining_view}",
                 fn ->
                   StopUnusedRecentTestCaseRunAggregates.up()
                 end

    queries = recorded_queries(query_log)
    assert Enum.count(queries, &reset_merge_setting_query?/1) == 4
  end

  test "does not accept a larger merge setting as the stopped postcondition", %{
    query_log: query_log,
    state: state
  } do
    update_state(state, postcondition_setting: 161_061_273_600)

    assert_raise Ecto.MigrationError,
                 "rolling aggregate tables still allow automatic merges: #{Enum.join(@retired_tables, ", ")}",
                 fn ->
                   StopUnusedRecentTestCaseRunAggregates.up()
                 end

    queries = recorded_queries(query_log)
    refute Enum.any?(queries, &reset_merge_setting_query?/1)
  end

  test "restores settings after a partial drop failure and succeeds when retried", %{
    query_log: query_log,
    state: state
  } do
    update_state(state, drop_failure: "test_case_runs_recent_500_success_per_case_mv")

    assert_raise RuntimeError, "simulated drop failure", fn ->
      StopUnusedRecentTestCaseRunAggregates.up()
    end

    assert Enum.count(recorded_queries(query_log), &reset_merge_setting_query?/1) == 4

    StopUnusedRecentTestCaseRunAggregates.up()

    queries = recorded_queries(query_log)
    assert Enum.count(queries, &String.starts_with?(&1, "DROP VIEW")) == 11
    assert Enum.count(queries, &modify_merge_setting_query?/1) == 8
  end

  test "is idempotent after the retired views have already been removed", %{query_log: query_log} do
    StopUnusedRecentTestCaseRunAggregates.up()
    StopUnusedRecentTestCaseRunAggregates.up()

    queries = recorded_queries(query_log)
    assert Enum.count(queries, &String.starts_with?(&1, "DROP VIEW")) == 16
    assert Enum.count(queries, &modify_merge_setting_query?/1) == 8
    refute Enum.any?(queries, &reset_merge_setting_query?/1)
  end

  test "down refuses to recreate views without a bounded backfill" do
    assert_raise Ecto.MigrationError,
                 "the retired materialized views require a bounded backfill before they can be re-enabled safely",
                 fn ->
                   StopUnusedRecentTestCaseRunAggregates.down()
                 end
  end

  defp query_result(sql, state, query_log) do
    cond do
      String.contains?(sql, "FROM system.clusters") ->
        if get_state(state, :cluster_available?), do: %{rows: [[1]]}, else: %{rows: []}

      String.contains?(sql, "system.merges") ->
        rows =
          Agent.get_and_update(state, fn %{merge_responses: [rows | remaining]} = current ->
            {rows, %{current | merge_responses: remaining}}
          end)

        %{rows: rows}

      system_tables_query?(sql, @active_views) ->
        %{rows: Enum.map(get_state(state, :active_views), &[&1, "CREATE MATERIALIZED VIEW #{&1}"])}

      system_tables_query?(sql, @retired_views) ->
        rows =
          query_log
          |> remaining_retired_views(state)
          |> Enum.map(&[&1, "CREATE MATERIALIZED VIEW #{&1}"])

        %{rows: rows}

      system_tables_query?(sql, @retired_tables) ->
        %{rows: retired_table_metadata(state, query_log)}

      true ->
        %{rows: []}
    end
  end

  defp remaining_retired_views(query_log, state) do
    dropped_views =
      query_log
      |> recorded_queries()
      |> Enum.filter(&String.starts_with?(&1, "DROP VIEW"))
      |> MapSet.new(fn query ->
        [_, view] = Regex.run(~r/DROP VIEW IF EXISTS ([a-z0-9_]+)/, query)
        view
      end)

    drop_noop = get_state(state, :drop_noop)

    Enum.reject(@retired_views, fn view ->
      MapSet.member?(dropped_views, view) and view != drop_noop
    end)
  end

  defp retired_table_metadata(state, query_log) do
    queries = recorded_queries(query_log)
    all_views_removed? = remaining_retired_views(query_log, state) == []
    postcondition_setting = get_state(state, :postcondition_setting)
    initial_settings = get_state(state, :initial_merge_settings)

    Enum.map(@retired_tables, fn table ->
      setting =
        if all_views_removed? and not is_nil(postcondition_setting) do
          {:explicit, postcondition_setting}
        else
          latest_merge_setting(queries, table, Map.fetch!(initial_settings, table))
        end

      [table, create_table_query(table, setting)]
    end)
  end

  defp latest_merge_setting(queries, table, initial_setting) do
    queries
    |> Enum.reverse()
    |> Enum.find_value(initial_setting, fn query ->
      cond do
        String.contains?(query, "ALTER TABLE #{table}") and String.contains?(query, "RESET SETTING") ->
          :default

        String.contains?(query, "ALTER TABLE #{table}") and String.contains?(query, "MODIFY SETTING") ->
          [_, value] = Regex.run(~r/max_bytes_to_merge_at_max_space_in_pool = (\d+)/, query)
          {:explicit, String.to_integer(value)}

        true ->
          nil
      end
    end)
  end

  defp create_table_query(table, :default), do: "CREATE TABLE #{table} SETTINGS index_granularity = 8192"

  defp create_table_query(table, {:explicit, value}),
    do:
      "CREATE TABLE #{table} SETTINGS index_granularity = 8192, " <> "max_bytes_to_merge_at_max_space_in_pool = #{value}"

  defp maybe_fail_query!(sql, state) do
    should_fail? =
      Agent.get_and_update(state, fn current ->
        fail? =
          not current.drop_failure_raised? and
            sql == "DROP VIEW IF EXISTS #{current.drop_failure}"

        {fail?, if(fail?, do: %{current | drop_failure_raised?: true}, else: current)}
      end)

    if should_fail?, do: raise("simulated drop failure")
  end

  defp system_tables_query?(sql, names) do
    String.contains?(sql, "system.tables") and Enum.any?(names, &String.contains?(sql, &1))
  end

  defp mutation_query?(queries) do
    Enum.any?(queries, &(String.starts_with?(&1, "ALTER TABLE") or String.starts_with?(&1, "DROP VIEW")))
  end

  defp modify_merge_setting_query?(query) do
    String.starts_with?(query, "ALTER TABLE") and String.contains?(query, "MODIFY SETTING")
  end

  defp reset_merge_setting_query?(query) do
    String.starts_with?(query, "ALTER TABLE") and String.contains?(query, "RESET SETTING")
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

  defp update_state(state, updates) do
    Agent.update(state, &Map.merge(&1, Map.new(updates)))
  end

  defp get_state(state, key), do: Agent.get(state, &Map.fetch!(&1, key))
end
