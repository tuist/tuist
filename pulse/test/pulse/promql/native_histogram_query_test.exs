defmodule Pulse.PromQL.NativeHistogramQueryTest do
  # Native histograms through PromQL: selection, range functions,
  # aggregation, arithmetic, histogram functions and Prometheus' JSON shape.
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.MetricSample
  alias Pulse.Record.NativeHistogram
  alias Pulse.Storage

  @s 1_000_000_000

  # A counter histogram observing one value of 0.75 per second: every
  # observation lands in schema-0 bucket 0, (0.5, 1].
  defp histogram(count),
    do: %NativeHistogram{
      schema: 0,
      count: count * 1.0,
      sum: count * 0.75,
      positive_spans: [{0, 1}],
      positive_buckets: [count * 1.0]
    }

  defp sample(labels, seconds, h), do: %MetricSample{labels: labels, timestamp_ns: seconds * @s, histogram: h}

  setup do
    tenant = "native-#{System.unique_integer([:positive])}"

    samples =
      for pod <- ["a", "b"], seconds <- [0, 15, 30, 45, 60] do
        sample(%{"__name__" => "latency_seconds", "pod" => pod}, seconds, histogram(seconds))
      end

    floats =
      for seconds <- [0, 30, 60],
          do: %MetricSample{labels: %{"__name__" => "up"}, timestamp_ns: seconds * @s, value: 1.0}

    assert :ok = Storage.append(:metrics, tenant, samples ++ floats)
    {:ok, tenant: tenant}
  end

  defp instant(query, tenant), do: Evaluator.query(query, tenant, %{end_ts_ns: 60 * @s})

  test "an instant selector returns histograms in Prometheus' shape", %{tenant: tenant} do
    assert {:ok, %{"data" => %{"resultType" => "vector", "result" => [a, _b]}}} =
             instant(~s(latency_seconds{pod=~"a|b"}), tenant)

    assert a == %{
             "metric" => %{"__name__" => "latency_seconds", "pod" => "a"},
             "histogram" => [60.0, %{"count" => "60", "sum" => "45", "buckets" => [[0, "0.5", "1", "60"]]}]
           }
  end

  test "rate, sum and arithmetic keep histograms; histogram functions return floats", %{tenant: tenant} do
    # One observation per second, up to the rounding of Prometheus'
    # extrapolation factor (60 / 45 / 60 seconds, times 45).
    assert {:ok, %{"data" => %{"result" => [%{"histogram" => [60.0, rate]}, _]}}} =
             instant("rate(latency_seconds[1m])", tenant)

    assert rate == %{
             "count" => "0.9999999999999999",
             "sum" => "0.7499999999999999",
             "buckets" => [[0, "0.5", "1", "0.9999999999999999"]]
           }

    assert {:ok, %{"data" => %{"result" => [%{"metric" => %{}, "histogram" => [60.0, sum]}]}}} =
             instant("sum(rate(latency_seconds[1m]))", tenant)

    assert sum["count"] == "1.9999999999999998"

    assert {:ok, %{"data" => %{"result" => [%{"histogram" => [60.0, %{"count" => "1.9999999999999998"}]}, _]}}} =
             instant("rate(latency_seconds[1m]) * 2", tenant)

    for {query, expected} <- [
          {"histogram_count(rate(latency_seconds[1m]))", "0.9999999999999999"},
          {"histogram_sum(rate(latency_seconds[1m]))", "0.7499999999999999"},
          {"histogram_avg(rate(latency_seconds[1m]))", "0.75"},
          {"histogram_fraction(0, 1, rate(latency_seconds[1m]))", "1"}
        ] do
      assert {:ok, %{"data" => %{"result" => [%{"metric" => metric, "value" => [60.0, ^expected]}, _]}}} =
               instant(query, tenant),
             query

      refute Map.has_key?(metric, "__name__")
    end

    assert {:ok, %{"data" => %{"result" => [%{"value" => [60.0, q]}, _]}}} =
             instant("histogram_quantile(0.5, rate(latency_seconds[1m]))", tenant)

    {q, ""} = Float.parse(q)
    assert q > 0.5 and q < 1
  end

  test "float-only operations leave histograms out and mixed vectors keep floats", %{tenant: tenant} do
    assert {:ok, %{"data" => %{"result" => []}}} = instant("max_over_time(latency_seconds[1m])", tenant)
    assert {:ok, %{"data" => %{"result" => []}}} = instant("abs(latency_seconds)", tenant)
    assert {:ok, %{"data" => %{"result" => []}}} = instant("latency_seconds > 1", tenant)

    for {name, expected} <- [
          {"ceil", "1"},
          {"sqrt", "1"},
          {"exp", "2.718281828459045"},
          {"ln", "0"},
          {"log2", "0"},
          {"log10", "0"}
        ] do
      assert {:ok, %{"data" => %{"result" => []}}} = instant("#{name}(latency_seconds)", tenant)

      assert {:ok, %{"data" => %{"result" => [%{"metric" => %{}, "value" => [60.0, ^expected]}]}}} =
               instant(~s<#{name}({__name__=~"latency_seconds|up"})>, tenant)
    end

    assert {:ok, %{"data" => %{"result" => [%{"value" => [60.0, "4"]}, _]}}} =
             instant("count_over_time(latency_seconds[1m])", tenant)

    assert {:ok, %{"data" => %{"result" => [%{"value" => [60.0, "3"]}]}}} =
             instant(~s<count({__name__=~"latency_seconds|up"})>, tenant)
  end

  test "range queries report histograms under `histograms`", %{tenant: tenant} do
    assert {:ok, %{"data" => %{"resultType" => "matrix", "result" => [series, _]}}} =
             Evaluator.query(~s(latency_seconds), tenant, %{start_ts_ns: 30 * @s, end_ts_ns: 60 * @s, step_ns: 30 * @s})

    assert Map.keys(series) == ["histograms", "metric"]
    assert [[30.0, %{"count" => "30"}], [60.0, %{"count" => "60"}]] = series["histograms"]
  end
end
