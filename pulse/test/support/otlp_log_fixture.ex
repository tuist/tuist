defmodule Pulse.Test.OTLPLogFixture do
  @moduledoc false
  import Bitwise

  alias Pulse.Test.OTLPTraceFixture, as: Common

  def json, do: "test/fixtures/otlp/protoc-logs.json" |> File.read!() |> JSON.decode!()
  def protobuf, do: File.read!("test/fixtures/otlp/protoc-logs.protobuf")
  def records, do: get_in(json(), ["resourceLogs", Access.at(0), "scopeLogs", Access.at(0), "logRecords"])

  def payload(records) do
    put_in(json(), ["resourceLogs", Access.at(0), "scopeLogs", Access.at(0), "logRecords"], records)
  end

  def protobuf(payload), do: message(payload, :export)

  @schemas %{
    export: [{1, "resourceLogs", :resource_logs, true}],
    resource_logs: [
      {1, "resource", :resource, false},
      {2, "scopeLogs", :scope_logs, true},
      {3, "schemaUrl", :string, false}
    ],
    scope_logs: [{1, "scope", :scope, false}, {2, "logRecords", :log, true}, {3, "schemaUrl", :string, false}],
    log: [
      {1, "timeUnixNano", :fixed64, false},
      {2, "severityNumber", :uint, false},
      {3, "severityText", :string, false},
      {5, "body", :any, false},
      {6, "attributes", :pair, true},
      {7, "droppedAttributesCount", :uint, false},
      {8, "flags", :fixed32, false},
      {9, "traceId", :hex, false},
      {10, "spanId", :hex, false},
      {11, "observedTimeUnixNano", :fixed64, false},
      {12, "eventName", :string, false}
    ]
  }
  # Mutations use a small test encoder; the fixed baseline is independently
  # encoded by protoc against official descriptors, not this helper.
  def message(map, schema) do
    Enum.flat_map(@schemas[schema], fn {number, key, type, repeated} ->
      values = values(map, key, repeated)
      Enum.map(values, &field(number, type, &1))
    end)
    |> IO.iodata_to_binary()
  end

  defp values(map, key, true), do: Map.get(map, key, [])
  defp values(map, key, false), do: if(Map.has_key?(map, key), do: [map[key]], else: [])

  defp field(n, :fixed64, v), do: [varint(n * 8 + 1), <<integer(v)::little-unsigned-64>>]
  defp field(n, :fixed32, v), do: [varint(n * 8 + 5), <<v::little-unsigned-32>>]
  defp field(n, :uint, v), do: [varint(n * 8), varint(integer(v))]
  defp field(n, :hex, v), do: Common.bytes(n, Base.decode16!(v, case: :mixed))
  defp field(n, :string, v), do: Common.bytes(n, v)

  defp field(n, schema, v) when schema in [:export, :resource_logs, :scope_logs, :log],
    do: Common.bytes(n, message(v, schema))

  defp field(n, schema, v), do: Common.bytes(n, Common.message(v, schema))
  defp integer(v) when is_binary(v), do: String.to_integer(v)
  defp integer(v), do: v
  defp varint(n) when n < 128, do: <<n>>
  defp varint(n), do: [<<bor(band(n, 127), 128)>>, varint(bsr(n, 7))]
end
