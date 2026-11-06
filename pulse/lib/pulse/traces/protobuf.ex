defmodule Pulse.Traces.Protobuf do
  @moduledoc false
  # Independent Elixir reference for the official OTLP trace wire schema.
  @schemas %{
    tags: [{1, "tagNames", :strings}],
    tags_v2: [{1, "scopes", {:messages, :tag_scope}}],
    tag_scope: [{1, "name", :string}, {2, "tags", :strings}],
    tag_values: [{1, "tagValues", :strings}],
    tag_values_v2: [{1, "tagValues", {:messages, :tag_value}}],
    tag_value: [{1, "type", :string}, {2, "value", :string}],
    search: [{1, "traces", {:messages, :search_trace}}],
    search_trace: [
      {1, "traceID", :string},
      {2, "rootServiceName", :string},
      {3, "rootTraceName", :string},
      {4, "startTimeUnixNano", :uint},
      {5, "durationMs", :uint},
      {6, "spanSet", {:message, :span_set}},
      {7, "spanSets", {:messages, :span_set}},
      {8, "serviceStats", {:map, :service_entry}}
    ],
    span_set: [{1, "spans", {:messages, :search_span}}, {2, "matched", :uint}, {3, "attributes", {:messages, :pair}}],
    search_span: [
      {1, "spanID", :string},
      {2, "name", :string},
      {3, "startTimeUnixNano", :uint},
      {4, "durationNanos", :uint},
      {5, "attributes", {:messages, :pair}}
    ],
    service_entry: [{1, "key", :string}, {2, "value", {:message, :service_stats}}],
    service_stats: [{1, "spanCount", :uint}, {2, "errorCount", :uint}],
    response: [{1, "trace", {:message, :export}}, {3, "status", :enum}, {4, "message", :string}],
    export: [{1, "batches", {:messages, :resource_spans}}],
    resource_spans: [
      {1, "resource", {:message, :resource}},
      {2, "scopeSpans", {:messages, :scope_spans}},
      {3, "schemaUrl", :string}
    ],
    resource: [{1, "attributes", {:messages, :pair}}, {2, "droppedAttributesCount", :uint}],
    scope_spans: [{1, "scope", {:message, :scope}}, {2, "spans", {:messages, :span}}, {3, "schemaUrl", :string}],
    scope: [
      {1, "name", :string},
      {2, "version", :string},
      {3, "attributes", {:messages, :pair}},
      {4, "droppedAttributesCount", :uint}
    ],
    span: [
      {1, "traceId", :bytes},
      {2, "spanId", :bytes},
      {3, "traceState", :string},
      {4, "parentSpanId", :bytes},
      {5, "name", :string},
      {6, "kind", :enum},
      {7, "startTimeUnixNano", :fixed64},
      {8, "endTimeUnixNano", :fixed64},
      {9, "attributes", {:messages, :pair}},
      {10, "droppedAttributesCount", :uint},
      {11, "events", {:messages, :event}},
      {12, "droppedEventsCount", :uint},
      {13, "links", {:messages, :link}},
      {14, "droppedLinksCount", :uint},
      {15, "status", {:message, :status}},
      {16, "flags", :fixed32}
    ],
    event: [
      {1, "timeUnixNano", :fixed64},
      {2, "name", :string},
      {3, "attributes", {:messages, :pair}},
      {4, "droppedAttributesCount", :uint}
    ],
    link: [
      {1, "traceId", :bytes},
      {2, "spanId", :bytes},
      {3, "traceState", :string},
      {4, "attributes", {:messages, :pair}},
      {5, "droppedAttributesCount", :uint},
      {6, "flags", :fixed32}
    ],
    status: [{2, "message", :string}, {3, "code", :enum}],
    pair: [{1, "key", :string}, {2, "value", {:message, :any}}],
    any: [
      {1, "stringValue", :string},
      {2, "boolValue", :bool},
      {3, "intValue", :int},
      {4, "doubleValue", :double},
      {5, "arrayValue", {:message, :array}},
      {6, "kvlistValue", {:message, :kvlist}},
      {7, "bytesValue", :bytes}
    ],
    array: [{1, "values", {:messages, :any}}],
    kvlist: [{1, "values", {:messages, :pair}}]
  }
  @enums %{
    "SPAN_KIND_UNSPECIFIED" => 0,
    "SPAN_KIND_INTERNAL" => 1,
    "SPAN_KIND_SERVER" => 2,
    "SPAN_KIND_CLIENT" => 3,
    "SPAN_KIND_PRODUCER" => 4,
    "SPAN_KIND_CONSUMER" => 5,
    "STATUS_CODE_UNSET" => 0,
    "STATUS_CODE_OK" => 1,
    "STATUS_CODE_ERROR" => 2,
    "COMPLETE" => 0,
    "PARTIAL" => 1
  }

  def encode(trace, schema \\ :export), do: trace |> message(schema) |> IO.iodata_to_binary()

  defp message(map, schema) do
    Enum.flat_map(Map.fetch!(@schemas, schema), fn {number, name, type} ->
      case Map.fetch(map, name) do
        {:ok, value} -> [field(number, type, value, schema == :any)]
        :error -> []
      end
    end)
  end

  defp field(number, {:map, schema}, values, _oneof),
    do:
      values
      |> Enum.sort()
      |> Enum.map(fn {key, value} -> field(number, {:message, schema}, %{"key" => key, "value" => value}, false) end)

  defp field(number, {:messages, :span}, values, _oneof) do
    # A span is the retained encoding unit: release its nested event/attribute
    # iodata before building the next span, without copying each small child.
    Enum.map(values, fn value ->
      number |> field({:message, :span}, value, false) |> IO.iodata_to_binary()
    end)
  end

  defp field(number, {:messages, schema}, values, _oneof),
    do: Enum.map(values, &field(number, {:message, schema}, &1, false))

  defp field(number, {:message, schema}, value, _oneof), do: delimited(number, message(value, schema))
  defp field(number, :strings, values, _oneof), do: Enum.map(values, &delimited(number, &1))
  defp field(number, :string, value, _oneof), do: delimited(number, value)
  defp field(number, :bytes, value, _oneof), do: delimited(number, Base.decode64!(value))

  defp field(number, :double, value, _oneof) when value in ["NaN", "Infinity", "-Infinity"] do
    bits =
      case value do
        "NaN" -> 0x7FF8000000000000
        "Infinity" -> 0x7FF0000000000000
        "-Infinity" -> 0xFFF0000000000000
      end

    [varint(number * 8 + 1), <<bits::little-64>>]
  end

  defp field(number, :double, value, _oneof), do: [varint(number * 8 + 1), <<value / 1::little-float-64>>]
  defp field(number, :fixed64, value, _oneof), do: [varint(number * 8 + 1), <<integer(value)::little-unsigned-64>>]
  defp field(number, :fixed32, value, _oneof), do: [varint(number * 8 + 5), <<value::little-unsigned-32>>]
  defp field(number, :enum, value, _oneof), do: [varint(number * 8), varint(Map.fetch!(@enums, value))]
  defp field(number, :bool, value, _oneof), do: [varint(number * 8), varint(if(value, do: 1, else: 0))]

  defp field(number, :int, value, _oneof),
    do: [varint(number * 8), varint(Bitwise.band(integer(value), 0xFFFFFFFFFFFFFFFF))]

  defp field(number, :uint, value, _oneof), do: [varint(number * 8), varint(integer(value))]
  defp integer(value) when is_binary(value), do: String.to_integer(value)
  defp integer(value), do: value
  defp delimited(number, body), do: [varint(number * 8 + 2), varint(IO.iodata_length(body)), body]
  defp varint(value) when value < 128, do: <<value>>
  defp varint(value), do: [<<Bitwise.bor(Bitwise.band(value, 127), 128)>>, varint(Bitwise.bsr(value, 7))]
end
