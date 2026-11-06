defmodule Pulse.OTLP.DeltaMetricsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.OTLP.Metrics
  alias Pulse.Test.OTLPMetricFixture, as: Fixture

  defp decode_both(metrics) do
    payload = Fixture.payload(metrics)
    json = Metrics.decode(payload)
    assert json == Metrics.decode_protobuf(Fixture.protobuf(payload))
    json
  end

  test "delta sums are stored as reported, never accumulated or named as counters" do
    sum = %{
      "name" => "requests",
      "sum" => %{"aggregationTemporality" => 1, "isMonotonic" => true, "dataPoints" => [Fixture.point(5.0)]}
    }

    assert {:ok, [sample], 0} = decode_both([sum])
    assert sample.labels["__name__"] == "requests"
    assert sample.value == 5.0
    assert sample.otlp["point"]["aggregationTemporality"] == 1
    assert sample.otlp["point"]["isMonotonic"] == true
  end

  test "cumulative monotonic sums keep the _total counter name" do
    sum = %{
      "name" => "requests",
      "sum" => %{"aggregationTemporality" => 2, "isMonotonic" => true, "dataPoints" => [Fixture.point(5.0)]}
    }

    assert {:ok, [sample], 0} = decode_both([sum])
    assert sample.labels["__name__"] == "requests_total"
  end

  test "monotonic deltas must still be non-negative" do
    sum = %{
      "name" => "requests",
      "sum" => %{"aggregationTemporality" => 1, "isMonotonic" => true, "dataPoints" => [Fixture.point(-1.0)]}
    }

    assert {:ok, [], 1} = decode_both([sum])
  end

  test "delta explicit histograms project their buckets for the reported interval" do
    point = %{
      "timeUnixNano" => "1700000000000000000",
      "count" => "3",
      "sum" => 1.5,
      "bucketCounts" => ["1", "2"],
      "explicitBounds" => [0.5]
    }

    histogram = %{"name" => "latency", "histogram" => %{"aggregationTemporality" => 1, "dataPoints" => [point]}}

    assert {:ok, samples, 0} = decode_both([histogram])

    assert Enum.map(samples, &{&1.labels["__name__"], &1.labels["le"], &1.value}) == [
             {"latency_bucket", "0.5", 1.0},
             {"latency_bucket", "+Inf", 3.0},
             {"latency_count", nil, 3.0},
             {"latency_sum", nil, 1.5}
           ]

    assert hd(samples).otlp["point"]["aggregationTemporality"] == 1
  end
end
