defmodule Pulse.PromQL.BatchTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.BatchQueryStorage
  alias Pulse.Test.BlockingMetricStorage

  defp finish(results, deadline), do: {:ok, {results, deadline}}
  defp queries, do: [{"A", "one", %{end_ts_ns: 10}}, {"B", "two", %{end_ts_ns: 10}}]

  defp sample(name, value),
    do: %MetricSample{series_id: 1, timestamp_ns: 10, value: value, labels: %{"__name__" => name}}

  @tag :loki_scalars_batch
  test "LogQL scalar result types preserve shared work and point quotas" do
    scalar = {"scalar", "2", %{end_ts_ns: 10, language: :logql}}
    vector = {"vector", "vector(4)", %{end_ts_ns: 10, language: :logql}}

    for queries <- [[scalar, vector], [vector, scalar]] do
      assert {:ok, {results, _}} = Evaluator.query_batch(queries, "loki-scalar", &finish/2)
      assert results["scalar"] == {:logql, :scalar, [{%{}, {10, 2.0}}]}
      assert results["vector"] == {:logql, :vector, [{%{}, {10, 4.0}}]}
    end

    for {setting, reason} <- [max_work: :query_work_limit, max_result_points: :query_result_limit] do
      Runtime.put_env(:pulse, Evaluator, [{setting, 1}])
      for query <- [scalar, vector], do: assert({:ok, _} = Evaluator.query_batch([query], "loki-scalar", &finish/2))

      for queries <- [[scalar, vector], [vector, scalar]] do
        assert {:error, ^reason} =
                 Evaluator.query_batch(queries, "loki-scalar", fn _, _ -> flunk("partial scalar result") end)
      end
    end
  end

  test "string and raw-range results share the batch's result quota in either order" do
    assert :ok = Storage.append(:metrics, "raw-result", [sample("one", 4.0)])
    queries = [{"text", ~s("literal"), %{end_ts_ns: 10}}, {"raw", "one[1s]", %{end_ts_ns: 10}}]

    for batch <- [queries, Enum.reverse(queries)] do
      assert {:ok, {results, _}} = Evaluator.query_batch(batch, "raw-result", &finish/2)
      assert results["text"]["data"] == %{"resultType" => "string", "result" => [1.0e-8, "literal"]}

      assert results["raw"]["data"] == %{
               "resultType" => "matrix",
               "result" => [%{"metric" => %{"__name__" => "one"}, "values" => [[1.0e-8, "4"]]}]
             }
    end

    Runtime.put_env(:pulse, Evaluator, max_result_points: 1)
    for query <- queries, do: assert({:ok, _} = Evaluator.query_batch([query], "raw-result", &finish/2))

    for batch <- [queries, Enum.reverse(queries)] do
      assert {:error, :query_result_limit} =
               Evaluator.query_batch(batch, "raw-result", fn _, _ -> flunk("partial callback") end)
    end
  end

  test "query context is local to each batch source while scalar work and points accumulate" do
    expression = "start() + end() + step() + range()"

    assert {:ok, %{"data" => %{"result" => [_, "1"]}}} =
             Evaluator.query("start() == bool time()", "context")

    queries = [
      {"range", expression, %{start_ts_ns: 10_000_000_000, end_ts_ns: 15_000_000_000, step_ns: 2_000_000_000}},
      {"instant", expression, %{end_ts_ns: 7_000_000_000}},
      {"single", expression, %{start_ts_ns: 3_000_000_000, end_ts_ns: 3_000_000_000, step_ns: 5_000_000_000}}
    ]

    for batch <- [queries, Enum.reverse(queries)] do
      assert {:ok, {results, _}} = Evaluator.query_batch(batch, "context", &finish/2)
      assert results["instant"]["data"] == %{"resultType" => "scalar", "result" => [7.0, "14"]}

      assert results["range"]["data"]["result"] == [
               %{"metric" => %{}, "values" => [[10.0, "32"], [12.0, "32"], [14.0, "32"]]}
             ]

      assert results["single"]["data"]["result"] == [%{"metric" => %{}, "values" => [[3.0, "6"]]}]
    end

    for expression <- ["start()", "end()", "step()", "range()", "min_of(2, 3)", "max_of(2, 3)"],
        {setting, reason} <- [max_work: :query_work_limit, max_result_points: :query_result_limit] do
      query = {"one", expression, %{end_ts_ns: 0}}

      assert {:ok, cost} =
               Evaluator.query_batch([query], "context", fn _, _ -> {:ok, Process.get(:promql_budget)} end)

      key = if setting == :max_work, do: :work, else: :points
      Runtime.put_env(:pulse, Evaluator, [{setting, Map.fetch!(cost, key)}])
      assert {:ok, _} = Evaluator.query_batch([query], "context", &finish/2)

      assert {:error, ^reason} =
               Evaluator.query_batch([query, {"two", expression, %{end_ts_ns: 1}}], "context", fn _, _ ->
                 flunk("partial callback")
               end)

      Runtime.put_env(:pulse, Evaluator, [])
    end
  end

  test "lookback overrides apply per source, including timestamp, and never leak into defaults" do
    assert :ok = Storage.append(:metrics, "acme", [sample("one", 4.0)])
    time = 360_000_000_000

    queries = [
      {"wide", "one", %{end_ts_ns: time, lookback_ns: 600_000_000_000}},
      {"default", "one", %{end_ts_ns: time}},
      {"timestamp", "timestamp(one)", %{end_ts_ns: time, lookback_ns: 600_000_000_000}},
      {"short", "one", %{end_ts_ns: time, lookback_ns: 60_000_000_000}}
    ]

    assert {:ok, {results, _}} = Evaluator.query_batch(queries, "acme", &finish/2)
    assert [%{"value" => [360.0, "4"]}] = results["wide"]["data"]["result"]
    assert [%{"value" => [360.0, "1e-08"]}] = results["timestamp"]["data"]["result"]
    assert results["default"]["data"]["result"] == []
    assert results["short"]["data"]["result"] == []

    for invalid <- [0, -1, nil, 1.0, 9_223_372_036_854_775_808] do
      assert {:error, :invalid_lookback} = Evaluator.query("one", "acme", %{end_ts_ns: time, lookback_ns: invalid})
    end
  end

  test "source results and final callback share a tenant-scoped admitted worker/deadline" do
    Memory.reset()
    assert :ok = Storage.append(:metrics, "acme", [sample("one", 4.0), sample("two", 8.0)])
    assert :ok = Storage.append(:metrics, "beta", [sample("one", 99.0)])
    assert {:ok, {results, deadline}} = Evaluator.query_batch(queries(), "acme", &finish/2)
    assert is_integer(deadline)
    assert results["A"]["data"]["result"] |> hd() |> Map.get("value") |> List.last() == "4"
    assert results["B"]["data"]["result"] |> hd() |> Map.get("value") |> List.last() == "8"
  end

  test "sample and output allocation budgets accumulate across queries, not per-node resets" do
    Memory.reset()
    assert :ok = Storage.append(:metrics, "acme", [sample("one", 4.0), sample("two", 8.0)])
    Runtime.put_env(:pulse, Evaluator, max_samples: 1)
    assert {:error, :query_sample_limit} = Evaluator.query_batch(queries(), "acme", &finish/2)
    Runtime.put_env(:pulse, Evaluator, max_result_points: 1)
    assert {:error, :query_result_limit} = Evaluator.query_batch(queries(), "acme", &finish/2)
    assert {:ok, _} = Evaluator.query("two", "acme", %{end_ts_ns: 10})
  end

  test "one slot covers all sources; aggregate scan ceilings are divided across every storage read" do
    Runtime.put_env(:pulse, Storage, adapter: BatchQueryStorage)
    Runtime.put_env(:pulse, BatchQueryStorage, self())
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_per_tenant: 1, class_limits: %{promql: 1})
    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 9, max_scan_bytes: 101, max_scan_rows: 999)
    callers = start_supervised!({Task.Supervisor, name: __MODULE__.Calls})
    owner = self()

    {:ok, _} =
      Task.Supervisor.start_child(callers, fn ->
        send(
          owner,
          {:batch_result,
           Evaluator.query_batch(
             [{"A", "one+two", %{end_ts_ns: 10}}, {"B", "three", %{end_ts_ns: 10}}],
             "acme",
             &finish/2
           )}
        )
      end)

    # Each source is one shared read (9 / 2 sources); an adapter without
    # multi-selector reads splits a source's share across its selectors.
    assert_receive {:batch_query, worker, "acme", first}, 5000
    ref = Process.monitor(worker)
    assert first[:max_scan_segments] == 2
    assert first[:max_scan_bytes] == 25
    assert first[:max_scan_rows] == 249
    send(worker, {:release_batch, {:ok, []}})
    assert_receive {:batch_query, ^worker, "acme", second}, 5000
    assert second[:deadline_ms] == first[:deadline_ms]
    send(worker, {:release_batch, {:ok, []}})
    assert_receive {:batch_query, ^worker, "acme", third}, 5000
    assert third[:max_scan_bytes] == 50
    send(worker, {:release_batch, {:ok, []}})
    assert_receive {:batch_result, {:ok, _}}, 5000
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 5000
  end

  test "mixed languages share one slot, deadline and aggregate selector scan allowance" do
    Runtime.put_env(:pulse, Storage, adapter: BatchQueryStorage)
    Runtime.put_env(:pulse, BatchQueryStorage, self())
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_per_tenant: 1, class_limits: %{promql: 1}, max_scan_segments: 6)
    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 9, max_scan_bytes: 101, max_scan_rows: 999)
    callers = start_supervised!({Task.Supervisor, name: __MODULE__.Calls})
    owner = self()

    batch = [
      {"A", "one", %{end_ts_ns: 10}},
      {"B", ~s'count_over_time({service="api"}[1m]) + count_over_time({service="api"}[2m])',
       %{end_ts_ns: 10, language: :logql}}
    ]

    {:ok, _} =
      Task.Supervisor.start_child(callers, fn ->
        send(owner, {:mixed_result, Evaluator.query_batch(batch, "acme", &finish/2)})
      end)

    assert_receive {:batch_query, worker, "acme", first}, 5000
    monitor = Process.monitor(worker)
    assert first[:max_scan_segments] == 2
    assert first[:max_scan_bytes] == 33
    send(worker, {:release_batch, {:ok, []}})

    for _ <- 1..2 do
      assert_receive {:batch_query, ^worker, "acme", opts}, 5000
      assert opts[:max_scan_segments] == 2
      assert opts[:max_scan_bytes] == 33
      assert opts[:max_scan_rows] == 333
      assert opts[:max_records] == 100_000
      assert opts[:deadline_ms] == first[:deadline_ms]
      send(worker, {:release_batch, {:ok, []}})
    end

    assert_receive {:mixed_result, {:ok, {%{"B" => {:logql, :vector, []}}, _}}}, 5000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5000
  end

  test "mixed source failures cannot reset budgets or return a partial callback" do
    Memory.reset()
    assert :ok = Storage.append(:metrics, "acme", [sample("one", 4.0)])
    assert :ok = Storage.append(:logs, "acme", [%Log{timestamp_ns: 10, service: "api", body: "hello"}])
    metric = {"A", "one", %{end_ts_ns: 10}}
    logs = {"B", ~s'count_over_time({service="api"}[1m])', %{end_ts_ns: 10, language: :logql}}
    # The metric fits its sample quota; the log source exceeds its own.
    Runtime.put_env(:pulse, Evaluator, max_samples: 1, max_log_samples: 0)

    for batch <- [[metric, logs], [logs, metric]] do
      assert {:error, :query_sample_limit} =
               Evaluator.query_batch(batch, "acme", fn _, _ -> flunk("partial callback") end)
    end

    assert {:error, :invalid_logql} =
             Evaluator.query_batch([{"L", "not logql", %{language: :logql}}], "acme", &finish/2)

    assert {:error, :unsupported_source_query} =
             Evaluator.query_batch([{"L", ~s'{service="api"}', %{language: :logql}}], "acme", &finish/2)
  end

  test "work and output points also accumulate across language boundaries in either order" do
    logs = {"L", "1", %{end_ts_ns: 10, language: :logql}}

    {:ok, work} =
      Evaluator.query_batch([{"P", "1+2", %{end_ts_ns: 10}}], "acme", fn _, _ ->
        {:ok, Process.get(:promql_budget).work}
      end)

    assert work > 0

    for {limits, query, reason} <- [
          {[max_work: work], "1+2", :query_work_limit},
          {[max_result_points: 1], "1", :query_result_limit}
        ] do
      Runtime.put_env(:pulse, Evaluator, limits)
      metric = {"P", query, %{end_ts_ns: 10}}
      assert {:ok, _} = Evaluator.query_batch([metric], "acme", &finish/2)
      assert {:ok, _} = Evaluator.query_batch([logs], "acme", &finish/2)

      for batch <- [[metric, logs], [logs, metric]] do
        assert {:error, ^reason} = Evaluator.query_batch(batch, "acme", fn _, _ -> flunk("partial callback") end)
      end
    end
  end

  test "invalid/cyclic identity batches and indivisible scan budgets fail without partial callback" do
    callback = fn _, _ -> flunk("partial callback") end

    for batch <- [[{"A", "one", %{}}, {"A", "two", %{}}], [nil], List.duplicate({"A", "one", %{}}, 129)] do
      assert {:error, :invalid_query_batch} = Evaluator.query_batch(batch, "acme", callback)
    end

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 1)
    assert {:error, :query_scan_limit} = Evaluator.query_batch(queries(), "acme", callback)
  end

  test "source errors are not a successful empty graph and the finish callback is inside the deadline" do
    Runtime.put_env(:pulse, Storage, adapter: BlockingMetricStorage)
    Runtime.put_env(:pulse, BlockingMetricStorage, {:error, :backend_unavailable})

    assert {:error, {:storage_error, :backend_unavailable}} =
             Evaluator.query_batch(queries(), "acme", fn _, _ -> flunk("source failure") end)

    assert {:error, :query_timeout} =
             Evaluator.query_batch(
               [],
               "acme",
               fn _, _ ->
                 receive do
                   :never -> :unexpected
                 end
               end,
               %{timeout_ms: 10}
             )
  end
end
