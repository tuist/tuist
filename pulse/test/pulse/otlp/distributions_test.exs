defmodule Pulse.OTLP.DistributionsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.IngestLimits
  alias Pulse.OTLP.JSON
  alias Pulse.OTLP.Metrics
  alias Pulse.OTLP.Metrics.Distribution
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Test.OTLPMetricFixture, as: Fixture
  alias Pulse.Test.OTLPTraceFixture

  @directory Path.expand("../../fixtures/otlp/distributions", __DIR__)

  test "frozen independent producer inputs, library identities and wire captures remain pinned" do
    index = File.read!(Path.join(@directory, "checksums.json"))
    assert sha(index) == "d44328c9424809b01115d78763c3876300659188e233cb11698627dc167ebe98"
    manifest = Pulse.JSON.decode!(index)
    assert map_size(manifest["files"]) == 8

    for {name, expected} <- manifest["files"] do
      assert sha(File.read!(Path.join(@directory, name))) == expected, name
    end

    assert manifest["producer"]["otlp_proto"] == "v1.9.0"
    assert manifest["producer"]["google_protobuf"] == "v1.36.11"
    raw = @directory |> Path.join("generic-protojson.json") |> File.read!() |> JSON.decode!()
    # Generic ProtoJSON uses base64 context IDs, unlike OTLP JSON hex IDs.
    # Do not infer source IDs from the wrong encoding or drop just the exemplar.
    assert {:ok, rows, 1} = Metrics.decode(raw)
    assert length(rows) == 19
    refute Enum.any?(rows, &(&1.otlp["metric"]["name"] == "request.duration"))
  end

  test "public protoc and Google ProtoJSON retain histogram and summary source fields and exact projections" do
    assert {:ok, json, 0} = Metrics.decode(json())
    assert {:ok, wire, 0} = Metrics.decode_protobuf(File.read!(Path.join(@directory, "input.protobuf")))
    assert deterministic(json) == deterministic(wire)
    assert length(json) == 24
    histogram = Enum.filter(json, &(&1.otlp["metric"]["name"] == "request.duration"))

    assert Enum.map(histogram, &{&1.otlp["projection"]["component"], &1.labels["le"], &1.value}) == [
             {"bucket", "1", 1.0},
             {"bucket", "2", 3.0},
             {"bucket", "+Inf", 4.0},
             {"count", nil, 4.0},
             {"sum", nil, 6.0}
           ]

    point = hd(histogram).otlp["point"]
    assert point["bucketCounts"] == ["1", "2", "1"]
    assert point["explicitBounds"] == [1.0, 2.0]
    assert point["min"] == 0.25
    assert point["max"] == 3.5
    assert point["flags"] == 2
    assert point["aggregationTemporality"] == 2
    assert point["startTimeUnixNano"] == "1700000000000000000"
    assert <<hd(point["exemplars"])["asDouble"]::float-64>> == <<0x8000000000000000::64>>
    assert hd(histogram).labels["http_response_status_code"] == "503"
    summary = Enum.filter(json, &(&1.otlp["point"]["kind"] == "summary"))

    assert Enum.map(summary, &{&1.labels["quantile"], &1.value}) == [
             {"0", 1.0},
             {"0.5", 2.0},
             {"0.99", 4.0},
             {nil, 4.0},
             {nil, 10.0}
           ]

    refute Map.has_key?(hd(summary).otlp["point"], "aggregationTemporality")
    large = Enum.find(json, &(&1.labels["__name__"] == "large_count_count"))
    assert large.otlp["point"]["count"] == "18446744073709551615"
    assert large.otlp["point"]["bucketCounts"] == ["18446744073709551615"]
    empty = Enum.filter(json, &(&1.otlp["metric"]["name"] == "empty.histogram"))
    assert length(empty) == 2
    assert Enum.all?(empty, &(&1.value == :stale))
    stale = Enum.filter(json, &(&1.otlp["metric"]["name"] == "stale.values"))
    assert length(stale) == 4
    assert Enum.all?(stale, &(&1.value == :stale))
    assert hd(stale).otlp["point"]["sum"] == "NaN"
    assert hd(stale).otlp["point"]["count"] == "0"
    assert hd(stale).otlp["point"]["bucketCounts"] == ["4", "7"]
    optional = Enum.find(json, &(&1.labels["__name__"] == "optional_zero_sum"))
    assert <<optional.value::float-64>> == <<0x8000000000000000::64>>
    assert <<optional.otlp["point"]["sum"]::float-64>> == <<0x8000000000000000::64>>
    assert optional.otlp["point"]["min"] === 0.0
    assert optional.otlp["point"]["max"] == "NaN"
    zero = Enum.find(json, &(&1.labels["__name__"] == "negative_zero_bucket" and &1.labels["le"] == "-0"))
    assert zero.value == 1.0
    assert zero.otlp["point"]["bucketCounts"] == ["1", "0"]
    assert <<zero.otlp["point"]["min"]::float-64>> == <<0x8000000000000000::64>>
  end

  test "mixed packed and unpacked primitive occurrences concatenate without losing counts or bounds" do
    alias OTLPTraceFixture, as: Wire

    timestamp = 1_700_000_000_123_456_789

    point = [
      <<0x19, timestamp::little-64, 0x21, 4::little-64, 0x29, 6.0::little-float-64>>,
      Wire.bytes(6, <<1::little-64>>),
      <<0x31, 2::little-64>>,
      Wire.bytes(6, <<1::little-64>>),
      Wire.bytes(7, <<>>),
      <<0x39, 1.0::little-float-64>>,
      Wire.bytes(7, <<2.0::little-float-64>>)
    ]

    metric =
      IO.iodata_to_binary([
        Wire.bytes(1, "histogram"),
        Wire.bytes(9, IO.iodata_to_binary([Wire.bytes(1, IO.iodata_to_binary(point)), <<0x10, 2>>]))
      ])

    wire = Wire.bytes(1, Wire.bytes(2, Wire.bytes(2, metric)))
    assert {:ok, actual, 0} = Metrics.decode_protobuf(wire)
    assert {:ok, expected, 0} = Metrics.decode(Fixture.payload([histogram()]))
    assert deterministic(actual) == deterministic(expected)
  end

  test "all source metadata survives native storage and repeated encode/decode" do
    assert {:ok, rows, 0} = Metrics.decode(json())
    assert {:ok, blob, _, _} = S3.encode_segment(:metrics, rows)
    assert {:ok, first} = S3.decode_segment(:metrics, blob, nil, nil, [])
    assert {:ok, blob, _, _} = S3.encode_segment(:metrics, first)
    assert {:ok, second} = S3.decode_segment(:metrics, blob, nil, nil, [])
    assert deterministic(first) == deterministic(second)
    expected = Enum.sort_by(rows, & &1.labels)
    actual = second |> Enum.map(&%{&1 | series_id: nil}) |> Enum.sort_by(& &1.labels)
    assert deterministic(expected) == deterministic(actual)
    assert {:ok, _} = NIF.encode_metric_samples(second)
  end

  test "malformed distributions and unsupported temporality reject SOURCE points, not individual projected samples" do
    bad = [
      histogram(%{"count" => "5"}),
      histogram(%{"explicitBounds" => [2.0, 1.0]}),
      histogram(%{"bucketCounts" => [1, 1]}),
      histogram(%{"explicitBounds" => ["NaN", 2.0]}),
      histogram(%{"attributes" => [%{"key" => "le", "value" => %{"stringValue" => "collision"}}]}),
      put_in(histogram(), ["histogram", "aggregationTemporality"], 0),
      summary(%{"quantileValues" => [%{"quantile" => 1.1, "value" => 2.0}]}),
      summary(%{"quantileValues" => [%{"quantile" => 0.5, "value" => -1.0}]}),
      summary(%{"quantileValues" => [%{"quantile" => 0.5}, %{"quantile" => 0.5}]}),
      summary(%{"count" => 0, "sum" => 1.0})
    ]

    payload = Fixture.payload([histogram() | bad])

    for result <- [Metrics.decode(payload), Metrics.decode_protobuf(Fixture.protobuf(payload))] do
      assert {:ok, rows, 10} = result
      assert length(rows) == 5
    end

    assert {:ok, [], 1} = Metrics.decode(Fixture.payload([histogram(%{"count" => "18446744073709551616"})]))
  end

  test "bucket omission, optional sum, infinities and no-recorded-value have explicit non-inventing semantics" do
    points = [
      histogram(%{"bucketCounts" => [], "explicitBounds" => [], "sum" => nil}),
      histogram(%{"count" => 4, "bucketCounts" => [4, 0], "explicitBounds" => ["Infinity"], "sum" => nil}),
      summary(%{"flags" => 1, "quantileValues" => [%{"quantile" => 0.5, "value" => "NaN"}]})
    ]

    rows =
      Enum.flat_map(points, fn metric ->
        assert {:ok, samples, 0} = Metrics.decode(Fixture.payload([metric]))
        samples
      end)

    histograms = Enum.reject(rows, &(&1.otlp["point"]["kind"] == "summary"))
    assert length(histograms) == 4
    assert Enum.all?(histograms, &(&1.value == 4.0))
    refute Enum.any?(histograms, &Map.has_key?(&1.otlp["point"], "sum"))
    assert Enum.all?(Enum.filter(rows, &(&1.otlp["point"]["kind"] == "summary")), &(&1.value == :stale))
  end

  test "staleness ignores supplied values, but still validates types and label-defining structure in both encodings" do
    markers = [
      histogram(%{"flags" => 1, "count" => 0, "sum" => "NaN"}),
      histogram(%{
        "flags" => 1,
        "count" => 0,
        "sum" => "NaN",
        "explicitBounds" => ["Infinity"],
        "bucketCounts" => [1, 2]
      }),
      summary(%{
        "flags" => 1,
        "count" => 0,
        "sum" => "NaN",
        "quantileValues" => [%{"quantile" => 0.5, "value" => -1.0}]
      })
    ]

    for metric <- markers do
      payload = Fixture.payload([metric])
      assert {:ok, json, 0} = Metrics.decode(payload)
      assert {:ok, wire, 0} = Metrics.decode_protobuf(Fixture.protobuf(payload))
      assert deterministic(json) == deterministic(wire)
      assert Enum.all?(json, &(&1.value == :stale))
      assert hd(json).otlp["point"]["sum"] == "NaN"
    end

    for metric <- [
          histogram(%{"flags" => 1, "explicitBounds" => [2.0, 1.0]}),
          summary(%{"flags" => 1, "quantileValues" => [%{"quantile" => 1.1}]})
        ] do
      assert {:ok, [], 1} = Metrics.decode(Fixture.payload([metric]))
      assert {:ok, [], 1} = Metrics.decode_protobuf(Fixture.protobuf(Fixture.payload([metric])))
    end
  end

  test "projected families cannot alias different instruments or conflicting original points within a request" do
    gauge = Fixture.gauge([Fixture.point()]) |> Map.put("name", "histogram_count")
    conflict = histogram(%{"count" => 5, "bucketCounts" => [1, 2, 2]})

    for metrics <- [[histogram(), gauge], [gauge, histogram()], [histogram(), conflict]] do
      payload = Fixture.payload(metrics)
      assert {:error, :invalid_otlp} = Metrics.decode(payload)
      assert {:error, :invalid_otlp} = Metrics.decode_protobuf(Fixture.protobuf(payload))
    end

    assert {:ok, rows, 0} = Metrics.decode(Fixture.payload([histogram(), histogram()]))
    assert length(rows) == 10

    assert {:ok, rows, 0} =
             Metrics.decode(Fixture.payload([histogram(), histogram(%{"timeUnixNano" => "1700000000123456788"})]))

    assert length(rows) == 10
  end

  test "expanded sample limits reject whole requests, in addition to supplied point limits" do
    Runtime.put_env(:pulse, IngestLimits, max_records: 4)

    for result <- [
          Metrics.decode(Fixture.payload([histogram()])),
          Metrics.decode_protobuf(Fixture.protobuf(Fixture.payload([histogram()])))
        ] do
      assert result == {:error, :too_many_records}
    end

    Runtime.put_env(:pulse, IngestLimits, max_records: 8)
    assert {:error, :too_many_records} = Metrics.decode(Fixture.payload([histogram(), histogram()]))
  end

  test "full repeated source envelopes still obey the independent 16MiB additive metadata budget" do
    bounds = Enum.map(1..1800, &(&1 / 1))
    point = %{"count" => 0, "sum" => nil, "bucketCounts" => List.duplicate(0, 1801), "explicitBounds" => bounds}
    assert {:error, :payload_too_large} = Metrics.decode(Fixture.payload([histogram(point)]))
  end

  test "actual Go fixed shortest-roundtrip labels agree on boundary and randomized finite IEEE values" do
    cases = @directory |> Path.join("float-labels.json") |> File.read!() |> Pulse.JSON.decode!()
    assert length(cases) > 2000

    for c <- cases do
      <<value::float-64>> = Base.decode16!(c["bits"], case: :lower)
      point = %{"count" => 0, "bucketCounts" => [0, 0], "explicitBounds" => [value]}

      assert {:ok, _, [{_, {"le", label}, _, _} | _]} =
               Distribution.normalize("histogram", %{"aggregationTemporality" => 2}, point, 3)

      assert label == c["label"], c["bits"]
    end
  end

  defp histogram(extra \\ %{}) do
    point =
      Map.merge(
        %{
          "timeUnixNano" => "1700000000123456789",
          "count" => 4,
          "sum" => 6.0,
          "bucketCounts" => [1, 2, 1],
          "explicitBounds" => [1.0, 2.0]
        },
        extra
      )

    %{"name" => "histogram", "histogram" => %{"aggregationTemporality" => 2, "dataPoints" => [point]}}
  end

  defp summary(extra) do
    point = Map.merge(%{"timeUnixNano" => "1700000000123456789", "count" => 4, "sum" => 6.0}, extra)
    %{"name" => "summary", "summary" => %{"dataPoints" => [point]}}
  end

  defp json, do: @directory |> Path.join("input.json") |> File.read!() |> JSON.decode!()
  defp deterministic(value), do: :erlang.term_to_binary(value, [:deterministic])
  defp sha(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
end
