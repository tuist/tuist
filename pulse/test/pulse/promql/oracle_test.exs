defmodule Pulse.PromQL.OracleTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.Memory
  alias Pulse.Test.NativeQueryStorage

  @directory Path.expand("../../fixtures/promql", __DIR__)
  @math_queries Enum.map(~w(ceil sqrt exp ln log2 log10), &"#{&1}(math_input)")

  setup do
    bytes = File.read!(Path.join(@directory, "conformance.json"))
    fixture = JSON.decode!(bytes)
    verified = Path.join(@directory, "verified-results.json") |> File.read!() |> JSON.decode!()
    assert verified["oracle"] == "Prometheus promtool 3.5.0"
    assert verified["fixture_sha256"] == Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

    for series <- fixture["series"] do
      records =
        series["values"]
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {"_", _} ->
            []

          {value, index} ->
            [
              %MetricSample{
                labels: series["labels"],
                value: value(value),
                timestamp_ns: index * fixture["interval_seconds"] * 1_000_000_000
              }
            ]
        end)

      :ok = Memory.append(:metrics, "oracle", records)
    end

    {:ok, cases: verified["cases"]}
  end

  for adapter <- [Memory, NativeQueryStorage] do
    # Keep all 946 oracle cases per adapter without accumulating every query's
    # scheduler/native wait under one test's normal 60-second deadline.
    for batch <- 0..9 do
      @tag oracle_batch: batch
      test "independently verified numerical, label, offset and stale cases through #{inspect(adapter)}, batch #{batch + 1}/10",
           ctx do
        Pulse.Runtime.put_env(:pulse, Pulse.Storage, adapter: unquote(adapter))
        assert length(ctx.cases) == 946

        for test <- Enum.slice(ctx.cases, ctx.oracle_batch * 100, 100) do
          assert {:ok, result} = Evaluator.query(test["expr"], "oracle", %{end_ts_ns: test["seconds"] * 1_000_000_000})
          assert_result(result["data"], test["data"], test["expr"])
        end
      end
    end

    test "basic math range steps match the verified instant cases through #{inspect(adapter)}", ctx do
      Pulse.Runtime.put_env(:pulse, Pulse.Storage, adapter: unquote(adapter))

      for expr <- @math_queries do
        assert {:ok, %{"data" => %{"resultType" => "matrix", "result" => series}}} =
                 Evaluator.query(expr, "oracle", %{start_ts_ns: 0, end_ts_ns: 720_000_000_000, step_ns: 30_000_000_000})

        for test <- ctx.cases, test["expr"] == expr, test["seconds"] <= 720 do
          entries =
            for sample <- series,
                [time, value] <- sample["values"],
                time == test["seconds"],
                do: %{"metric" => sample["metric"], "value" => [time, value]}

          assert_result(%{"resultType" => "vector", "result" => entries}, test["data"], expr)
        end
      end
    end
  end

  test "subquery steps and materialized points share query budgets" do
    assert {:error, :query_work_limit} =
             Evaluator.query("sum_over_time(gauge[1d:1s])", "oracle", %{end_ts_ns: 600_000_000_000})

    Pulse.Runtime.put_env(:pulse, Evaluator, max_materialized_samples: 2)

    assert {:error, :query_intermediate_limit} =
             Evaluator.query("sum_over_time(gauge[5m:30s])", "oracle", %{end_ts_ns: 600_000_000_000})
  end

  test "large epoch timestamp and time comparisons use exact millisecond conversion" do
    ns = 1_700_000_000_123_000_000

    :ok =
      Memory.append(:metrics, "epoch", [%MetricSample{labels: %{"__name__" => "epoch"}, value: 1.0, timestamp_ns: ns}])

    for expression <- ["timestamp(epoch)", "time()", "timestamp(epoch) == 1700000000.123"] do
      assert {:ok, result} = Evaluator.query(expression, "epoch", %{end_ts_ns: ns})
      data = result["data"]
      points = if data["resultType"] == "scalar", do: [data["result"]], else: Enum.map(data["result"], & &1["value"])
      assert [[1_700_000_000.123, "1700000000.123"]] = points
    end
  end

  test "metric-name removal merges disjoint lifetimes but rejects simultaneous label collisions" do
    for {name, time, value} <- [{"a", 0, 1.0}, {"a", 30, :stale}, {"b", 30, 2.0}] do
      :ok =
        Memory.append(:metrics, "rename", [
          %MetricSample{labels: %{"__name__" => name, "job" => "api"}, value: value, timestamp_ns: time * 1_000_000_000}
        ])
    end

    assert {:ok, %{"data" => %{"result" => [%{"metric" => %{"job" => "api"}, "values" => [[+0.0, "1"], [30.0, "2"]]}]}}} =
             Evaluator.query("floor({__name__=~\"a|b\"})", "rename", %{
               start_ts_ns: 0,
               end_ts_ns: 30_000_000_000,
               step_ns: 30_000_000_000
             })

    :ok =
      Memory.append(:metrics, "rename", [
        %MetricSample{labels: %{"__name__" => "b", "job" => "api"}, value: 2.0, timestamp_ns: 0}
      ])

    assert {:error, :duplicate_result_label_sets} =
             Evaluator.query("timestamp({__name__=~\"a|b\"})", "rename", %{end_ts_ns: 0})
  end

  defp assert_result(actual, expected, expr) when expr in @math_queries do
    assert actual["resultType"] == expected["resultType"]
    assert Enum.map(actual["result"], & &1["metric"]) == Enum.map(expected["result"], & &1["metric"])

    for {a, b} <- Enum.zip(actual["result"], expected["result"]) do
      [time, value] = a["value"]
      assert [^time, expected_value] = b["value"]
      assert_math_value(value, expected_value)
    end
  end

  defp assert_result(actual, expected, expr), do: assert(actual == expected, expr)

  defp assert_math_value(value, value), do: :ok

  defp assert_math_value(actual, expected) do
    # Platform libm and Go can differ by one ULP. Labels, timestamps, signed
    # zero and nonfinite classes remain exact, not relative-tolerance matches.
    {a, ""} = Float.parse(actual)
    {b, ""} = Float.parse(expected)
    refute a == 0 or b == 0, "#{actual} != #{expected}"
    <<a_bits::64>> = <<a::float-64>>
    <<b_bits::64>> = <<b::float-64>>
    assert abs(a_bits - b_bits) <= 1, "#{actual} != #{expected}"
  end

  defp value("stale"), do: :stale
  defp value("NaN"), do: :nan
  defp value("Inf"), do: :infinity
  defp value("-Inf"), do: :negative_infinity
  defp value(number), do: number * 1.0
end
