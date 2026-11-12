defmodule Pulse.OTLP.MetricsProtocolTest do
  use Pulse.Test.Case, async: true

  alias Pulse.IngestLimits
  alias Pulse.OTLP.Metrics
  alias Pulse.Runtime
  alias Pulse.Test.OTLPMetricFixture, as: Fixture

  test "independent protoc and Google JSON produce the same complete typed scalar records" do
    assert {:ok, json, 0} = Metrics.decode(Fixture.json())
    assert {:ok, wire, 0} = Metrics.decode_protobuf(Fixture.protobuf())
    assert :erlang.term_to_binary(json, [:deterministic]) == :erlang.term_to_binary(wire, [:deterministic])
    assert length(json) == 7
    [zero, integer, nan, infinity, stale, sum, _] = json
    assert <<zero.value::float-64>> == <<0x8000000000000000::64>>
    assert zero.labels["__name__"] == "cpu_utilization"
    [exemplar] = zero.otlp["point"]["exemplars"]
    assert exemplar["traceId"] == "30313233343536373839616263646566"
    assert exemplar["spanId"] == "6465616462656566"
    assert <<exemplar["asDouble"]::float-64>> == <<0x8000000000000000::64>>

    assert exemplar["filteredAttributes"] == [
             %{"key" => "request.id", "value" => %{"stringValue" => "fixture-request"}}
           ]

    assert zero.labels["job"] == "example/example-api"
    assert zero.labels["instance"] == "pod-1"
    assert zero.labels["http_method"] == "GET"
    assert zero.otlp["metric"]["name"] == "cpu.utilization"
    assert zero.otlp["metric"]["metadata"] == [%{"key" => "category", "value" => %{"stringValue" => "runtime"}}]
    assert integer.otlp["point"]["asInt"] == "-9223372036854775808"
    assert nan.value == :nan
    assert infinity.value == :infinity
    assert stale.value == :stale
    assert sum.labels["__name__"] == "request_count_total"
    assert sum.otlp["point"]["aggregationTemporality"] == 2
    assert sum.otlp["point"]["startTimeUnixNano"] == "1700000000000000000"
    assert zero.otlp["scope"]["droppedAttributesCount"] == 2
    assert zero.otlp["resource"]["attributes"] |> Enum.any?(&(&1["key"] == "deployment.environment.name"))
  end

  test "actual Python SDK 1.40 HTTP-emitted wire retains its sampled counter exemplar" do
    wire = File.read!("test/fixtures/otlp/python-sdk-metrics.protobuf")
    assert {:ok, records, 0} = Metrics.decode_protobuf(wire)
    assert length(records) == 2
    counter = Enum.find(records, &(&1.labels["__name__"] == "sdk_requests_total"))
    gauge = Enum.find(records, &(&1.labels["__name__"] == "sdk_temperature"))
    assert counter.value == 7.0
    assert counter.labels["instance"] == "synthetic-python-producer"
    assert counter.otlp["point"]["isMonotonic"] == true
    assert counter.otlp["scope"]["name"] == "fixture.python"
    [exemplar] = counter.otlp["point"]["exemplars"]
    assert exemplar["asInt"] == "7"
    assert exemplar["traceId"] == "0123456789abcdef0123456789abcdef"
    assert exemplar["spanId"] == "0123456789abcdef"
    assert <<gauge.value::float-64>> == <<0x8000000000000000::64>>
  end

  test "unsupported temporality/types and malformed exemplars reject supplied points rather than invent values" do
    metrics = [
      Fixture.gauge([Fixture.point()]),
      %{"name" => "unspecified", "sum" => %{"aggregationTemporality" => 0, "dataPoints" => [Fixture.point()]}},
      %{"name" => "hist", "histogram" => %{"dataPoints" => [%{}]}},
      %{"name" => "exp", "exponentialHistogram" => %{"dataPoints" => [%{}]}},
      %{"name" => "summary", "summary" => %{"dataPoints" => [%{}]}},
      Fixture.gauge([Map.put(Fixture.point(), "exemplars", [%{"timeUnixNano" => "0", "asDouble" => 1.0}])])
    ]

    payload = Fixture.payload(metrics)
    assert {:ok, [_], 5} = Metrics.decode(payload)
    assert {:ok, [_], 5} = Metrics.decode_protobuf(Fixture.protobuf(payload))
  end

  test "malformed containers and metadata reject requests; malformed points reject only themselves" do
    for payload <- [%{"resourceMetrics" => %{}}, %{"resourceMetrics" => [false]}, Fixture.payload([%{}])] do
      assert {:error, :invalid_otlp} = Metrics.decode(payload)
    end

    assert {:ok, [], 0} = Metrics.decode(%{"resourceMetrics" => nil})

    points = [
      Fixture.point(),
      %{"asInt" => "1"},
      Map.put(Fixture.point(), "asInt", "1"),
      Map.put(Fixture.point(), "attributes", [
        %{"key" => "a.b", "value" => %{"stringValue" => "a"}},
        %{"key" => "a_b", "value" => %{"stringValue" => "b"}}
      ])
    ]

    assert {:ok, [_], 3} = Metrics.decode(Fixture.payload([Fixture.gauge(points)]))
    # JSON cannot contain two populated oneof members. On the protobuf wire,
    # the later asInt legitimately replaces asDouble (public oracle coverage
    # lives in WireProtocolTest).
    assert {:ok, [_, selected], 2} = Metrics.decode_protobuf(Fixture.protobuf(Fixture.payload([Fixture.gauge(points)])))
    assert selected.otlp["point"]["asInt"] == "1"
    refute Map.has_key?(selected.otlp["point"], "asDouble")

    malformed = %{
      "resourceMetrics" => [
        %{"resource" => %{"attributes" => [%{"key" => "dup", "value" => %{}}, %{"key" => "dup", "value" => %{}}]}}
      ]
    }

    assert {:error, :invalid_otlp} = Metrics.decode(malformed)
  end

  test "total record/node budgets include unsupported points and malformed oneof members" do
    Runtime.put_env(:pulse, IngestLimits, max_records: 1)
    payload = Fixture.payload([%{"name" => "hist", "histogram" => %{"dataPoints" => [%{}, %{}]}}])
    assert {:error, :too_many_records} = Metrics.decode(payload)
    assert {:error, :too_many_records} = Metrics.decode_protobuf(Fixture.protobuf(payload))
    Runtime.put_env(:pulse, IngestLimits, max_otlp_nodes: 10)
    assert {:error, :too_many_otlp_nodes} = Metrics.decode(Fixture.json())
    assert {:error, :too_many_otlp_nodes} = Metrics.decode_protobuf(Fixture.protobuf())
  end

  test "always-on exemplars outside spans retain zero context IDs without dropping the scalar" do
    exemplar = %{
      "timeUnixNano" => "1",
      "asDouble" => 1.0,
      "traceId" => String.duplicate("0", 32),
      "spanId" => String.duplicate("0", 16)
    }

    payload = Fixture.payload([Fixture.gauge([Map.put(Fixture.point(), "exemplars", [exemplar])])])

    for result <- [Metrics.decode(payload), Metrics.decode_protobuf(Fixture.protobuf(payload))] do
      assert {:ok, [sample], 0} = result
      assert sample.value == 1.5
      [stored] = sample.otlp["point"]["exemplars"]
      assert stored["traceId"] == exemplar["traceId"]
      assert stored["spanId"] == exemplar["spanId"]
    end
  end

  test "cumulative non-monotonic sums remain unsuffixed and flags retain source numeric values" do
    points = [
      %{"timeUnixNano" => "2", "asInt" => "0"},
      %{"timeUnixNano" => "3", "asDouble" => "-Infinity"},
      %{"timeUnixNano" => "4", "asDouble" => -12.0, "flags" => 1}
    ]

    sum = %{
      "name" => "balance",
      "sum" => %{"aggregationTemporality" => 2, "isMonotonic" => false, "dataPoints" => points}
    }

    payload = Fixture.payload([sum])

    for result <- [Metrics.decode(payload), Metrics.decode_protobuf(Fixture.protobuf(payload))] do
      assert {:ok, records, 0} = result
      assert Enum.map(records, & &1.value) == [0.0, :negative_infinity, :stale]
      assert Enum.all?(records, &(&1.labels["__name__"] == "balance"))
      assert List.last(records).otlp["point"]["asDouble"] == -12.0
    end

    monotonic = put_in(sum, ["sum", "isMonotonic"], true)
    assert {:ok, [_, stale], 1} = Metrics.decode(Fixture.payload([monotonic]))
    assert stale.value == :stale
  end

  test "metadata repetition and oversized numeric spellings reject the complete request" do
    payload =
      Fixture.payload([
        Fixture.gauge([Map.put(Fixture.point(), "asDouble", String.duplicate("1", 1025)), Fixture.point()])
      ])

    assert {:error, :attributes_too_large} = Metrics.decode(payload)
    points = List.duplicate(Fixture.point(), 4000)

    payload = %{
      "resourceMetrics" => [
        %{
          "resource" => %{
            "attributes" => [%{"key" => "repeated", "value" => %{"stringValue" => String.duplicate("\\\"", 2000)}}]
          },
          "scopeMetrics" => [%{"metrics" => [Fixture.gauge(points)]}]
        }
      ]
    }

    assert {:error, :payload_too_large} = Metrics.decode(payload)
    assert {:error, :payload_too_large} = Metrics.decode_protobuf(Fixture.protobuf(payload))
  end
end
