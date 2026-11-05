defmodule Pulse.Traces.Tempo do
  @moduledoc "Bounded Tempo v1/v2 trace lookup conversion; search/discovery compatibility is separate."
  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.QueryRunner
  alias Pulse.Record.Span
  alias Pulse.Record.SpanKey
  alias Pulse.Storage
  alias Pulse.Traces.Protobuf
  alias Pulse.Traces.Search
  alias Pulse.Traces.TempoFilter

  @limit 16_777_216
  @kinds ~w(SPAN_KIND_UNSPECIFIED SPAN_KIND_INTERNAL SPAN_KIND_SERVER SPAN_KIND_CLIENT SPAN_KIND_PRODUCER SPAN_KIND_CONSUMER)
  @codes ~w(STATUS_CODE_UNSET STATUS_CODE_OK STATUS_CODE_ERROR)
  @filtered_message "Trace filtered, only a subset of spans matching the filter is returned"

  defguardp uint32?(value) when is_integer(value) and value >= 0 and value <= 4_294_967_295
  defguardp timestamp?(value) when is_integer(value) and value >= 0 and value <= 9_223_372_036_854_775_807

  def lookup(tenant, trace_id, format, filter \\ nil) do
    QueryRunner.run(tenant, :raw, fn deadline ->
      with {:ok, assembly} <- Storage.get_trace_json(tenant, trace_id, QueryRunner.storage_opts(deadline)) do
        export(assembly, format, filter)
      end
    end)
  end

  def export(assembly, format, filter \\ nil)

  def export(assembly, format, nil) do
    case NIF.tempo_trace_export(assembly, format) do
      :fallback -> reference(assembly, format)
      result -> result
    end
  end

  def export(assembly, format, filter), do: reference(assembly, format, filter)

  @doc false
  def reference(assembly, format, filter \\ nil)

  def reference(assembly, format, filter) when byte_size(assembly) <= @limit do
    with {:ok, data} <- decode_assembly(assembly),
         :ok <- coverage(data["coverage"]),
         spans when is_list(spans) <- data["spans"],
         :ok <- span_count(spans),
         :ok <- same_trace(spans, data["trace_id"]),
         {:ok, spans} <- unique(spans),
         {:ok, spans, partial?} <- TempoFilter.apply(spans, filter),
         {:ok, groups} <- groups(spans),
         trace = %{"batches" => Enum.map(groups, &resource/1)},
         {:ok, body} <- encode_filtered(trace, format, partial?),
         true <- byte_size(body) <= @limit do
      {:ok, body}
    else
      {:error, _} = error -> error
      false -> {:error, :query_resource_limit}
      _ -> {:error, :invalid_trace_export}
    end
  rescue
    _ -> {:error, :invalid_trace_export}
  end

  def reference(_assembly, _format, _filter), do: {:error, :query_resource_limit}

  defp decode_assembly(assembly) do
    case Pulse.JSON.decode(assembly) do
      {:ok, data} when is_map(data) -> {:ok, data}
      _ -> {:error, :invalid_trace_export}
    end
  end

  defp coverage(value) when value in ["all_stored_spans", "all_stored_spans_at_or_above_floor"], do: :ok
  defp coverage(_value), do: {:error, :invalid_trace_export}

  defp span_count(spans) when length(spans) <= 5000, do: :ok
  defp span_count(_spans), do: {:error, :query_resource_limit}

  defp same_trace(spans, id) do
    if Enum.all?(spans, &(&1["trace_id"] == id)), do: :ok, else: {:error, :invalid_trace_export}
  end

  defp encode_filtered(trace, format, false), do: encode(trace, format)

  defp encode_filtered(trace, "protobuf_v2", true),
    do: {:ok, Protobuf.encode(%{"trace" => trace, "status" => "PARTIAL", "message" => @filtered_message}, :response)}

  defp encode_filtered(%{"batches" => batches}, "json_v2", true) do
    trace = if batches == [], do: %{}, else: %{"resourceSpans" => batches}
    {:ok, Pulse.JSON.encode!(%{"trace" => trace, "status" => "PARTIAL", "message" => @filtered_message})}
  end

  defp encode(trace, "json"), do: {:ok, Pulse.JSON.encode!(trace)}
  defp encode(trace, "protobuf"), do: {:ok, Protobuf.encode(trace)}
  defp encode(trace, "protobuf_v2"), do: {:ok, Protobuf.encode(%{"trace" => trace}, :response)}

  defp encode(%{"batches" => batches}, "json_v2"),
    do: {:ok, Pulse.JSON.encode!(%{"trace" => %{"resourceSpans" => batches}})}

  defp encode(_trace, _format), do: {:error, :invalid_trace_export}

  defp unique([]), do: {:error, :not_found}

  defp unique(spans) do
    Enum.reduce_while(spans, {:ok, %{}, [], 0}, &keep/2)
    |> case do
      {:ok, _, kept, _} -> {:ok, Enum.reverse(kept)}
      error -> error
    end
  end

  defp keep(%{"otlp" => nil}, _state), do: {:halt, {:error, :trace_metadata_unknown}}

  defp keep(span, {:ok, seen, kept, bytes}) do
    cond do
      not Map.has_key?(span, "otlp") -> {:halt, {:error, :trace_metadata_unknown}}
      not valid_span?(span) -> {:halt, {:error, :invalid_trace_export}}
      true -> keep_known(span, seen, kept, bytes)
    end
  end

  defp keep_known(span, seen, kept, bytes) do
    key = SpanKey.encode(span)
    id = span["span_id"]

    case Map.fetch(seen, id) do
      {:ok, ^key} ->
        {:cont, {:ok, seen, kept, bytes}}

      {:ok, _} ->
        {:halt, {:error, :trace_span_id_conflict}}

      :error when bytes + byte_size(key) <= @limit ->
        {:cont, {:ok, Map.put(seen, id, key), [span | kept], bytes + byte_size(key)}}

      _ ->
        {:halt, {:error, :query_resource_limit}}
    end
  end

  defp valid_span?(map) do
    span = Span.from_map(map)

    match?({:ok, _}, Traces.id(span.trace_id, 32)) and match?({:ok, _}, Traces.id(span.span_id, 16)) and
      span.kind in 0..5 and span.status["code"] in 0..2 and Search.validate_metadata(span) == :ok and
      valid_core?(span)
  end

  # Validate every stored owner, including nonmatches, without allocating export
  # maps, decimal timestamps or base64 IDs. Only selected spans are converted.
  defp valid_core?(span) do
    optional_id?(span.parent_span_id, 16) and is_binary(span.name) and is_binary(span.trace_state) and
      uint32?(span.flags) and uint32?(span.dropped_attributes_count) and uint32?(span.dropped_events_count) and
      uint32?(span.dropped_links_count) and is_binary(span.status["message"]) and valid_owner_fields?(span)
  end

  defp valid_owner_fields?(span) do
    uint32?(span.resource_dropped_attributes_count) and is_binary(span.resource_schema_url) and
      is_binary(span.scope["name"]) and is_binary(span.scope["version"]) and
      uint32?(span.scope["dropped_attributes_count"]) and is_binary(span.scope_schema_url) and
      Enum.all?(span.events, &valid_event?/1) and Enum.all?(span.links, &valid_link?/1)
  end

  defp valid_event?(event) do
    timestamp?(event["timestamp_ns"]) and is_binary(event["name"]) and uint32?(event["dropped_attributes_count"])
  end

  defp valid_link?(link) do
    optional_id?(link["trace_id"], 32) and optional_id?(link["span_id"], 16) and is_binary(link["trace_state"]) and
      uint32?(link["flags"]) and uint32?(link["dropped_attributes_count"])
  end

  defp optional_id?(nil, _width), do: true
  defp optional_id?(value, width), do: match?({:ok, _}, Traces.id(value, width))

  defp groups(spans) do
    spans
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}, 0}, &group/2)
    |> case do
      {:ok, groups, _bytes} ->
        rows = groups |> Map.values() |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {_, rows} -> Enum.reverse(rows) end)
        {:ok, rows}

      error ->
        error
    end
  end

  defp group({span, index}, {:ok, groups, bytes}) do
    key = owner_key(span)
    extra = if Map.has_key?(groups, key), do: 0, else: byte_size(key)

    if bytes + extra > @limit do
      {:halt, {:error, :query_resource_limit}}
    else
      groups = Map.update(groups, key, {index, [span]}, fn {first, rows} -> {first, [span | rows]} end)
      {:cont, {:ok, groups, bytes + extra}}
    end
  end

  defp owner_key(span) do
    SpanKey.encode([
      span["otlp"]["resource"],
      span["resource_dropped_attributes_count"],
      span["resource_schema_url"],
      span["scope"]["name"],
      span["scope"]["version"],
      span["scope"]["dropped_attributes_count"],
      span["otlp"]["scope"],
      span["scope_schema_url"]
    ])
  end

  defp resource([span | _] = spans) do
    typed = span["otlp"]
    scope = span["scope"]

    resource =
      %{} |> attrs(typed["resource"]) |> number("droppedAttributesCount", span["resource_dropped_attributes_count"])

    scope =
      %{}
      |> string("name", scope["name"])
      |> string("version", scope["version"])
      |> attrs(typed["scope"])
      |> number("droppedAttributesCount", scope["dropped_attributes_count"])

    scope_spans =
      %{"scope" => scope, "spans" => Enum.map(spans, &span/1)} |> string("schemaUrl", span["scope_schema_url"])

    %{"resource" => resource, "scopeSpans" => [scope_spans]} |> string("schemaUrl", span["resource_schema_url"])
  end

  defp span(span) do
    %{}
    |> id("traceId", span["trace_id"])
    |> id("spanId", span["span_id"])
    |> id("parentSpanId", span["parent_span_id"])
    |> string("traceState", span["trace_state"])
    |> string("name", span["name"])
    |> enum("kind", span["kind"], @kinds)
    |> number("startTimeUnixNano", span["timestamp_ns"], true)
    |> number("endTimeUnixNano", span["end_timestamp_ns"], true)
    |> attrs(span["otlp"]["attributes"])
    |> number("droppedAttributesCount", span["dropped_attributes_count"])
    |> number("droppedEventsCount", span["dropped_events_count"])
    |> number("droppedLinksCount", span["dropped_links_count"])
    |> number("flags", span["flags"])
    |> children("events", span["events"], span["otlp"]["events"])
    |> children("links", span["links"], span["otlp"]["links"])
    |> status(span["status"])
  end

  defp children(map, _name, [], []), do: map

  defp children(map, name, rows, attrs) when length(rows) == length(attrs),
    do: Map.put(map, name, Enum.zip_with(rows, attrs, &child(name, &1, &2)))

  defp child("events", row, typed),
    do:
      %{}
      |> number("timeUnixNano", row["timestamp_ns"], true)
      |> string("name", row["name"])
      |> attrs(typed)
      |> number("droppedAttributesCount", row["dropped_attributes_count"])

  defp child("links", row, typed),
    do:
      %{}
      |> id("traceId", row["trace_id"])
      |> id("spanId", row["span_id"])
      |> string("traceState", row["trace_state"])
      |> attrs(typed)
      |> number("droppedAttributesCount", row["dropped_attributes_count"])
      |> number("flags", row["flags"])

  defp status(map, status) do
    value = %{} |> string("message", status["message"]) |> enum("code", status["code"], @codes)
    Map.put(map, "status", value)
  end

  defp attrs(map, []), do: map
  defp attrs(map, values) when is_list(values), do: Map.put(map, "attributes", values)
  defp string(map, _key, ""), do: map
  defp string(map, key, value) when is_binary(value), do: Map.put(map, key, value)
  defp number(map, key, value, quoted \\ false)
  defp number(map, _key, 0, _quoted), do: map

  defp number(map, key, value, true) when timestamp?(value), do: Map.put(map, key, Integer.to_string(value))

  defp number(map, key, value, false) when uint32?(value), do: Map.put(map, key, value)

  defp enum(map, _key, 0, _values), do: map
  defp enum(map, key, value, values), do: Map.put(map, key, Enum.fetch!(values, value))
  defp id(map, _key, nil), do: map
  defp id(map, key, value), do: Map.put(map, key, value |> Base.decode16!(case: :mixed) |> Base.encode64())
end
