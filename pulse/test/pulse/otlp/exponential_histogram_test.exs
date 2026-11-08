defmodule Pulse.OTLP.ExponentialHistogramTest do
  use Pulse.Test.Case, async: true

  alias Pulse.OTLP.Metrics
  alias Pulse.Test.OTLPMetricFixture, as: Fixture

  defp metric(point, temporality \\ 2) do
    %{
      "name" => "latency",
      "exponentialHistogram" => %{"aggregationTemporality" => temporality, "dataPoints" => [point]}
    }
  end

  defp point(fields) do
    Map.merge(
      %{"timeUnixNano" => "1700000000000000000", "startTimeUnixNano" => "1690000000000000000"},
      fields
    )
  end

  defp decode_both(metrics) do
    payload = Fixture.payload(metrics)
    json = Metrics.decode(payload)
    assert json == Metrics.decode_protobuf(Fixture.protobuf(payload))
    json
  end

  defp rows(samples) do
    Enum.map(samples, fn sample ->
      {sample.labels["__name__"], sample.labels["le"], sample.value}
    end)
  end

  test "projects negative, zero and positive buckets to cumulative classic buckets" do
    point =
      point(%{
        "count" => "7",
        "sum" => 3.5,
        "scale" => 0,
        "zeroCount" => "1",
        "positive" => %{"offset" => 0, "bucketCounts" => ["2", "3"]},
        "negative" => %{"offset" => 0, "bucketCounts" => ["1"]}
      })

    assert {:ok, samples, 0} = decode_both([metric(point)])

    assert rows(samples) == [
             {"latency_bucket", "-1", 1.0},
             {"latency_bucket", "0", 2.0},
             {"latency_bucket", "2", 4.0},
             {"latency_bucket", "4", 7.0},
             {"latency_bucket", "+Inf", 7.0},
             {"latency_count", nil, 7.0},
             {"latency_sum", nil, 3.5}
           ]

    [first | _] = samples
    source = first.otlp["point"]
    assert source["kind"] == "exponentialHistogram"
    assert source["scale"] == 0
    assert source["positive"] == %{"offset" => 0, "bucketCounts" => ["2", "3"]}
    assert source["count"] == "7"
  end

  test "fine scales are downscaled to the shared grid, keeping the original in the envelope" do
    counts = List.duplicate("1", 8)

    point =
      point(%{"count" => "8", "scale" => 5, "positive" => %{"offset" => 32, "bucketCounts" => counts}})

    assert {:ok, samples, 0} = decode_both([metric(point)])

    # Scale 5 indices 32..39 merge pairwise-twice into scale 3 indices 8 and 9.
    assert [{_, upper_a, 4.0}, {_, upper_b, 8.0} | _] =
             samples |> rows() |> Enum.reject(fn {_, le, _} -> le in [nil, "0", "+Inf"] end)

    assert String.to_float(upper_a) == :math.pow(2, 9 / 8)
    assert String.to_float(upper_b) == :math.pow(2, 10 / 8)
    assert hd(samples).otlp["point"]["scale"] == 5
  end

  test "wide distributions shrink further instead of exceeding the bucket ceiling" do
    counts = List.duplicate("1", 400)
    point = point(%{"count" => "400", "scale" => 3, "positive" => %{"offset" => 0, "bucketCounts" => counts}})

    assert {:ok, samples, 0} = decode_both([metric(point)])
    buckets = Enum.filter(samples, &(&1.labels["__name__"] == "latency_bucket"))
    assert length(buckets) <= 162
    assert List.last(buckets).value == 400.0
  end

  test "inconsistent, out-of-range and unspecified-temporality points are rejected, not invented" do
    bad = [
      point(%{"count" => "3", "scale" => 0, "positive" => %{"bucketCounts" => ["1"]}}),
      point(%{"count" => "1", "scale" => 21, "positive" => %{"bucketCounts" => ["1"]}}),
      point(%{"count" => "1", "scale" => 0, "zeroThreshold" => -1.0, "zeroCount" => "1"})
    ]

    for point <- bad, do: assert({:ok, [], 1} = decode_both([metric(point)]))

    unspecified = point(%{"count" => "1", "scale" => 0, "zeroCount" => "1"})
    assert {:ok, [], 1} = decode_both([metric(unspecified, 0)])
  end

  test "delta points project per point and record their temporality" do
    delta = point(%{"count" => "1", "scale" => 0, "zeroCount" => "1"})
    assert {:ok, [first | _], 0} = decode_both([metric(delta, 1)])
    assert first.otlp["point"]["aggregationTemporality"] == 1
  end

  test "an empty population still proves its +Inf bucket and count" do
    assert {:ok, samples, 0} = decode_both([metric(point(%{"count" => "0", "scale" => 0}))])

    assert rows(samples) == [
             {"latency_bucket", "0", 0.0},
             {"latency_bucket", "+Inf", 0.0},
             {"latency_count", nil, 0.0}
           ]
  end
end
