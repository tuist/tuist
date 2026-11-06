defmodule Pulse.Record.Span do
  @moduledoc "An OTLP span. IDs are lowercase hex; timestamp_ns is the span start time."
  alias Pulse.Traces.RegexFilters

  defstruct timestamp_ns: nil,
            end_timestamp_ns: nil,
            trace_id: nil,
            span_id: nil,
            parent_span_id: nil,
            trace_state: "",
            flags: 0,
            name: "",
            kind: 0,
            service: nil,
            status: %{"code" => 0, "message" => ""},
            attributes: %{},
            resource: %{},
            scope: %{},
            events: [],
            links: [],
            dropped_attributes_count: 0,
            dropped_events_count: 0,
            dropped_links_count: 0,
            resource_dropped_attributes_count: 0,
            resource_schema_url: "",
            scope_schema_url: "",
            otlp: nil

  @type t :: %__MODULE__{
          timestamp_ns: non_neg_integer() | nil,
          end_timestamp_ns: non_neg_integer() | nil,
          trace_id: String.t() | nil,
          span_id: String.t() | nil,
          parent_span_id: String.t() | nil,
          service: String.t() | nil,
          name: String.t(),
          kind: 0..5,
          flags: non_neg_integer(),
          status: map(),
          attributes: map(),
          resource: map(),
          scope: map(),
          events: [map()],
          links: [map()],
          otlp: map() | nil
        }

  @doc false
  def to_map(%__MODULE__{} = span) do
    fields = Map.from_struct(span)
    fields = if is_nil(span.otlp), do: Map.delete(fields, :otlp), else: fields
    Map.new(fields, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  @doc false
  def from_map(map) do
    # Never create atoms from storage or user input.
    fields = Map.keys(%__MODULE__{}) -- [:__struct__, :otlp]
    struct!(__MODULE__, [{:otlp, Map.get(map, "otlp")} | Enum.map(fields, &{&1, Map.fetch!(map, Atom.to_string(&1))})])
  end

  @doc false
  def matches?(span, opts) do
    Enum.all?([:trace_id, :span_id, :parent_span_id, :service, :name, :kind], fn key ->
      wanted = Keyword.get(opts, key)
      is_nil(wanted) or Map.fetch!(span, key) == wanted
    end) and
      (is_nil(opts[:status_code]) or span.status["code"] == opts[:status_code]) and
      (opts[:root_only] != true or is_nil(span.parent_span_id)) and
      duration_matches?(span, opts) and
      attribute_matches?(span, opts)
  end

  defp attribute_matches?(span, opts) do
    RegexFilters.matches?(span, opts) and
      Enum.all?(Keyword.get(opts, :attributes, %{}), fn {key, value} ->
        Map.fetch(span.attributes, key) === {:ok, value}
      end) and
      Enum.all?(Keyword.get(opts, :resource, %{}), fn {key, value} -> Map.fetch(span.resource, key) === {:ok, value} end)
  end

  defp duration_matches?(span, opts) do
    duration = span.end_timestamp_ns - span.timestamp_ns

    (is_nil(opts[:min_duration_ns]) or duration >= opts[:min_duration_ns]) and
      (is_nil(opts[:max_duration_ns]) or duration <= opts[:max_duration_ns])
  end
end
