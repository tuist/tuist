defmodule Pulse.OTLP.Traces do
  @moduledoc "Decode OTLP trace JSON (including the native protobuf decoder's JSON-shaped output)."
  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Value
  alias Pulse.Record.Span

  @max_timestamp 9_223_372_036_854_775_807
  @max_u32 4_294_967_295
  # Atom key: decoded JSON and native protobuf maps only have binary keys.
  @duplicates :duplicate_attributes

  @rejection_reasons ~w(invalid_span invalid_trace_id invalid_span_id invalid_parent_span_id invalid_start_time
                        invalid_end_time end_before_start invalid_name invalid_trace_state invalid_kind invalid_status
                        empty_attribute_key invalid_attribute_value invalid_flags
                        invalid_dropped_count invalid_event invalid_link)a

  @doc "Fixed vocabulary of per-span rejection reasons returned by `decode_detailed/1`."
  def rejection_reasons, do: @rejection_reasons

  def decode(payload), do: summarize(decode_detailed(payload))

  def decode_protobuf(body), do: summarize(decode_protobuf_detailed(body))

  @doc """
  Like `decode/1`, but also returns rejected spans grouped by
  `{reason, service}`, where `reason` is one of `rejection_reasons/0`.
  """
  def decode_detailed(%{} = payload) do
    with :ok <- shape(payload),
         :ok <- Pulse.IngestLimits.validate(:otlp_traces, payload),
         payload = normalize(payload),
         :ok <- metadata(payload) do
      {spans, rejections} =
        Enum.reduce(Map.get(payload, "resourceSpans", []), {[], %{}}, &decode_resource/2)

      spans = Enum.reverse(spans)

      with {:ok, _bytes} <- NIF.trace_payload_size(Enum.map(spans, &Span.to_map/1), 16_777_216),
           do: {:ok, spans, rejections |> Map.values() |> Enum.sum(), rejections}
    end
  end

  def decode_detailed(_), do: {:error, :invalid_otlp}

  def decode_protobuf_detailed(body) do
    case NIF.decode_otlp_traces(body, native_limits()) do
      {:ok, payload} -> decode_detailed(payload)
      {:error, _} = error -> error
    end
  end

  defp summarize({:ok, spans, rejected, _rejections}), do: {:ok, spans, rejected}
  defp summarize(error), do: error

  defp decode_resource(resource, acc) do
    res = Map.get(resource, "resource", %{})
    attrs = attributes(res)
    typed = typed_attributes(res)
    # Resource/scope counts have already passed whole-request metadata validation.
    {:ok, dropped} = dropped_attributes(res)

    base = %Span{
      resource: attrs,
      service: string_service(typed),
      resource_dropped_attributes_count: dropped,
      resource_schema_url: Map.get(resource, "schemaUrl", ""),
      otlp: %{"version" => 1, "resource" => typed}
    }

    Enum.reduce(Map.get(resource, "scopeSpans", []), acc, &decode_scope_spans(&1, base, &2))
  end

  defp decode_scope_spans(scope, base, acc) do
    base = %{
      base
      | scope: decode_scope(Map.get(scope, "scope", %{})),
        scope_schema_url: Map.get(scope, "schemaUrl", ""),
        otlp: Map.put(base.otlp, "scope", typed_attributes(Map.get(scope, "scope", %{})))
    }

    Enum.reduce(Map.get(scope, "spans", []), acc, &collect_span(&1, base, &2))
  end

  defp collect_span(raw, base, {spans, rejections}) do
    case span(raw, base) do
      {:ok, span} -> {[span | spans], rejections}
      {:error, reason} -> {spans, Map.update(rejections, {reason, base.service}, 1, &(&1 + 1))}
    end
  end

  # OTLP requires unique attribute keys, but common SDKs emit repeats: the
  # Erlang SDK keeps atom and binary keys apart (`:"client.address"` and
  # `"client.address"`), and the Rust SDK and tracing-opentelemetry append a
  # re-recorded field. Collectors and Tempo keep such spans. Keep the last
  # occurrence of each owner-level key, as repeated attribute sets mean, and
  # count the discarded ones as dropped. Nested kvlists stay strict.
  defp normalize(payload) do
    update_list(payload, "resourceSpans", fn resource ->
      resource
      |> update_map("resource", &dedupe/1)
      |> update_list("scopeSpans", fn scope ->
        scope |> update_map("scope", &dedupe/1) |> update_list("spans", &normalize_span/1)
      end)
    end)
  end

  defp normalize_span(%{} = span),
    do: span |> dedupe() |> update_list("events", &dedupe/1) |> update_list("links", &dedupe/1)

  defp normalize_span(span), do: span

  defp update_map(%{} = map, key, fun) do
    case map do
      %{^key => %{} = value} -> %{map | key => fun.(value)}
      _ -> map
    end
  end

  defp update_map(other, _key, _fun), do: other

  defp update_list(%{} = map, key, fun) do
    case map do
      %{^key => list} when is_list(list) -> %{map | key => Enum.map(list, fun)}
      _ -> map
    end
  end

  defp update_list(other, _key, _fun), do: other

  defp dedupe(%{"attributes" => pairs} = owner) when is_list(pairs) do
    {kept, _seen, removed} =
      pairs
      |> Enum.reverse()
      |> Enum.reduce({[], MapSet.new(), 0}, fn
        %{"key" => key} = pair, {kept, seen, removed} when is_binary(key) ->
          if MapSet.member?(seen, key),
            do: {kept, seen, removed + 1},
            else: {[pair | kept], MapSet.put(seen, key), removed}

        pair, {kept, seen, removed} ->
          {[pair | kept], seen, removed}
      end)

    if removed == 0, do: owner, else: %{owner | "attributes" => kept} |> Map.put(@duplicates, removed)
  end

  defp dedupe(owner), do: owner

  defp dropped_attributes(owner) do
    with {:ok, dropped} <- u32(Map.get(owner, "droppedAttributesCount", 0)),
         do: {:ok, min(dropped + Map.get(owner, @duplicates, 0), @max_u32)}
  end

  defp native_limits do
    l = Pulse.IngestLimits.config()

    {l.max_records, l.max_attributes, l.max_key_bytes, l.max_value_bytes, l.max_attribute_bytes, l.max_depth,
     l.max_nodes, l.max_trace_nodes}
  end

  defp shape(payload) do
    if containers?(Map.get(payload, "resourceSpans", []), "scopeSpans", "spans"),
      do: :ok,
      else: {:error, :invalid_otlp}
  end

  defp containers?(resources, scopes_key, records_key) when is_list(resources) do
    Enum.all?(resources, fn
      %{} = resource ->
        scopes = Map.get(resource, scopes_key, [])

        is_map(Map.get(resource, "resource", %{})) and is_list(scopes) and
          Enum.all?(scopes, fn
            %{} = scope -> is_map(Map.get(scope, "scope", %{})) and is_list(Map.get(scope, records_key, []))
            _ -> false
          end)

      _ ->
        false
    end)
  end

  defp containers?(_, _, _), do: false

  defp metadata(payload) do
    valid? =
      Enum.all?(Map.get(payload, "resourceSpans", []), fn resource ->
        res = Map.get(resource, "resource", %{})

        valid_attributes?(res) and valid_count?(Map.get(res, "droppedAttributesCount", 0)) and
          is_binary(Map.get(resource, "schemaUrl", "")) and
          Enum.all?(Map.get(resource, "scopeSpans", []), fn scope ->
            s = Map.get(scope, "scope", %{})

            valid_attributes?(s) and valid_count?(Map.get(s, "droppedAttributesCount", 0)) and
              is_binary(Map.get(s, "name", "")) and is_binary(Map.get(s, "version", "")) and
              is_binary(Map.get(scope, "schemaUrl", ""))
          end)
      end)

    if valid?, do: :ok, else: {:error, :invalid_otlp}
  end

  defp span(%{} = raw, base) do
    with {:ok, trace_id} <- reason(id(raw["traceId"], 32), :invalid_trace_id),
         {:ok, span_id} <- reason(id(raw["spanId"], 16), :invalid_span_id),
         {:ok, parent} <- reason(parent_id(raw["parentSpanId"]), :invalid_parent_span_id),
         {:ok, start} <- reason(timestamp(Map.get(raw, "startTimeUnixNano", 0)), :invalid_start_time),
         {:ok, finish} <- reason(timestamp(Map.get(raw, "endTimeUnixNano", 0)), :invalid_end_time),
         :ok <- if(finish >= start, do: :ok, else: {:error, :end_before_start}),
         :ok <- valid_span(raw),
         {:ok, flags} <- reason(u32(Map.get(raw, "flags", 0)), :invalid_flags),
         {:ok, dropped_attributes} <- reason(dropped_attributes(raw), :invalid_dropped_count),
         {:ok, dropped_events} <- reason(u32(Map.get(raw, "droppedEventsCount", 0)), :invalid_dropped_count),
         {:ok, dropped_links} <- reason(u32(Map.get(raw, "droppedLinksCount", 0)), :invalid_dropped_count),
         {:ok, events} <- reason(events(Map.get(raw, "events", [])), :invalid_event),
         {:ok, links} <- reason(links(Map.get(raw, "links", [])), :invalid_link) do
      {:ok,
       %{
         base
         | timestamp_ns: start,
           end_timestamp_ns: finish,
           trace_id: trace_id,
           span_id: span_id,
           parent_span_id: parent,
           trace_state: Map.get(raw, "traceState", ""),
           flags: flags,
           name: Map.get(raw, "name", ""),
           kind: int_zero(Map.get(raw, "kind", 0)),
           status:
             Map.merge(%{"code" => 0, "message" => ""}, Map.get(raw, "status", %{})) |> Map.update!("code", &int_zero/1),
           attributes: attributes(raw),
           events: events,
           links: links,
           dropped_attributes_count: dropped_attributes,
           dropped_events_count: dropped_events,
           dropped_links_count: dropped_links,
           otlp:
             Map.merge(base.otlp, %{
               "attributes" => typed_attributes(raw),
               "events" => Enum.map(Map.get(raw, "events", []), &typed_attributes/1),
               "links" => Enum.map(Map.get(raw, "links", []), &typed_attributes/1)
             })
       }}
    end
  end

  defp span(_, _), do: {:error, :invalid_span}

  defp reason({:ok, _} = ok, _reason), do: ok
  defp reason(_, reason), do: {:error, reason}

  defp string_service(attributes) do
    Enum.reduce(attributes, nil, fn
      %{"key" => "service.name", "value" => %{"stringValue" => value}}, _ -> value
      %{"key" => "service.name"}, _ -> nil
      _, service -> service
    end)
  end

  defp valid_span(raw) do
    status = Map.get(raw, "status", %{})

    cond do
      not is_binary(Map.get(raw, "name", "")) -> {:error, :invalid_name}
      not is_binary(Map.get(raw, "traceState", "")) -> {:error, :invalid_trace_state}
      int_zero(Map.get(raw, "kind", 0)) not in 0..5 -> {:error, :invalid_kind}
      not (is_map(status) and int_zero(Map.get(status, "code", 0)) in 0..2) -> {:error, :invalid_status}
      not is_binary(Map.get(status, "message", "")) -> {:error, :invalid_status}
      not valid_attributes?(raw) -> {:error, attribute_reason(Map.get(raw, "attributes"))}
      true -> :ok
    end
  end

  # Classify only already-invalid owner attributes; nested values report as values.
  defp attribute_reason(pairs) when is_list(pairs) do
    keys = for %{"key" => key} when is_binary(key) <- pairs, do: key

    if "" in keys do
      :empty_attribute_key
    else
      :invalid_attribute_value
    end
  end

  defp attribute_reason(_), do: :invalid_attribute_value

  def id(value, length) when is_binary(value) and byte_size(value) == length do
    case Base.decode16(value, case: :mixed) do
      {:ok, bytes} -> if bytes == :binary.copy(<<0>>, div(length, 2)), do: :error, else: {:ok, String.downcase(value)}
      _ -> :error
    end
  end

  def id(_, _), do: :error
  defp parent_id(value) when value in [nil, ""], do: {:ok, nil}
  defp parent_id(value), do: id(value, 16)

  defp timestamp(value), do: Value.integer(value, 0, @max_timestamp)

  defp events(values) when is_list(values) do
    collect(values, fn
      %{} = e ->
        with {:ok, ts} <- timestamp(Map.get(e, "timeUnixNano", 0)),
             true <- is_binary(Map.get(e, "name", "")),
             true <- valid_attributes?(e),
             {:ok, dropped} <- dropped_attributes(e) do
          {:ok,
           %{
             "timestamp_ns" => ts,
             "name" => Map.get(e, "name", ""),
             "attributes" => attributes(e),
             "dropped_attributes_count" => dropped
           }}
        else
          _ -> :error
        end

      _ ->
        :error
    end)
  end

  defp events(_), do: :error

  defp links(values) when is_list(values) do
    collect(values, fn
      %{} = link ->
        with {:ok, tid} <- id(link["traceId"], 32),
             {:ok, sid} <- id(link["spanId"], 16),
             true <- valid_attributes?(link) and is_binary(Map.get(link, "traceState", "")),
             {:ok, dropped} <- dropped_attributes(link),
             {:ok, flags} <- u32(Map.get(link, "flags", 0)) do
          {:ok,
           %{
             "trace_id" => tid,
             "span_id" => sid,
             "trace_state" => Map.get(link, "traceState", ""),
             "attributes" => attributes(link),
             "dropped_attributes_count" => dropped,
             "flags" => flags
           }}
        else
          _ -> :error
        end

      _ ->
        :error
    end)
  end

  defp links(_), do: :error

  defp collect(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn v, {:ok, acc} ->
      case fun.(v) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      _ -> :error
    end
  end

  defp decode_scope(scope) when is_map(scope) do
    {:ok, dropped} = dropped_attributes(scope)

    %{
      "name" => Map.get(scope, "name", ""),
      "version" => Map.get(scope, "version", ""),
      "attributes" => attributes(scope),
      "dropped_attributes_count" => dropped
    }
  end

  defp decode_scope(_), do: %{}

  defp int_zero(v) when is_float(v) and v == 0.0, do: 0
  defp int_zero(v), do: v
  defp u32(v), do: Value.integer(v, 0, 4_294_967_295)
  defp valid_count?(v), do: match?({:ok, _}, u32(v))

  defp valid_attributes?(value) do
    pairs = Map.get(value, "attributes", [])

    is_list(pairs) and match?({:ok, _, _}, Value.attributes(value)) and
      Enum.all?(pairs, fn
        %{"key" => key} = pair when is_binary(key) -> valid_value?(Map.get(pair, "value", %{}))
        _ -> false
      end)
  end

  @any_value_fields ~w(stringValue boolValue doubleValue intValue bytesValue arrayValue kvlistValue)
  defp valid_value?(v) when is_map(v) do
    # OTLP JSON must ignore unknown message fields, including inside AnyValue.
    # Safety preflight still counts the supplied tree before this filtering.
    known = Map.take(v, @any_value_fields)
    map_size(known) == 0 or (map_size(known) == 1 and Enum.all?(known, &valid_value_pair?/1))
  end

  defp valid_value?(_), do: false

  defp valid_value_pair?({"stringValue", s}), do: is_binary(s)
  defp valid_value_pair?({"boolValue", b}), do: is_boolean(b)
  defp valid_value_pair?({"doubleValue", n}), do: match?({:ok, _, _}, Value.decode(%{"doubleValue" => n}))

  defp valid_value_pair?({"intValue", n}),
    do: match?({:ok, _}, Value.integer(n, -9_223_372_036_854_775_808, 9_223_372_036_854_775_807))

  defp valid_value_pair?({"bytesValue", b}) when is_binary(b), do: match?({:ok, _}, Base.decode64(b))

  defp valid_value_pair?({"arrayValue", %{} = array}) do
    list = Map.get(array, "values", [])
    is_list(list) and Enum.all?(list, &valid_value?/1)
  end

  defp valid_value_pair?({"kvlistValue", %{} = kvlist}),
    do: valid_attributes?(%{"attributes" => Map.get(kvlist, "values", [])})

  defp valid_value_pair?(_), do: false

  defp attributes(owner) do
    {:ok, values, _typed} = Value.attributes(owner)
    values
  end

  defp typed_attributes(owner) do
    {:ok, _values, typed} = Value.attributes(owner)
    typed
  end
end
