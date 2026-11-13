defmodule Tuist.Pulse.Errors do
  @moduledoc false
  alias Tuist.Pulse.Table
  alias Tuist.Tests.Sanitizer

  def issue_id?(id), do: is_binary(id) and byte_size(id) == 67 and Regex.match?(~r/\Av1_[0-9a-f]{64}\z/, id)
  def event_id?(id), do: is_binary(id) and byte_size(id) == 32 and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

  def list(opts, call) do
    with {:ok, rows} <- fetch("query_errors", opts, %{}, call),
         {:ok, events} <- project(rows, nil, opts.params) do
      # Native summaries have no occurrence trend. Build every summary from the
      # same complete, filtered snapshot, never from a numbered issue/event page.
      rows =
        events
        |> Enum.group_by(&{&1["project"], &1["issue_id"]})
        |> Enum.map(fn {_, events} -> summary(events, opts) end)

      {rows, meta} = Table.page(rows, without_filters(opts))
      {:ok, %{rows: rows, series: [], meta: meta, warnings: []}}
    end
  end

  defp without_filters(opts), do: %{opts | params: Map.drop(opts.params, ~w(project environment release service level))}

  defp summary(events, opts) do
    events = Enum.sort_by(events, &{String.to_integer(&1["timestamp_ns"]), &1["event_id"]}, :desc)
    latest = hd(events)

    %{
      "issue_id" => latest["issue_id"],
      "project" => latest["project"],
      "service" => latest["service"],
      "title" => latest["title"],
      "level" => latest["level"],
      "platform" => latest["platform"],
      "culprit" => latest["culprit"],
      "occurrence_series" => occurrence_series(events, opts),
      "count" => length(events),
      "first_seen_ns" => String.to_integer(List.last(events)["timestamp_ns"]),
      "last_seen_ns" => String.to_integer(latest["timestamp_ns"]),
      "latest_event_id" => latest["event_id"]
    }
  end

  def issue(id, opts, call) do
    with {:ok, rows} <- fetch("query_errors", opts, %{"issue_id" => id}, call),
         {:ok, events} <- project(rows, id, opts.params) do
      case events do
        [] ->
          {:error, :not_found}

        _ ->
          latest_event = Enum.max_by(events, &{String.to_integer(&1["timestamp_ns"]), &1["event_id"]})
          occurrence_series = occurrence_series(events, opts)

          {page, meta} =
            Table.page(events, %{without_filters(opts) | sort_by: "timestamp_ns", sort_order: "desc", query: ""})

          {:ok,
           %{
             issue: summary(events, opts),
             latest_event: latest_event,
             occurrence_series: occurrence_series,
             events: page,
             meta: meta,
             warnings: []
           }}
      end
    end
  end

  defp occurrence_series(events, opts) do
    # Supported periods divide into 60 equal-width buckets. Timestamps label
    # bucket starts; buckets are half-open except the last includes opts.finish,
    # matching the source's inclusive interval without counting boundaries twice.
    start = opts.finish - opts.seconds
    width = div(opts.seconds, 60)

    counts =
      Enum.frequencies_by(events, fn event ->
        offset = String.to_integer(event["timestamp_ns"]) - start * 1_000_000_000
        offset |> div(width * 1_000_000_000) |> max(0) |> min(59)
      end)

    Enum.map(0..59, fn bucket -> [start + bucket * width, Map.get(counts, bucket, 0)] end)
  end

  def event(issue, id, opts, call) do
    with {:ok, rows} <- fetch("query_errors", opts, %{"issue_id" => issue, "event_id" => id}, call),
         {:ok, events} <- project(rows, issue, opts.params) do
      case events do
        [%{"event_id" => ^id} = event] -> {:ok, %{event: event, warnings: []}}
        [] -> {:error, :not_found}
        _ -> {:error, :malformed_response}
      end
    end
  end

  defp fetch(tool, opts, extra, call) do
    args = opts.params |> Map.take(~w(project environment release service)) |> Map.reject(fn {_, v} -> v == "" end)
    args = Map.reject(args, fn {key, _} -> Map.get(opts.params, key <> "_op", "eq") != "eq" end)

    args =
      args
      |> Map.merge(extra)
      |> Map.merge(%{
        "start_ts_ns" => (opts.finish - opts.seconds) * 1_000_000_000,
        "end_ts_ns" => opts.finish * 1_000_000_000,
        "limit" => 5000
      })

    fetch_pages(tool, args, call, [], nil, nil, 0, 0)
  end

  # Native cursors fence the complete result snapshot. Never merge changed
  # snapshots or silently discard a byte-bounded page's continuation.
  defp fetch_pages(tool, args, call, acc, snapshot, expected, pages, bytes) when pages < 32 do
    with {:ok, body} <- call.(tool, args),
         {:ok, page} <- page(body),
         %{"results" => rows, "snapshot_id" => current, "matched_results" => count, "next_cursor" => cursor} <- page,
         true <- valid_page?(rows, current, count),
         true <- snapshot in [nil, current] and expected in [nil, count],
         true <- length(acc) + length(rows) <= count do
      rows = acc ++ rows
      bytes = bytes + byte_size(JSON.encode!(page))

      cond do
        bytes > 33_554_432 ->
          {:error, :query_result_limit}

        is_nil(cursor) and length(rows) == count ->
          {:ok, rows}

        valid_cursor?(cursor, page["results"], args["cursor"]) ->
          fetch_pages(tool, Map.put(args, "cursor", cursor), call, rows, current, count, pages + 1, bytes)

        true ->
          {:error, :malformed_response}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :malformed_response}
    end
  end

  defp fetch_pages(_, _, _, _, _, _, _, _), do: {:error, :query_result_limit}

  defp valid_page?(rows, snapshot, count),
    do: is_list(rows) and is_binary(snapshot) and is_integer(count) and count in 0..5000

  defp valid_cursor?(cursor, rows, previous),
    do: is_binary(cursor) and byte_size(cursor) in 1..4096 and rows != [] and cursor != previous

  defp page(%{
         "jsonrpc" => "2.0",
         "id" => 1,
         "result" => %{"isError" => false, "content" => [%{"type" => "text", "text" => text}]}
       })
       when is_binary(text) and byte_size(text) <= 2_097_152 do
    case JSON.decode(text) do
      {:ok, %{} = page} -> {:ok, page}
      _ -> {:error, :malformed_response}
    end
  end

  defp page(%{"result" => %{"isError" => true, "content" => [%{"type" => "text", "text" => text}]}})
       when is_binary(text) do
    cond do
      String.starts_with?(text, [
        ":query_result_limit",
        ":query_scan_limit",
        ":query_execution_limit",
        ":query_sample_limit",
        ":query_decoded_limit",
        ":query_resource_limit"
      ]) ->
        {:error, :query_result_limit}

      String.starts_with?(text, ":query_timeout") ->
        {:error, :timeout}

      String.starts_with?(text, ":query_overloaded") ->
        {:error, :rate_limited}

      String.starts_with?(text, ":error_query_reset_required") ->
        {:error, :query_reset_required}

      true ->
        {:error, :upstream_error}
    end
  end

  defp page(%{"result" => %{"isError" => true}}), do: {:error, :upstream_error}
  defp page(_), do: {:error, :malformed_response}

  defp ns?(n), do: is_integer(n) and n >= 0 and n <= 9_223_372_036_854_775_807

  defp project(rows, issue, params) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case project_event(row, issue) do
        {:ok, event} ->
          metadata =
            Map.merge(row, %{
              "environment" => environment(row["event"]),
              "release" => lenient_string(row["event"]["release"])
            })

          {:cont, {:ok, if(Table.filters?(metadata, params), do: [event | acc], else: acc)}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp project_event(%{"event" => event} = row, issue) when is_map(event) do
    if valid_event?(row, issue) do
      exceptions = event_exceptions(event)
      title = title(event, List.last(exceptions) || %{})
      culprit = culprit(List.last(exceptions) || %{})

      exceptions = Enum.map(exceptions, &project_exception/1)

      last = List.last(exceptions) || %{}

      {:ok,
       ~w(event_id issue_id project service trace_id span_id)
       |> Map.new(&{&1, text(row[&1])})
       |> Map.merge(%{
         "timestamp_ns" => Integer.to_string(row["timestamp_ns"]),
         "timestamp" => Integer.to_string(row["timestamp_ns"]),
         "level" =>
           Map.get(
             %{
               "log" => "info",
               "critical" => "fatal",
               10 => "debug",
               20 => "info",
               30 => "warning",
               40 => "error",
               50 => "fatal"
             },
             event["level"],
             text(event["level"]) || "error"
           ),
         "environment" => text(environment(event)),
         "release" => text(lenient_string(event["release"])),
         "title" => title,
         "platform" => text(event["platform"]),
         "culprit" => culprit,
         "tags" => metadata(tags(event["tags"])),
         "contexts" => metadata(object(event["contexts"])),
         "extra" => metadata(object(event["extra"])),
         "modules" => metadata(object(event["modules"])),
         "exceptions" => exceptions,
         "exception" => last
       })}
    else
      {:error, :malformed_response}
    end
  end

  defp project_event(_, _), do: {:error, :malformed_response}

  defp event_exceptions(event) do
    exceptions =
      case Map.get(event, "exception", event["sentry.interfaces.Exception"]) do
        %{"values" => values} -> values
        %{} = exception -> [exception]
        values -> values
      end

    if is_list(exceptions), do: exceptions |> Enum.filter(&is_map/1) |> Enum.take(-10), else: []
  end

  defp valid_event?(row, issue) do
    (is_nil(issue) or row["issue_id"] == issue) and issue_id?(row["issue_id"]) and event_id?(row["event_id"]) and
      ns?(row["timestamp_ns"]) and is_binary(row["project"]) and is_binary(row["service"])
  end

  defp project_exception(exception) do
    frames =
      exception |> Map.get("stacktrace", exception["sentry.interfaces.Stacktrace"]) |> object() |> Map.get("frames", [])

    frames = if is_list(frames), do: frames |> Enum.filter(&is_map/1) |> Enum.take(-100), else: []
    %{"type" => text(exception["type"]), "value" => display(exception["value"]), "frames" => Enum.map(frames, &frame/1)}
  end

  defp object(value) when is_map(value), do: value
  defp object(_), do: %{}
  defp text(value) when is_binary(value), do: String.slice(value, 0, 4096)
  defp text(_), do: nil

  defp culprit(exception) do
    frames =
      exception |> Map.get("stacktrace", exception["sentry.interfaces.Stacktrace"]) |> object() |> Map.get("frames")

    frames = if is_list(frames), do: Enum.filter(frames, &is_map/1), else: []
    in_app = Enum.filter(frames, &(&1["in_app"] == true))
    frame = List.last(if in_app == [], do: frames, else: in_app) || %{}
    location = [text(frame["module"]) || text(frame["filename"]), text(frame["function"])]

    case Enum.reject(location, &(&1 in [nil, ""])) do
      [] -> nil
      parts -> parts |> Enum.join(".") |> text()
    end
  end

  defp tags(value) when is_map(value), do: value

  defp tags(value) when is_list(value) do
    # Bound pair normalization too, including malformed entries.
    pairs = value |> Enum.take(51) |> Enum.filter(&match?([key, _] when is_binary(key), &1))
    result = Map.new(pairs, fn [key, value] -> {key, value} end)
    if length(value) > 50, do: Map.put(result, "[TRUNCATED]", "[TRUNCATED]"), else: result
  end

  defp tags(_), do: %{}

  # Only these four recorded sections are projected. The existing text sanitizer
  # handles embedded credentials; telemetry's sanitizer is display-only and does
  # not redact keys. Bound traversal independently of serialized output: depth 5,
  # 50 entries/container, 200 nodes/section, 128-byte keys, 1024-byte text. Each
  # section's final JSON is at most 4096 bytes (16384 across section values).
  defp metadata(value) do
    {safe, _remaining} = metadata(value, 0, 200)
    if byte_size(JSON.encode!(safe)) <= 4096, do: safe, else: %{"[TRUNCATED]" => "[TRUNCATED]"}
  end

  defp metadata(_, depth, remaining) when depth > 5 or remaining <= 0, do: {"[TRUNCATED]", max(remaining - 1, 0)}

  defp metadata(value, depth, remaining) when is_map(value) do
    entries = Enum.take(value, 51)

    {safe, remaining} =
      entries
      |> Enum.take(50)
      |> Enum.reduce_while({%{}, remaining - 1}, fn {key, value}, {acc, left} ->
        cond do
          left <= 0 ->
            {:halt, {Map.put(acc, "[TRUNCATED]", "[TRUNCATED]"), left}}

          not is_binary(key) or byte_size(key) > 128 ->
            {:cont, {Map.put(acc, "[TRUNCATED]", "[TRUNCATED]"), left - 1}}

          sensitive_key?(key) ->
            {:cont, {Map.put(acc, Sanitizer.sanitize(key), "[REDACTED]"), left - 1}}

          true ->
            {safe, left} = metadata(value, depth + 1, left)
            {:cont, {Map.put(acc, Sanitizer.sanitize(key), safe), left}}
        end
      end)

    safe = if length(entries) > 50, do: Map.put(safe, "[TRUNCATED]", "[TRUNCATED]"), else: safe
    {safe, remaining}
  end

  defp metadata(value, depth, remaining) when is_list(value) do
    {safe, left} =
      value
      |> Enum.take(50)
      |> Enum.reduce_while({[], remaining - 1}, fn value, {acc, left} ->
        if left <= 0 do
          {:halt, {["[TRUNCATED]" | acc], left}}
        else
          {safe, left} = metadata(value, depth + 1, left)
          {:cont, {[safe | acc], left}}
        end
      end)

    safe = Enum.reverse(safe)
    {if(length(value) > 50, do: safe ++ ["[TRUNCATED]"], else: safe), left}
  end

  defp metadata(value, _depth, remaining) when is_binary(value) do
    # Sanitize a bounded prefix before limiting the displayed text. Never turn
    # caller-controlled strings into HTML; consumers must escape ordinary text.
    prefix = value |> byte_prefix(4096) |> Sanitizer.sanitize() |> String.replace("<REDACTED>", "[REDACTED]")
    truncated? = byte_size(value) > 1024 or byte_size(prefix) > 1024
    safe = byte_prefix(prefix, 1024)
    {if(truncated?, do: safe <> "[TRUNCATED]", else: safe), remaining - 1}
  end

  defp metadata(value, _depth, remaining) when is_number(value) or is_boolean(value) or is_nil(value),
    do: {value, remaining - 1}

  defp metadata(_, _, remaining), do: {"[TRUNCATED]", remaining - 1}

  defp byte_prefix(value, limit) when byte_size(value) <= limit, do: value

  defp byte_prefix(value, limit) do
    prefix = binary_part(value, 0, limit)
    # At most three trailing bytes can belong to an incomplete UTF-8 codepoint.
    if String.valid?(prefix), do: prefix, else: byte_prefix(prefix, limit - 1)
  end

  defp sensitive_key?(key) do
    normalized = key |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")

    String.contains?(
      normalized,
      ~w(password passwd token secret authorization authentication cookie session apikey privatekey credential email phone ipaddress creditcard)
    ) or
      normalized in ~w(pwd auth jwt bearer dsn user userid username address ip remoteaddr ssn request headers vars locals stacktrace sentryinterfacesuser sentryinterfacesrequest sentryinterfacesstacktrace)
  end

  defp environment(%{"environment" => value}) when is_binary(value) and value != "", do: value

  defp environment(event) do
    value =
      case event["tags"] do
        %{} = tags -> tags["environment"]
        tags when is_list(tags) -> tags |> Enum.find(&match?(["environment", _], &1)) |> List.wrap() |> List.last()
        _ -> nil
      end

    String.trim(lenient_string(value) || "")
  end

  defp lenient_string(value) when is_binary(value), do: value
  defp lenient_string(true), do: "True"
  defp lenient_string(false), do: "False"
  defp lenient_string(value) when is_integer(value), do: Integer.to_string(value)

  defp lenient_string(value) when is_float(value) and abs(value) < 9_007_199_254_740_992 do
    integer = trunc(value)
    if integer == 0 and String.starts_with?(Float.to_string(value), "-"), do: "-0", else: Integer.to_string(integer)
  end

  defp lenient_string(_), do: nil

  # Mirror Pulse.Errors.title/1 for occurrence-filtered groups without exposing
  # arbitrary payload fields. Canonical JSON keeps legacy structured messages
  # consistent with the native grouped listing.
  defp title(event, exception) do
    message =
      message(Map.get(event, "logentry", event["sentry.interfaces.Message"])) || message(event["message"]) || "Error"

    value = display(exception["value"]) || message
    type = text(exception["type"]) || ""
    String.slice(if(type == "", do: value, else: type <> ": " <> value), 0, 500)
  end

  defp message(value) when value in [nil, false], do: nil
  defp message(%{} = value), do: text(value["formatted"]) || text(value["message"])
  defp message(value), do: display(value)
  defp display(nil), do: nil
  defp display(value) when is_binary(value), do: text(value)
  defp display(value), do: value |> canonical() |> IO.iodata_to_binary() |> text()

  defp canonical(value) when is_map(value) do
    [
      "{",
      value
      |> Enum.sort()
      |> Enum.map(fn {key, value} -> [JSON.encode!(key), ":", canonical(value)] end)
      |> Enum.intersperse(","),
      "}"
    ]
  end

  defp canonical(value) when is_list(value), do: ["[", value |> Enum.map(&canonical/1) |> Enum.intersperse(","), "]"]
  defp canonical(value), do: JSON.encode!(value)

  defp frame(frame) do
    strings = Map.new(~w(filename module function), &{&1, text(frame[&1])})

    Map.merge(strings, %{
      "lineno" => if(is_integer(frame["lineno"]), do: frame["lineno"]),
      "in_app" => frame["in_app"] == true
    })
  end
end
