defmodule Pulse.Test.OTLPTraceFixture do
  @moduledoc false
  import Bitwise

  @trace "0123456789abcdef0123456789abcdef"
  @span "0123456789abcdef"

  def trace_id, do: @trace
  def span_id, do: @span

  def span(ts \\ 1_700_000_000_123_456_789) do
    %{
      "traceId" => @trace,
      "spanId" => @span,
      "parentSpanId" => "fedcba9876543210",
      "traceState" => "vendor=value",
      "flags" => 257,
      "name" => "GET /api/builds",
      "kind" => 2,
      "startTimeUnixNano" => Integer.to_string(ts),
      "endTimeUnixNano" => Integer.to_string(ts + 1000),
      "attributes" =>
        pairs(%{
          "auth_account_handle" => %{"stringValue" => "acme"},
          "request_kind" => %{"stringValue" => "api"},
          "http.response.status_code" => %{"intValue" => "500"},
          "metrics.skip" => %{"boolValue" => false},
          "elapsed" => %{"doubleValue" => 1.25},
          "negative" => %{"intValue" => "-42"},
          "bytes" => %{"bytesValue" => "aGVsbG8="},
          "nested" => %{
            "arrayValue" => %{
              "values" => [
                %{"boolValue" => true},
                %{"kvlistValue" => %{"values" => pairs(%{"unicode" => %{"stringValue" => "🌍\n"}})}}
              ]
            }
          }
        }),
      "status" => %{"code" => 2, "message" => "failed"},
      "events" => [
        %{
          "timeUnixNano" => Integer.to_string(ts + 500),
          "name" => "exception",
          "attributes" => pairs(%{"exception.message" => %{"stringValue" => "oops"}}),
          "droppedAttributesCount" => 2
        }
      ],
      "links" => [
        %{
          "traceId" => String.duplicate("a", 32),
          "spanId" => String.duplicate("b", 16),
          "traceState" => "remote=1",
          "flags" => 1,
          "attributes" => [],
          "droppedAttributesCount" => 3
        }
      ],
      "droppedAttributesCount" => 4,
      "droppedEventsCount" => 5,
      "droppedLinksCount" => 6
    }
  end

  def payload(spans \\ [span()]) do
    %{
      "resourceSpans" => [
        %{
          "schemaUrl" => "https://opentelemetry.io/schemas/1.27.0",
          "resource" => %{
            "attributes" =>
              pairs(%{
                "service.name" => %{"stringValue" => "tuist-server"},
                "service.namespace" => %{"stringValue" => "tuist"},
                "deployment.environment" => %{"stringValue" => "production"}
              }),
            "droppedAttributesCount" => 1
          },
          "scopeSpans" => [
            %{
              "schemaUrl" => "https://example.com/schema",
              "scope" => %{
                "name" => "opentelemetry_phoenix",
                "version" => "2.0",
                "attributes" => pairs(%{"library" => %{"stringValue" => "phoenix"}}),
                "droppedAttributesCount" => 2
              },
              "spans" => spans
            }
          ]
        }
      ]
    }
  end

  def pairs(map), do: Enum.map(Enum.sort(map), fn {k, v} -> %{"key" => k, "value" => v} end)
  def protobuf(payload \\ payload()), do: message(payload, :export)

  # Independent test-only encoder of the published OTLP proto field numbers.
  @schemas %{
    export: [{1, "resourceSpans", :resources, true}],
    resources: [{1, "resource", :resource, false}, {2, "scopeSpans", :scopes, true}, {3, "schemaUrl", :string, false}],
    resource: [{1, "attributes", :pair, true}, {2, "droppedAttributesCount", :uint, false}],
    scopes: [{1, "scope", :scope, false}, {2, "spans", :span, true}, {3, "schemaUrl", :string, false}],
    scope: [
      {1, "name", :string, false},
      {2, "version", :string, false},
      {3, "attributes", :pair, true},
      {4, "droppedAttributesCount", :uint, false}
    ],
    span: [
      {1, "traceId", :hex, false},
      {2, "spanId", :hex, false},
      {3, "traceState", :string, false},
      {4, "parentSpanId", :hex, false},
      {5, "name", :string, false},
      {6, "kind", :uint, false},
      {7, "startTimeUnixNano", :fixed64, false},
      {8, "endTimeUnixNano", :fixed64, false},
      {9, "attributes", :pair, true},
      {10, "droppedAttributesCount", :uint, false},
      {11, "events", :event, true},
      {12, "droppedEventsCount", :uint, false},
      {13, "links", :link, true},
      {14, "droppedLinksCount", :uint, false},
      {15, "status", :status, false},
      {16, "flags", :fixed32, false}
    ],
    event: [
      {1, "timeUnixNano", :fixed64, false},
      {2, "name", :string, false},
      {3, "attributes", :pair, true},
      {4, "droppedAttributesCount", :uint, false}
    ],
    link: [
      {1, "traceId", :hex, false},
      {2, "spanId", :hex, false},
      {3, "traceState", :string, false},
      {4, "attributes", :pair, true},
      {5, "droppedAttributesCount", :uint, false},
      {6, "flags", :fixed32, false}
    ],
    status: [{2, "message", :string, false}, {3, "code", :uint, false}],
    pair: [{1, "key", :string, false}, {2, "value", :any, false}],
    any: [
      {1, "stringValue", :string, false},
      {2, "boolValue", :bool, false},
      {3, "intValue", :uint, false},
      {4, "doubleValue", :double, false},
      {5, "arrayValue", :array, false},
      {6, "kvlistValue", :kvlist, false},
      {7, "bytesValue", :base64, false}
    ],
    array: [{1, "values", :any, true}],
    kvlist: [{1, "values", :pair, true}]
  }

  def message(map, schema) do
    Enum.map(@schemas[schema], fn {field, key, type, repeated} ->
      case Map.fetch(map, key) do
        :error ->
          []

        {:ok, values} ->
          encode_field(field, type, values, repeated)
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp encode_field(n, type, values, true), do: Enum.map(values, &field(n, type, &1))
  defp encode_field(n, type, value, false), do: field(n, type, value)

  defp field(n, :fixed64, v), do: [varint(n * 8 + 1), <<integer(v)::little-unsigned-64>>]
  defp field(n, :fixed32, v), do: [varint(n * 8 + 5), <<v::little-unsigned-32>>]

  defp field(n, :double, v) when v in ["NaN", "Infinity", "-Infinity"] do
    bits =
      case v do
        "NaN" -> 0x7FF8000000000000
        "Infinity" -> 0x7FF0000000000000
        "-Infinity" -> 0xFFF0000000000000
      end

    [varint(n * 8 + 1), <<bits::little-unsigned-64>>]
  end

  defp field(n, :double, v), do: [varint(n * 8 + 1), <<v::little-float-64>>]
  defp field(n, :uint, v), do: [varint(n * 8), varint(band(integer(v), 0xFFFFFFFFFFFFFFFF))]
  defp field(n, :bool, v), do: field(n, :uint, if(v, do: 1, else: 0))
  defp field(n, :hex, v), do: bytes(n, Base.decode16!(v, case: :mixed))
  defp field(n, :base64, v), do: bytes(n, Base.decode64!(v))
  defp field(n, :string, v), do: bytes(n, v)
  defp field(n, schema, v), do: bytes(n, message(v, schema))
  def bytes(n, b), do: IO.iodata_to_binary([varint(n * 8 + 2), varint(byte_size(b)), b])
  defp integer(v) when is_binary(v), do: String.to_integer(v)
  defp integer(v), do: v
  defp varint(n) when n < 128, do: <<n>>
  defp varint(n), do: [<<bor(band(n, 127), 128)>>, varint(bsr(n, 7))]
end
