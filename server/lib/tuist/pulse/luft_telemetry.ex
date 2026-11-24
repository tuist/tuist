defmodule Tuist.Pulse.LuftTelemetry do
  @moduledoc """
  What Luft may write to Pulse. Luft's OAuth client ID is public, so
  anyone with a Tuist account can hold a Luft session and send anything;
  this is the allowlist that keeps such a sender inside the `luft-client`
  service.

  Pulse turns resource, scope, span and log attributes into columns (typed by
  the first value written), metric names and units into tables, metric
  attributes and promoted resource attributes into labels, and span names
  into rows of its operations table. So every one of them is pinned to what
  Luft's core sends:

    * every resource is `service.name` `luft-client`; traces and logs may add
      `service.version` and `os.type`, metrics nothing (Pulse would promote
      `service.version` to a label);
    * scopes keep only their name and version;
    * spans keep their IDs, kind, times and status and the attributes in
      `@span_attributes`, each of its one type; their name is a known
      operation, or a request (`METHOD /path`) whose path segments are
      Luft's own or `*`, at most 8 of them, and anything else becomes
      `other`; events, links
      and trace state are dropped;
    * log records keep their times, severity, a string body, IDs and the
      attributes in `@log_attributes`;
    * the only metric is `luft.core.operations`, a delta monotonic integer
      sum without a unit, whose points carry exactly `luft.operation` (a
      known operation, otherwise `other`) and `luft.outcome` (one of
      `@outcomes`); any other metric or point is rejected;
    * enums outside OTLP's values become unspecified;
    * a span's start, a log record's time and a point's time must be set and
      fall between a week before and a day after receipt, or the span,
      record or point is rejected; other times outside that window are
      dropped, except a point's start, which is moved up to it (Luft's
      counting window can open long before a device wakes and sends it).

  Rejected records are counted in the partial success. Strings are cut to 256
  characters, and the encoded batch must fit in 1 MiB.
  """

  alias Tuist.Pulse.OTLP

  @service "luft-client"
  @max_bytes 1_048_576
  @text_length 256
  @past_nanos 7 * 86_400 * 1_000_000_000
  @future_nanos 86_400 * 1_000_000_000
  @max_path_segments 8

  @resource_attributes %{"service.version" => :string_value, "os.type" => :string_value}
  @span_attributes %{
    "luft.outcome" => :string_value,
    "luft.error" => :string_value,
    "http.request.method" => :string_value,
    "url.path" => :string_value,
    "http.response.status_code" => :int_value
  }
  @log_attributes %{"luft.operation" => :string_value}

  @metric "luft.core.operations"
  @outcomes ~w(ok expected_error error)
  # The operations Luft's core and desktop client record (the edges'
  # operations, thread operations, and `unknown` for unrecognized input).
  @operations ~w(
    begin_sign_in boot cached_thread cached_threads cancel_sign_in delete_account
    delete_preview finish_sign_in flush_outbox live_activity_register
    live_activity_unregister live_close live_connect live_receive live_tick live_wait
    navigate navigation_back open_notification organizations presence
    presence_disconnect preview preview_update previews projects push_enable
    push_register register_runner routes runners select_organization select_tab
    send_message sign_out snapshot start_thread switch_profile thread threads tracks
    unknown
  )
  # The path segments Luft's request spans keep; the core writes `*` for others.
  @path_segments ~w(
    api accounts projects organizations threads messages models previews tracks me
    push-devices push-device-registrations thread-live-activities thread-runners
    halls people directs read oauth2 token .well-known tuist.json luft telemetry v1
    traces logs metrics envelope *
  )
  @methods ~w(GET POST PUT PATCH DELETE)

  @span_kinds ~w(SPAN_KIND_UNSPECIFIED SPAN_KIND_INTERNAL SPAN_KIND_SERVER SPAN_KIND_CLIENT SPAN_KIND_PRODUCER SPAN_KIND_CONSUMER)a
  @status_codes ~w(STATUS_CODE_UNSET STATUS_CODE_OK STATUS_CODE_ERROR)a

  def service, do: @service
  def max_bytes, do: @max_bytes

  # Sentry is an event-only producer route. Logs and spans must use OTLP,
  # where prepare/3 applies Luft's attribute, path and timestamp policy.
  # Consume length-delimited items before inspecting the next header: binary
  # attachments must not be mistaken for envelope framing.
  def prepare_envelope(body) do
    {header, rest} = envelope_line(body)

    with {:ok, %{}} <- JSON.decode(header),
         {:ok, items} <- event_items(rest, []) do
      {:ok, IO.iodata_to_binary([header, "\n", Enum.reverse(items)])}
    else
      _ -> {:error, :invalid}
    end
  end

  defp event_items("", items), do: {:ok, items}

  defp event_items(body, items) do
    {header, rest} = envelope_line(body)

    with {:ok, %{} = item} <- JSON.decode(header),
         {:ok, payload, rest} <- envelope_payload(rest, item["length"]) do
      items = if item["type"] == "event", do: [[header, "\n", payload, "\n"] | items], else: items
      event_items(rest, items)
    else
      _ -> {:error, :invalid}
    end
  end

  defp envelope_payload(body, nil) do
    {payload, rest} = envelope_line(body)
    {:ok, payload, rest}
  end

  defp envelope_payload(body, length) when is_integer(length) and length >= 0 and length <= byte_size(body) do
    <<payload::binary-size(^length), rest::binary>> = body

    rest =
      case rest do
        "\n" <> rest -> rest
        rest -> rest
      end

    {:ok, payload, rest}
  end

  defp envelope_payload(_body, _length), do: {:error, :invalid}

  defp envelope_line(body) do
    case :binary.split(body, "\n") do
      [line, rest] -> {line, rest}
      [line] -> {line, ""}
    end
  end

  @doc """
  Decodes an OTLP export request for `signal` (see `Tuist.Pulse.OTLP.decode/2`),
  confines it to Luft and encodes it as protobuf. Returns `{:ok, body,
  rejected}`, where `rejected` counts the spans, records or data points
  dropped, or `{:error, :invalid}` or `{:error, :too_large}`.
  """
  def prepare(signal, payload, now \\ System.system_time(:nanosecond)) do
    with {:ok, request} <- OTLP.decode(signal, payload),
         {request, rejected} = confine(signal, request, {now - @past_nanos, now + @future_nanos}),
         {:ok, body} <- OTLP.encode(signal, request),
         true <- byte_size(body) <= @max_bytes || {:error, :too_large} do
      {:ok, body, rejected}
    end
  end

  defp confine("traces", request, window) do
    confine_entries(request, window, :resource_spans, :scope_spans, :spans, @resource_attributes, &span/2)
  end

  defp confine("logs", request, window) do
    confine_entries(request, window, :resource_logs, :scope_logs, :log_records, @resource_attributes, &log/2)
  end

  defp confine("metrics", request, window) do
    confine_entries(request, window, :resource_metrics, :scope_metrics, :metrics, %{}, &metric/2)
  end

  # Maps every resource's scopes' items through `item`, which returns
  # `{kept, rejected}`, and sums what was rejected.
  defp confine_entries(request, window, resources, scopes, items, resource_attributes, item) do
    {entries, rejected} =
      Enum.map_reduce(Map.get(request, resources, []), 0, fn entry, rejected ->
        {kept_scopes, rejected} =
          Enum.map_reduce(Map.get(entry, scopes, []), rejected, fn scope, rejected ->
            {kept, dropped} =
              scope
              |> Map.get(items, [])
              |> Enum.reduce({[], 0}, fn value, {kept, dropped} ->
                {new, count} = item.(value, window)
                {Enum.reverse(new, kept), dropped + count}
              end)

            {%{items => Enum.reverse(kept), :scope => scope(scope)}, rejected + dropped}
          end)

        {%{scopes => kept_scopes, :resource => resource(entry, resource_attributes)}, rejected}
      end)

    {%{resources => entries}, rejected}
  end

  defp resource(entry, allowed) do
    attributes = entry |> Map.get(:resource, %{}) |> Map.get(:attributes, []) |> attributes(allowed)
    %{attributes: [%{key: "service.name", value: %{value: {:string_value, @service}}} | attributes]}
  end

  defp scope(entry) do
    entry
    |> Map.get(:scope, %{})
    |> Map.take([:name, :version])
    |> Map.new(fn {key, value} -> {key, text(value)} end)
  end

  defp span(span, window) do
    if within?(Map.get(span, :start_time_unix_nano, 0), window) do
      confined =
        span
        |> Map.take([:trace_id, :span_id, :parent_span_id, :start_time_unix_nano])
        |> put_within(:end_time_unix_nano, Map.get(span, :end_time_unix_nano, 0), window)
        |> Map.put(:name, span_name(Map.get(span, :name, "")))
        |> Map.put(:kind, enum(Map.get(span, :kind), @span_kinds))
        |> Map.put(:attributes, attributes(Map.get(span, :attributes, []), @span_attributes))

      confined =
        case span do
          %{status: status} ->
            Map.put(confined, :status, %{
              code: enum(Map.get(status, :code), @status_codes),
              message: text(Map.get(status, :message, ""))
            })

          _ ->
            confined
        end

      {[confined], 0}
    else
      {[], 1}
    end
  end

  defp log(record, window) do
    if within?(Map.get(record, :time_unix_nano, 0), window) do
      confined =
        record
        |> Map.take([:time_unix_nano, :trace_id, :span_id])
        |> put_within(:observed_time_unix_nano, Map.get(record, :observed_time_unix_nano, 0), window)
        |> Map.put(:severity_number, severity(Map.get(record, :severity_number)))
        |> Map.put(:severity_text, text(Map.get(record, :severity_text, "")))
        |> Map.put(:attributes, attributes(Map.get(record, :attributes, []), @log_attributes))

      confined =
        case record do
          %{body: %{value: {:string_value, body}}} -> Map.put(confined, :body, %{value: {:string_value, text(body)}})
          _ -> confined
        end

      {[confined], 0}
    else
      {[], 1}
    end
  end

  # Only the shape Luft sends: a delta monotonic sum, rebuilt without a unit,
  # since Pulse names its tables after the metric's name, kind and unit.
  defp metric(
         %{
           name: @metric,
           data: {:sum, %{is_monotonic: true, aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA} = sum}
         },
         window
       ) do
    {points, dropped} =
      sum
      |> Map.get(:data_points, [])
      |> Enum.reduce({[], 0}, fn point, {kept, dropped} ->
        case point(point, window) do
          nil -> {kept, dropped + 1}
          point -> {[point | kept], dropped}
        end
      end)

    metric = %{
      name: @metric,
      data:
        {:sum,
         %{is_monotonic: true, aggregation_temporality: :AGGREGATION_TEMPORALITY_DELTA, data_points: Enum.reverse(points)}}
    }

    {[metric], dropped}
  end

  defp metric(metric, _window), do: {[], points(metric)}

  defp point(%{value: {:as_int, value}} = point, {from, _to} = window) when is_integer(value) and value >= 0 do
    time = Map.get(point, :time_unix_nano, 0)

    with true <- within?(time, window),
         {:ok, labels} <- labels(Map.get(point, :attributes, [])) do
      # A delta's window may open before the receiver's: it starts no earlier
      # than the window and no later than the point.
      start = point |> Map.get(:start_time_unix_nano, 0) |> max(from) |> min(time)
      %{start_time_unix_nano: start, time_unix_nano: time, value: point.value, attributes: labels}
    else
      _ -> nil
    end
  end

  defp point(_point, _window), do: nil

  # Exactly the metric's two labels, with values from a closed set, so a
  # sender can neither add dimensions nor invent series.
  defp labels(attributes) do
    case Map.new(attributes, fn attribute -> {attribute[:key], get_in(attribute, [:value, :value])} end) do
      %{"luft.operation" => {:string_value, operation}, "luft.outcome" => {:string_value, outcome}} = labels
      when map_size(labels) == 2 and outcome in @outcomes ->
        operation = if operation in @operations, do: operation, else: "other"

        {:ok,
         [
           %{key: "luft.operation", value: %{value: {:string_value, operation}}},
           %{key: "luft.outcome", value: %{value: {:string_value, outcome}}}
         ]}

      _ ->
        :error
    end
  end

  defp points(%{data: {_kind, %{data_points: points}}}) when is_list(points), do: length(points)
  defp points(_metric), do: 0

  defp span_name(name) when name in @operations, do: name

  defp span_name(name) do
    with [method, "/" <> path] when method in @methods <- String.split(name, " ", parts: 2),
         segments = String.split(path, "/"),
         true <- length(segments) <= @max_path_segments,
         true <- Enum.all?(segments, &(&1 in @path_segments)) do
      name
    else
      _ -> "other"
    end
  end

  # Unset times are 0, which is never within the window.
  defp within?(time, {from, to}), do: is_integer(time) and time >= from and time <= to

  defp put_within(map, key, time, window) do
    if within?(time, window), do: Map.put(map, key, time), else: map
  end

  # gpb decodes protobuf enum numbers it doesn't know as integers.
  defp enum(value, values) do
    if value in values, do: value, else: hd(values)
  end

  defp severity(value) when is_atom(value) and not is_nil(value), do: value
  defp severity(_value), do: :SEVERITY_NUMBER_UNSPECIFIED

  defp attributes(attributes, allowed) do
    for %{key: key, value: %{value: {type, value}}} <- attributes, Map.get(allowed, key) == type do
      %{key: key, value: %{value: {type, text(value)}}}
    end
  end

  defp text(value) when is_binary(value), do: String.slice(value, 0, @text_length)
  defp text(value), do: value
end
