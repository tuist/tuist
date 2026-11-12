defmodule Pulse.OTLP.JSONReference do
  @moduledoc false
  # Independent Elixir schema/lexer reference for the native OTLP JSON path.
  # Callbacks keep number tokens unrounded; tuples cannot be forged by JSON.
  alias Pulse.OTLP.Value

  @fields %{
    root: %{
      "resourceLogs" => :resource_logs,
      "resourceMetrics" => :resource_metrics,
      "resourceSpans" => :resource_spans
    },
    root_logs: %{"resourceLogs" => :resource_logs},
    root_metrics: %{"resourceMetrics" => :resource_metrics},
    root_traces: %{"resourceSpans" => :resource_spans},
    resource_logs: %{"resource" => :resource, "scopeLogs" => :scope_logs},
    resource_metrics: %{"resource" => :resource, "scopeMetrics" => :scope_metrics},
    resource_spans: %{"resource" => :resource, "scopeSpans" => :scope_spans},
    scope_logs: %{"scope" => :scope, "logRecords" => :log},
    scope_metrics: %{"scope" => :scope, "metrics" => :metric},
    scope_spans: %{"scope" => :scope, "spans" => :span},
    resource: %{"attributes" => :pair, "droppedAttributesCount" => :integer},
    scope: %{"attributes" => :pair, "droppedAttributesCount" => :integer},
    pair: %{"value" => :any},
    any: %{"intValue" => :integer, "arrayValue" => :array, "kvlistValue" => :kvlist},
    array: %{"values" => :any},
    kvlist: %{"values" => :pair},
    metric: %{
      "metadata" => :pair,
      "gauge" => :gauge,
      "sum" => :sum,
      "histogram" => :histogram,
      "summary" => :summary,
      "exponentialHistogram" => :exponential
    },
    gauge: %{"dataPoints" => :number},
    sum: %{"dataPoints" => :number, "aggregationTemporality" => :integer},
    histogram: %{"dataPoints" => :histogram_point, "aggregationTemporality" => :integer},
    exponential: %{"dataPoints" => :exponential_point, "aggregationTemporality" => :integer},
    summary: %{"dataPoints" => :summary_point},
    number: %{
      "attributes" => :pair,
      "exemplars" => :exemplar,
      "asInt" => :integer,
      "flags" => :integer,
      "startTimeUnixNano" => :integer,
      "timeUnixNano" => :integer
    },
    exemplar: %{"filteredAttributes" => :pair, "timeUnixNano" => :integer, "asInt" => :integer},
    histogram_point: %{
      "attributes" => :pair,
      "exemplars" => :exemplar,
      "flags" => :integer,
      "startTimeUnixNano" => :integer,
      "timeUnixNano" => :integer,
      "count" => :integer,
      "bucketCounts" => :integer
    },
    summary_point: %{
      "quantileValues" => :quantile,
      "attributes" => :pair,
      "flags" => :integer,
      "startTimeUnixNano" => :integer,
      "timeUnixNano" => :integer,
      "count" => :integer
    },
    exponential_point: %{
      "attributes" => :pair,
      "exemplars" => :exemplar,
      "flags" => :integer,
      "startTimeUnixNano" => :integer,
      "timeUnixNano" => :integer,
      "count" => :integer,
      "scale" => :integer,
      "zeroCount" => :integer,
      "positive" => :buckets,
      "negative" => :buckets
    },
    buckets: %{"offset" => :integer, "bucketCounts" => :integer},
    log: %{
      "body" => :any,
      "attributes" => :pair,
      "timeUnixNano" => :integer,
      "observedTimeUnixNano" => :integer,
      "severityNumber" => :integer,
      "flags" => :integer,
      "droppedAttributesCount" => :integer
    },
    span: %{
      "attributes" => :pair,
      "events" => :event,
      "links" => :link,
      "status" => :status,
      "startTimeUnixNano" => :integer,
      "endTimeUnixNano" => :integer,
      "flags" => :integer,
      "kind" => :integer,
      "droppedAttributesCount" => :integer,
      "droppedEventsCount" => :integer,
      "droppedLinksCount" => :integer
    },
    event: %{"attributes" => :pair, "timeUnixNano" => :integer, "droppedAttributesCount" => :integer},
    link: %{"attributes" => :pair, "flags" => :integer, "droppedAttributesCount" => :integer},
    status: %{"code" => :integer}
  }

  @scalars %{
    resource_logs: ~w(schemaUrl),
    resource_metrics: ~w(schemaUrl),
    resource_spans: ~w(schemaUrl),
    scope_logs: ~w(schemaUrl),
    scope_metrics: ~w(schemaUrl),
    scope_spans: ~w(schemaUrl),
    resource: ~w(entityRefs),
    scope: ~w(name version),
    pair: ~w(key),
    any: ~w(stringValue boolValue doubleValue bytesValue),
    metric: ~w(name description unit),
    sum: ~w(isMonotonic),
    number: ~w(asDouble),
    exemplar: ~w(asDouble traceId spanId),
    histogram_point: ~w(sum min max explicitBounds),
    exponential_point: ~w(sum min max zeroThreshold),
    summary_point: ~w(sum),
    quantile: ~w(quantile value),
    log: ~w(severityText traceId spanId eventName),
    span: ~w(traceId spanId parentSpanId name traceState),
    event: ~w(name),
    link: ~w(traceId spanId traceState),
    status: ~w(message)
  }
  @roots %{all: :root, logs: :root_logs, metrics: :root_metrics, traces: :root_traces}

  def decode!(body, signal \\ :all) when signal in [:all, :logs, :metrics, :traces] do
    body = negative_zero(body)

    options = [
      integer: &{:number, :integer, &1},
      float: &{:number, :float, &1},
      object_start: fn _ -> [] end,
      object_push: fn key, value, acc -> [{key, value} | acc] end,
      object_finish: fn acc, old -> {{:object, Enum.reverse(acc)}, old} end
    ]

    case JSON.decode(body, nil, options) do
      {value, nil, ""} -> normalize(value, Map.fetch!(@roots, signal))
      _ -> JSON.decode!(body)
    end
  end

  defp normalize({:number, _kind, raw}, :integer) do
    case Value.integer(raw, -9_223_372_036_854_775_808, 18_446_744_073_709_551_615) do
      {:ok, value} -> value
      :error -> :invalid_otlp_integer
    end
  end

  defp normalize({:number, _kind, raw}, :unknown) do
    # Unknown fields are opaque protocol data. A syntactically valid numeric
    # token must not fail only because a BEAM float cannot represent it. Keep
    # scalar/eight-byte admission rather than discarding its supplied node.
    JSON.decode!(raw)
  rescue
    JSON.DecodeError -> :invalid_otlp_integer
  end

  defp normalize({:number, _kind, raw}, _role), do: JSON.decode!(raw)
  defp normalize(values, role) when is_list(values), do: Enum.map(values, &normalize(&1, role))

  defp normalize({:object, pairs}, role) do
    fields = Map.get(@fields, role, %{})
    known = Map.keys(fields) ++ Map.get(@scalars, role, [])

    {result, _seen} =
      Enum.reduce(pairs, {%{}, MapSet.new()}, fn {key, child}, {result, seen} ->
        known? = key in known
        if known? and MapSet.member?(seen, key), do: raise(ArgumentError, "duplicate OTLP JSON field #{key}")
        fallback = if known?, do: :ordinary, else: :unknown
        value = normalize(child, Map.get(fields, key, fallback))
        seen = if known?, do: MapSet.put(seen, key), else: seen
        {Map.put_new(result, key, value), seen}
      end)

    result
  end

  defp normalize(value, _role), do: value

  # Unlike the built-in integer callback (which receives "0" for -0), this
  # independent scanner retains double negative zero before token decoding.
  defp negative_zero(body), do: zeroes(body, 0, 0, false, [])

  defp zeroes(body, cursor, mark, quoted, parts) do
    patterns = if quoted, do: ["\"", "\\"], else: ["\"", "-0"]

    case :binary.match(body, patterns, scope: {cursor, byte_size(body) - cursor}) do
      :nomatch -> finish(body, mark, parts)
      {pos, _length} -> zero(body, pos, mark, quoted, parts)
    end
  end

  defp zero(body, pos, mark, quoted, parts) do
    case :binary.at(body, pos) do
      ?" ->
        zeroes(body, pos + 1, mark, not quoted, parts)

      ?\\ ->
        zeroes(body, min(pos + 2, byte_size(body)), mark, quoted, parts)

      ?- ->
        if boundary(body, pos - 1, [nil, ?[, ?,, ?:, ?\s, ?\n, ?\r, ?\t]) and
             boundary(body, pos + 2, [nil, ?,, ?}, ?], ?\s, ?\n, ?\r, ?\t, ?e, ?E]) do
          segment = binary_part(body, mark, pos + 2 - mark)
          zeroes(body, pos + 2, pos + 2, false, [".0", segment | parts])
        else
          zeroes(body, pos + 2, mark, false, parts)
        end
    end
  end

  defp boundary(body, pos, allowed) do
    byte = if !(pos < 0 or pos >= byte_size(body)), do: :binary.at(body, pos)
    byte in allowed
  end

  defp finish(body, _mark, []), do: body

  defp finish(body, mark, parts),
    do: IO.iodata_to_binary(Enum.reverse([binary_part(body, mark, byte_size(body) - mark) | parts]))
end
