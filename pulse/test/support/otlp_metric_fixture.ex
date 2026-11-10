defmodule Pulse.Test.OTLPMetricFixture do
  @moduledoc false
  import Bitwise

  alias Pulse.Test.OTLPTraceFixture, as: Common

  @schemas %{
    export: [{1, "resourceMetrics", :resources, true}],
    resources: [{1, "resource", :resource, false}, {2, "scopeMetrics", :scopes, true}, {3, "schemaUrl", :string, false}],
    scopes: [{1, "scope", :scope, false}, {2, "metrics", :metric, true}, {3, "schemaUrl", :string, false}],
    metric: [
      {1, "name", :string, false},
      {2, "description", :string, false},
      {3, "unit", :string, false},
      {5, "gauge", :gauge, false},
      {7, "sum", :sum, false},
      {9, "histogram", :histogram, false},
      {10, "exponentialHistogram", :exponential, false},
      {11, "summary", :summary, false},
      {12, "metadata", :pair, true}
    ],
    gauge: [{1, "dataPoints", :point, true}],
    sum: [
      {1, "dataPoints", :point, true},
      {2, "aggregationTemporality", :uint, false},
      {3, "isMonotonic", :bool, false}
    ],
    exponential: [{1, "dataPoints", :exponential_point, true}, {2, "aggregationTemporality", :uint, false}],
    exponential_point: [
      {1, "attributes", :pair, true},
      {2, "startTimeUnixNano", :fixed64, false},
      {3, "timeUnixNano", :fixed64, false},
      {4, "count", :fixed64, false},
      {5, "sum", :double, false},
      {6, "scale", :sint32, false},
      {7, "zeroCount", :fixed64, false},
      {8, "positive", :buckets, false},
      {9, "negative", :buckets, false},
      {10, "flags", :uint, false},
      {11, "exemplars", :exemplar, true},
      {12, "min", :double, false},
      {13, "max", :double, false},
      {14, "zeroThreshold", :double, false}
    ],
    buckets: [{1, "offset", :sint32, false}, {2, "bucketCounts", :packed_varint, false}],
    histogram: [{1, "dataPoints", :histogram_point, true}, {2, "aggregationTemporality", :uint, false}],
    histogram_point: [
      {2, "startTimeUnixNano", :fixed64, false},
      {3, "timeUnixNano", :fixed64, false},
      {4, "count", :fixed64, false},
      {5, "sum", :double, false},
      {6, "bucketCounts", :packed_uint64, false},
      {7, "explicitBounds", :packed_double, false},
      {8, "exemplars", :exemplar, true},
      {9, "attributes", :pair, true},
      {10, "flags", :uint, false},
      {11, "min", :double, false},
      {12, "max", :double, false}
    ],
    summary: [{1, "dataPoints", :summary_point, true}],
    summary_point: [
      {2, "startTimeUnixNano", :fixed64, false},
      {3, "timeUnixNano", :fixed64, false},
      {4, "count", :fixed64, false},
      {5, "sum", :double, false},
      {6, "quantileValues", :quantile, true},
      {7, "attributes", :pair, true},
      {8, "flags", :uint, false}
    ],
    quantile: [{1, "quantile", :double, false}, {2, "value", :double, false}],
    point: [
      {2, "startTimeUnixNano", :fixed64, false},
      {3, "timeUnixNano", :fixed64, false},
      {4, "asDouble", :double, false},
      {6, "asInt", :signed64, false},
      {7, "attributes", :pair, true},
      {5, "exemplars", :exemplar, true},
      {8, "flags", :uint, false}
    ],
    exemplar: [
      {2, "timeUnixNano", :fixed64, false},
      {3, "asDouble", :double, false},
      {6, "asInt", :signed64, false},
      {7, "filteredAttributes", :pair, true},
      {4, "spanId", :hex, false},
      {5, "traceId", :hex, false}
    ]
  }

  def json, do: Pulse.JSON.decode!(File.read!("test/fixtures/otlp/protoc-metrics.json"))
  def protobuf, do: File.read!("test/fixtures/otlp/protoc-metrics.protobuf")
  def protobuf(payload), do: message(payload, :export)

  def payload(metrics) do
    %{"resourceMetrics" => [%{"scopeMetrics" => [%{"metrics" => metrics}]}]}
  end

  def gauge(points), do: %{"name" => "metric", "gauge" => %{"dataPoints" => points}}
  def point(value \\ 1.5), do: %{"timeUnixNano" => "1700000000123456789", "asDouble" => value}

  defp message(map, schema) do
    Enum.flat_map(@schemas[schema], fn {number, key, type, repeated} ->
      Enum.map(values(map, key, repeated), &field(number, type, &1))
    end)
    |> IO.iodata_to_binary()
  end

  defp values(map, key, true), do: Map.get(map, key, [])
  defp values(map, key, false), do: if(Map.has_key?(map, key), do: [map[key]], else: [])
  defp field(n, :string, value), do: Common.bytes(n, value)
  defp field(n, :hex, value), do: Common.bytes(n, Base.decode16!(value, case: :mixed))
  defp field(n, :uint, value), do: [varint(n * 8), varint(integer(value))]
  defp field(n, :bool, value), do: field(n, :uint, if(value, do: 1, else: 0))
  defp field(n, :fixed64, value), do: [varint(n * 8 + 1), <<integer(value)::little-unsigned-64>>]
  defp field(n, :signed64, value), do: [varint(n * 8 + 1), <<integer(value)::little-signed-64>>]

  defp field(n, :sint32, value) do
    value = integer(value)
    [varint(n * 8), varint(if(value >= 0, do: value * 2, else: -value * 2 - 1))]
  end

  defp field(n, :packed_varint, values),
    do: Common.bytes(n, values |> Enum.map(&varint(integer(&1))) |> IO.iodata_to_binary())

  defp field(n, :packed_uint64, values),
    do: Common.bytes(n, Enum.map(values, &<<integer(&1)::little-unsigned-64>>) |> IO.iodata_to_binary())

  defp field(n, :packed_double, values), do: Common.bytes(n, Enum.map(values, &double_bits/1) |> IO.iodata_to_binary())

  defp field(n, :double, "NaN"), do: [varint(n * 8 + 1), <<0x7FF8000000000000::little-64>>]
  defp field(n, :double, "Infinity"), do: [varint(n * 8 + 1), <<0x7FF0000000000000::little-64>>]
  defp field(n, :double, "-Infinity"), do: [varint(n * 8 + 1), <<0xFFF0000000000000::little-64>>]
  defp field(n, :double, value), do: [varint(n * 8 + 1), <<value::little-float-64>>]

  defp field(n, schema, value) when schema in [:resource, :scope, :pair],
    do: Common.bytes(n, Common.message(value, schema))

  defp field(n, schema, value), do: Common.bytes(n, message(value, schema))
  defp double_bits("NaN"), do: <<0x7FF8000000000000::little-64>>
  defp double_bits("Infinity"), do: <<0x7FF0000000000000::little-64>>
  defp double_bits("-Infinity"), do: <<0xFFF0000000000000::little-64>>
  defp double_bits(value), do: <<value::little-float-64>>
  defp integer(value) when is_binary(value), do: String.to_integer(value)
  defp integer(value), do: value
  defp varint(n) when n < 128, do: <<n>>
  defp varint(n), do: [<<bor(band(n, 127), 128)>>, varint(bsr(n, 7))]
end
