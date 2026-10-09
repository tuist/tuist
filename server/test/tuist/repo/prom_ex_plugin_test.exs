defmodule Tuist.Repo.PromExPluginTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.PromEx.StripedPeep
  alias Tuist.Repo.PromExPlugin
  alias TuistCommon.Repo.PoolMetrics

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "uses the same query and pool labels in every runtime" do
    for workload <- [:web, :processor, :xcresult_processor, :swift_registry_sync] do
      stub(Tuist.Environment, :mode, fn -> workload end)

      groups = PromExPlugin.event_metrics([]) ++ PromExPlugin.polling_metrics([])

      for group <- groups, metric <- group.metrics do
        tags = metric.tag_values.(%{repo: "postgres", database: "postgres", result: {:ok, %{}}})
        assert tags.workload == to_string(workload)
        assert :workload in metric.tags
      end
    end
  end

  test "exports query phases separately, preserving counts across scrapes", context do
    stub(Tuist.Environment, :mode, fn -> :xcresult_processor end)

    metrics = query_metrics(context.test)
    start_supervised!(StripedPeep.child_spec(context.test, metrics))

    for {prefix, repo} <- [
          {:repo, "postgres"},
          {:click_house_repo, "clickhouse_read"},
          {:ingest_repo, "clickhouse_write"},
          {:shadow_click_house_repo, "clickhouse_shadow_read"},
          {:shadow_ingest_repo, "clickhouse_shadow_write"},
          {:ops_click_house_repo, "ops_clickhouse_read"}
        ] do
      PromExPlugin.handle_query(
        [:tuist, prefix, :query],
        native_times(total_time: 135, queue_time: 100, query_time: 30, decode_time: 5, idle_time: 2_000),
        %{result: {:ok, %{}}, query: "private query text", params: ["private parameter"]},
        [:tuist, :database, :query, context.test]
      )

      output = StripedPeep.scrape(context.test)
      tags = ~s(repo="#{repo}",result="ok",workload="xcresult_processor")
      assert output =~ ~s(tuist_repo_query_count{#{tags}} 1)

      for {phase, value} <- [total_time: 135, queue_time: 100, query_time: 30, decode_time: 5, idle_time: 2_000] do
        assert output =~ ~s(tuist_repo_query_#{phase}_milliseconds_sum{#{tags}} #{value})
        assert output =~ ~s(tuist_repo_query_#{phase}_milliseconds_count{#{tags}} 1)
      end

      refute output =~ "private"
      assert StripedPeep.scrape(context.test) == output
    end

    assert length(Regex.scan(~r/^# TYPE tuist_repo_query_count counter$/m, StripedPeep.scrape(context.test))) == 1
  end

  test "application startup wires repository events into the shared metrics", context do
    stub(Tuist.Environment, :mode, fn -> :web end)
    owner = self()

    metrics =
      context.test
      |> query_metrics()
      |> Enum.map(&%{&1 | event_name: [:tuist, :database, :query], keep: fn _ -> self() == owner end})

    start_supervised!(StripedPeep.child_spec(context.test, metrics))

    for {prefix, repo} <- [
          {:repo, "postgres"},
          {:shadow_click_house_repo, "clickhouse_shadow_read"},
          {:shadow_ingest_repo, "clickhouse_shadow_write"},
          {:ops_click_house_repo, "ops_clickhouse_read"}
        ] do
      :telemetry.execute([:tuist, prefix, :query], native_times(total_time: 25, query_time: 25), %{result: {:ok, %{}}})

      assert StripedPeep.scrape(context.test) =~
               ~s(tuist_repo_query_count{repo="#{repo}",result="ok",workload="web"} 1)
    end

    refute StripedPeep.scrape(context.test) =~ "idle_time_milliseconds"
  end

  test "counts rejected checkouts without inventing execution or decoding times", context do
    stub(Tuist.Environment, :mode, fn -> :processor end)
    start_supervised!(StripedPeep.child_spec(context.test, query_metrics(context.test)))

    PromExPlugin.handle_query(
      [:tuist, :repo, :query],
      native_times(total_time: 705, queue_time: 705),
      %{result: {:error, DBConnection.ConnectionError.exception("unavailable", :queue_timeout)}},
      [:tuist, :database, :query, context.test]
    )

    output = StripedPeep.scrape(context.test)
    tags = ~s(repo="postgres",result="queue_timeout",workload="processor")
    assert output =~ ~s(tuist_repo_query_count{#{tags}} 1)
    assert output =~ ~s(tuist_repo_query_queue_time_milliseconds_sum{#{tags}} 705)
    refute output =~ "tuist_repo_query_query_time_milliseconds_count"
    refute output =~ "tuist_repo_query_decode_time_milliseconds_count"
    refute output =~ "tuist_repo_query_idle_time_milliseconds_count"
  end

  test "polls each running physical pool without inventing optional pools", context do
    owner = self()
    event = Tuist.Telemetry.event_name_repo_pool_metrics()

    :telemetry.attach(
      context.test,
      event,
      fn _, measurements, metadata, pid ->
        if self() == pid, do: send(pid, {:pool_metrics, measurements, metadata})
      end,
      owner
    )

    on_exit(fn -> :telemetry.detach(context.test) end)

    running = [
      {Tuist.Repo, "postgres"},
      {Tuist.ShadowClickHouseRepo, "clickhouse_shadow_read"},
      {Tuist.ShadowIngestRepo, "clickhouse_shadow_write"},
      {Tuist.OpsClickHouseRepo, "ops_clickhouse_read"}
    ]

    stub(PoolMetrics, :running?, fn repo -> Enum.any?(running, &(elem(&1, 0) == repo)) end)

    expect(PoolMetrics, :connection_pool_metrics, length(running), fn repo ->
      assert Enum.any?(running, &(elem(&1, 0) == repo))
      %{checkout_queue_length: 2, ready_conn_count: 0, pool_size: 5}
    end)

    PromExPlugin.execute_repo_pool_metrics_event()

    for {_, label} <- running do
      assert_receive {:pool_metrics, %{pool_size: 5, checkout_queue_starved_count: 1}, %{repo: ^label}}
    end

    refute_receive {:pool_metrics, _, _}
  end

  test "uses bounded outcomes for connection and database errors", context do
    stub(Tuist.Environment, :mode, fn -> :web end)
    start_supervised!(StripedPeep.child_spec(context.test, query_metrics(context.test)))

    for {error, result} <- [
          {%DBConnection.ConnectionError{message: "private host"}, "connection_error"},
          {%RuntimeError{message: "private query"}, "error"}
        ] do
      PromExPlugin.handle_query(
        [:tuist, :repo, :query],
        %{},
        %{result: {:error, error}},
        [:tuist, :database, :query, context.test]
      )

      output = StripedPeep.scrape(context.test)
      assert output =~ ~s(tuist_repo_query_count{repo="postgres",result="#{result}",workload="web"} 1)
      refute output =~ "private"
    end
  end

  defp query_metrics(test) do
    []
    |> PromExPlugin.event_metrics()
    |> Enum.flat_map(& &1.metrics)
    |> Enum.filter(&match?([:tuist, :repo, :query | _], &1.name))
    |> Enum.map(&%{&1 | event_name: &1.event_name ++ [test]})
  end

  defp native_times(times) do
    Map.new(times, fn {key, value} -> {key, System.convert_time_unit(value, :millisecond, :native)} end)
  end
end
