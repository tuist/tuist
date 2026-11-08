defmodule Pulse.PromQL.EvaluatorTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.QuerySlots
  alias Pulse.PromQL.TaskSupervisor
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime.Task
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.BlockingMetricStorage

  setup do
    Memory.reset()
    :ok
  end

  defp append(name, points, extra \\ %{}, tenant \\ "acme") do
    samples =
      Enum.map(points, fn {seconds, value} ->
        %MetricSample{
          series_id: 1,
          timestamp_ns: seconds * 1_000_000_000,
          value: value * 1.0,
          labels: Map.put(extra, "__name__", name)
        }
      end)

    :ok = Storage.append(:metrics, tenant, samples)
  end

  defp instant(query, time, tenant \\ "acme") do
    Evaluator.query(query, tenant, %{end_ts_ns: time * 1_000_000_000})
  end

  defp values(result), do: Enum.map(result["data"]["result"], & &1["value"])

  test "the operator heap ceiling is configurable" do
    Pulse.Runtime.put_env(:pulse, Evaluator, max_heap_words: 1000)
    append("memory", Enum.map(1..1000, &{&1, &1}))
    assert {:error, :query_resource_limit} = instant("memory", 1000)
  end

  test "real blocked queries enforce tenant admission and release their slots" do
    adapter = BlockingMetricStorage
    Pulse.Runtime.put_env(:pulse, Pulse.Storage, adapter: adapter)
    Pulse.Runtime.put_env(:pulse, adapter, self())

    callers = start_supervised!({Task.Supervisor, name: __MODULE__.CallerSupervisor})
    owner = self()

    workers =
      for _ <- 1..2 do
        {:ok, _} =
          Task.Supervisor.start_child(callers, fn -> send(owner, {:finished_metric_query, instant("m", 1, "acme")}) end)

        assert_receive {:blocked_metric_query, worker, "acme"}, 5_000
        worker
      end

    assert {:error, :query_overloaded} = instant("m", 1, "acme")

    {:ok, _} =
      Task.Supervisor.start_child(callers, fn -> send(owner, {:finished_metric_query, instant("m", 1, "beta")}) end)

    assert_receive {:blocked_metric_query, beta, "beta"}, 5_000
    refs = Enum.map([beta | workers], &Process.monitor/1)
    Enum.each([beta | workers], &send(&1, {:release, {:ok, []}}))
    for _ <- 1..3, do: assert_receive({:finished_metric_query, {:ok, _}}, 5_000)
    # A result reaches the caller before its worker necessarily exits.
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, :normal}, 5_000)
    slots = Pulse.Runtime.name(QuerySlots)

    # Registry partitions clean up asynchronously after worker termination.
    # Registration, used by admission, synchronously reclaims dead owners.
    for slot <- 0..1 do
      assert {:ok, _} = Registry.register(slots, {"acme", slot}, nil)
      Registry.unregister(slots, {"acme", slot})
    end
  end

  test "one tenant cannot occupy every node slot" do
    owner = self()
    slots = Pulse.Runtime.name(QuerySlots)

    for slot <- 0..1 do
      {:ok, pid} =
        Task.Supervisor.start_child(TaskSupervisor, fn ->
          {:ok, _} = Registry.register(slots, {"acme", slot}, nil)
          send(owner, {:tenant_slot, self()})
          receive do: (:release -> :ok)
        end)

      assert_receive {:tenant_slot, ^pid}, 5_000
    end

    # The query task supervisor and slot registry are owned by this test and
    # stop with it, so the blocked children need no explicit cleanup.
    assert {:error, :query_overloaded} = instant("m", 1, "acme")
    assert {:ok, _} = instant("m", 1, "beta")
  end

  test "unexpected task crashes are execution failures" do
    Pulse.Runtime.put_env(:pulse, Pulse.Storage, adapter: Pulse.MissingAdapter)
    # The crash, not the default 10 s deadline, must end this query under load.
    Pulse.Runtime.put_env(:pulse, Pulse.QueryRunner, timeout_ms: 60_000)

    ExUnit.CaptureLog.capture_log(fn ->
      assert {:error, :query_execution_failed} = instant("m", 1)
    end)
  end

  test "query admission rejects excess work and releases capacity" do
    owner = self()

    children =
      for _ <- 1..4 do
        {:ok, pid} =
          Task.Supervisor.start_child(TaskSupervisor, fn ->
            send(owner, {:query_slot, self()})
            receive do: (:release -> :ok)
          end)

        assert_receive {:query_slot, ^pid}
        pid
      end

    assert {:error, :query_overloaded} = instant("m", 1)

    Enum.each(children, fn pid ->
      ref = Process.monitor(pid)
      send(pid, :release)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end)

    assert {:ok, _} = instant("m", 1)
  end

  test "sample strings use Prometheus decimal and exponent cutoffs" do
    for {number, expected} <- [
          {1.0e21, "1e+21"},
          {1.0e-7, "1e-07"},
          {1.0e-6, "0.000001"},
          {1.0e20, "100000000000000000000"},
          {-0.0, "-0"},
          {1.25, "1.25"}
        ] do
      Memory.reset()
      append("format", [{1, number}])
      assert {:ok, result} = instant("format", 1)
      assert values(result) == [[1.0, expected]]
    end
  end

  test "selectors use the newest sample in a left-open five-minute lookback" do
    append("gauge", [{0, 1}, {10, 2}, {20, 3}])
    assert {:ok, result} = instant("gauge", 15)
    assert values(result) == [[15.0, "2"]]
    assert {:ok, result} = instant("gauge", 320)
    assert values(result) == []
    assert {:ok, result} = instant("gauge offset 10s", 25)
    assert values(result) == [[25.0, "2"]]
    assert {:ok, result} = instant("gauge", 20, "other")
    assert values(result) == []
  end

  test "selector regular expressions are fully anchored and missing labels are empty" do
    append("gauge", [{1, 1}], %{"job" => "api"})
    append("gauge", [{1, 2}], %{"job" => "myapi"})
    assert {:ok, result} = instant(~s(gauge{job=~"api",missing=""}), 1)
    assert values(result) == [[1.0, "1"]]
    assert {:ok, result} = instant(~s(gauge{job!~"api"}), 1)
    assert values(result) == [[1.0, "2"]]
  end

  test "rates extrapolate, correct resets, and preserve evaluation timestamps" do
    append("requests_total", [{0, 100}, {10, 110}, {20, 120}, {30, 5}])
    assert {:ok, result} = instant("rate(requests_total[30s])", 30)
    assert values(result) == [[30.0, "0.75"]]
    assert result["data"]["result"] |> hd() |> Map.fetch!("metric") == %{}
    assert {:ok, result} = instant("increase(requests_total[30s])", 30)
    assert values(result) == [[30.0, "22.5"]]
    assert {:ok, result} = instant("irate(requests_total[30s])", 30)
    assert values(result) == [[30.0, "0.5"]]
    assert {:ok, result} = instant("delta(requests_total[30s])", 30)
    assert values(result) == [[30.0, "-157.5"]]
  end

  test "rates do not extrapolate counters below zero or across distant boundaries" do
    append("new_total", [{10, 0}, {20, 10}])
    assert {:ok, result} = instant("increase(new_total[30s])", 30)
    assert values(result) == [[30.0, "20"]]
    assert {:ok, result} = instant("increase(new_total[100s])", 100)
    assert values(result) == [[100.0, "15"]]
    assert {:ok, result} = instant("rate(new_total[5s])", 20)
    assert values(result) == []
  end

  test "range functions omit empty buckets and aggregations group per evaluation time" do
    append("gauge", [{10, 2}, {20, 4}], %{"job" => "api", "instance" => "a"})
    append("gauge", [{10, 6}, {20, 8}], %{"job" => "api", "instance" => "b"})
    assert {:ok, result} = instant("sum by (job) (avg_over_time(gauge[20s]))", 20)
    assert result["data"]["result"] == [%{"metric" => %{"job" => "api"}, "value" => [20.0, "10"]}]
    assert {:ok, result} = instant("count(gauge) without(instance)", 20)
    assert result["data"]["result"] == [%{"metric" => %{"job" => "api"}, "value" => [20.0, "2"]}]

    assert {:ok, result} =
             Evaluator.query("sum(gauge)", "acme", %{start_ts_ns: 0, end_ts_ns: 20_000_000_000, step_ns: 10_000_000_000})

    assert result["data"]["resultType"] == "matrix"
    assert result["data"]["result"] == [%{"metric" => %{}, "values" => [[10.0, "8"], [20.0, "12"]]}]
  end

  test "each supported over-time function and vector aggregation folds real values" do
    append("gauge", [{10, 2}, {20, 4}], %{"instance" => "a"})
    append("gauge", [{10, 6}, {20, 8}], %{"instance" => "b"})

    for {op, expected} <- [{"sum", "12"}, {"avg", "6"}, {"min", "4"}, {"max", "8"}, {"count", "2"}] do
      assert {:ok, result} = instant("#{op}(gauge)", 20)
      assert values(result) == [[20.0, expected]]
    end

    for {op, expected} <- [
          {"sum", ["6", "14"]},
          {"avg", ["3", "7"]},
          {"min", ["2", "6"]},
          {"max", ["4", "8"]},
          {"count", ["2", "2"]}
        ] do
      assert {:ok, result} = instant("#{op}_over_time(gauge[20s])", 20)
      assert values(result) == Enum.map(expected, &[20.0, &1])
    end
  end

  test "instant and range evaluation agree at every step, including counter reset and offset" do
    append("requests_total", [{0, 100}, {10, 110}, {20, 120}, {30, 5}])
    opts = %{start_ts_ns: 10_000_000_000, end_ts_ns: 40_000_000_000, step_ns: 10_000_000_000}
    query = "sum(rate(requests_total[30s] offset 10s))"
    assert {:ok, matrix} = Evaluator.query(query, "acme", opts)

    expected =
      for time <- [10, 20, 30, 40],
          {:ok, vector} = instant(query, time),
          [_, value] <- values(vector),
          do: [time * 1.0, value]

    assert matrix["data"]["result"] == [%{"metric" => %{}, "values" => expected}]
  end

  test "same series hash does not merge different label sets; overlapping retries deduplicate" do
    append("gauge", [{1, 1}, {1, 1}], %{"instance" => "a"})
    append("gauge", [{1, 2}], %{"instance" => "b"})
    assert {:ok, result} = instant("sum(gauge)", 1)
    assert values(result) == [[1.0, "3"]]
    append("gauge", [{1, 5}], %{"instance" => "a"})
    assert {:ok, result} = instant("gauge", 1)
    assert values(result) == [[1.0, "5"], [1.0, "2"]]
    assert result["warnings"] == ["Conflicting samples at the same timestamp were resolved using the maximum value."]
    append("gauge", [{20, 9}], %{"instance" => "a"})
    assert {:ok, result} = instant(~s/gauge{instance="a"}/, 30)
    assert values(result) == [[30.0, "9"]]
  end

  test "invalid times and excessive step counts fail before scanning" do
    for opts <- [
          %{start_ts_ns: 0},
          %{step_ns: 1, start_ts_ns: 0},
          %{step_ns: 0},
          %{end_ts_ns: "bad"},
          %{step_ns: 1, start_ts_ns: 0, end_ts_ns: 11_000},
          %{step_ns: 1, start_ts_ns: 10, end_ts_ns: 0}
        ] do
      assert {:error, _} = Evaluator.query("gauge", "acme", opts)
    end
  end

  test "result points count only the returned points; intermediates bound the points held at once" do
    # Ten counters c_i = i * t, so each rate is i/s and their sum is 55.
    for i <- 1..10, do: append("c", Enum.map(0..9, &{&1 * 10, &1 * 10 * i}), %{"i" => "#{i}"})
    opts = %{start_ts_ns: 30_000_000_000, end_ts_ns: 90_000_000_000, step_ns: 10_000_000_000}

    # sum() folds each rate() series as it is computed, so it holds its 7
    # (group, step) states, not 10 series x 7 steps = 70 points. Counting
    # every point produced would need 77, and counting intermediates as
    # results 70.
    Pulse.Runtime.put_env(:pulse, Evaluator, max_result_points: 7, max_materialized_samples: 7)
    assert {:ok, result} = Evaluator.query("sum(rate(c[30s]))", "acme", opts)
    assert [%{"values" => values}] = result["data"]["result"]
    assert Enum.map(values, &List.last/1) == List.duplicate("55", 7)

    Pulse.Runtime.put_env(:pulse, Evaluator, max_result_points: 6, max_materialized_samples: 70)
    assert {:error, :query_result_limit} = Evaluator.query("sum(rate(c[30s]))", "acme", opts)

    Pulse.Runtime.put_env(:pulse, Evaluator, max_result_points: 7, max_materialized_samples: 6)
    assert {:error, :query_intermediate_limit} = Evaluator.query("sum(rate(c[30s]))", "acme", opts)

    # Without a fusable source the inner result is held: 70 points.
    Pulse.Runtime.put_env(:pulse, Evaluator, max_result_points: 7, max_materialized_samples: 69)
    assert {:error, :query_intermediate_limit} = Evaluator.query("sum(rate(c[30s]) * 1)", "acme", opts)

    # Both operands of a binary operation are held at once: 70 + 70.
    Pulse.Runtime.put_env(:pulse, Evaluator, max_result_points: 70, max_materialized_samples: 139)
    assert {:error, :query_intermediate_limit} = Evaluator.query("rate(c[30s]) + rate(c[20s])", "acme", opts)
    Pulse.Runtime.put_env(:pulse, Evaluator, max_result_points: 70, max_materialized_samples: 140)
    assert {:ok, _} = Evaluator.query("rate(c[30s]) + rate(c[20s])", "acme", opts)
  end

  test "topk over histogram_quantile holds the summed buckets, not every pod's rates" do
    # Two routes x three buckets x four pods: rate() yields 24 series, the
    # sum by (path, le) 6. Pod p adds p * n per 10 s to a bucket of count n,
    # so /a's buckets hold 1:2:3 of its observations and /b's 1:3:3.
    counts = %{"/a" => [{"1", 1}, {"2", 2}, {"+Inf", 3}], "/b" => [{"1", 1}, {"2", 3}, {"+Inf", 3}]}

    for {path, buckets} <- counts, {le, n} <- buckets, pod <- 1..4 do
      append("d_bucket", Enum.map(0..9, &{&1 * 10, &1 * n * pod}), %{"path" => path, "le" => le, "pod" => "#{pod}"})
    end

    opts = %{start_ts_ns: 30_000_000_000, end_ts_ns: 90_000_000_000, step_ns: 10_000_000_000}
    query = "topk(1, histogram_quantile(0.5, sum by (path, le) (rate(d_bucket[30s]))))"

    # 6 summed series x 7 steps = 42 held, under the 24 x 7 = 168 rate points.
    Pulse.Runtime.put_env(:pulse, Evaluator, max_materialized_samples: 84)
    assert {:ok, result} = Evaluator.query(query, "acme", opts)
    assert [%{"metric" => metric, "values" => values}] = result["data"]["result"]
    # /a's median falls halfway into (1, 2]: 1.5; /b's a quarter in: 1.25.
    assert metric == %{"path" => "/a"}
    assert length(values) == 7
    for [_, value] <- values, do: assert_in_delta(String.to_float(value), 1.5, 1.0e-9)
  end

  test "sample, work, and result limits return errors instead of partial aggregates" do
    append("gauge", [{10, 1}, {20, 2}, {30, 3}])
    Pulse.Runtime.put_env(:pulse, Evaluator, max_samples: 2)
    assert {:error, :query_sample_limit} = instant("sum(gauge)", 30)
    Pulse.Runtime.put_env(:pulse, Evaluator, max_work: 1)
    assert {:error, :query_work_limit} = instant("sum_over_time(gauge[30s])", 30)
    Pulse.Runtime.put_env(:pulse, Evaluator, max_result_points: 1)

    assert {:error, :query_result_limit} =
             Evaluator.query("gauge", "acme", %{
               start_ts_ns: 20_000_000_000,
               end_ts_ns: 30_000_000_000,
               step_ns: 10_000_000_000
             })
  end
end
