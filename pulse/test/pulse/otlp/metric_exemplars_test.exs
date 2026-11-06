defmodule Pulse.OTLP.MetricExemplarsTest do
  # OTLP exemplars become Prometheus exemplars the way Prometheus' OTLP
  # translator builds them, on the samples it attaches them to.
  use Pulse.Test.Case, async: true

  alias Pulse.OTLP.Metrics
  alias Pulse.Record.Exemplar
  alias Pulse.Test.OTLPMetricFixture, as: Fixture

  @trace "0af7651916cd43dd8448eb211c80319c"
  @span "b7ad6b7169203331"

  defp exemplar(value, attrs \\ [], trace \\ @trace, span \\ @span) do
    %{
      "timeUnixNano" => "1700000000000000000",
      "asDouble" => value,
      "traceId" => trace,
      "spanId" => span,
      "filteredAttributes" => Enum.map(attrs, fn {k, v} -> %{"key" => k, "value" => %{"stringValue" => v}} end)
    }
  end

  test "sum and gauge exemplars carry trace context and filtered attributes" do
    point =
      Map.put(Fixture.point(), "exemplars", [
        exemplar(1.5, [{"http.route", "/a"}]),
        exemplar(2.0, [], "", "0000000000000000")
      ])

    assert {:ok, [sample], 0} = Metrics.decode(Fixture.payload([Fixture.gauge([point])]))

    assert sample.exemplars == [
             %Exemplar{
               labels: %{"trace_id" => @trace, "span_id" => @span, "http_route" => "/a"},
               value: 1.5,
               timestamp_ns: 1_700_000_000_000_000_000
             },
             %Exemplar{labels: %{}, value: 2.0, timestamp_ns: 1_700_000_000_000_000_000}
           ]

    # Typed source exemplars are still kept in the point's envelope.
    assert length(sample.otlp["point"]["exemplars"]) == 2
  end

  test "histogram exemplars go to the first bucket holding their value" do
    histogram = %{
      "name" => "latency",
      "histogram" => %{
        "aggregationTemporality" => 2,
        "dataPoints" => [
          %{
            "timeUnixNano" => "1700000000123456789",
            "count" => "3",
            "sum" => 2.5,
            "explicitBounds" => [0.5, 1.0],
            "bucketCounts" => ["1", "1", "1"],
            "exemplars" => [exemplar(0.2), exemplar(1.0), exemplar(7.0), exemplar("NaN")]
          }
        ]
      }
    }

    assert {:ok, samples, 0} = Metrics.decode(Fixture.payload([histogram]))

    exemplars =
      for %{labels: %{"__name__" => "latency_bucket", "le" => le}} = sample <- samples,
          into: %{},
          do: {le, Enum.map(sample.exemplars || [], & &1.value)}

    assert exemplars == %{"0.5" => [0.2], "1" => [1.0], "+Inf" => [7.0]}
    assert samples |> Enum.reject(&(&1.labels["__name__"] == "latency_bucket")) |> Enum.all?(&is_nil(&1.exemplars))
  end

  test "exemplars over Prometheus' 128-character label limit are kept only in the envelope" do
    long = String.duplicate("a", 200)
    point = Map.put(Fixture.point(), "exemplars", [exemplar(1.0, [{"k", long}])])
    assert {:ok, [sample], 0} = Metrics.decode(Fixture.payload([Fixture.gauge([point])]))
    assert sample.exemplars == nil
    assert [_] = sample.otlp["point"]["exemplars"]
  end
end
