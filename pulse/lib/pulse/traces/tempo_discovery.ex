defmodule Pulse.Traces.TempoDiscovery do
  @moduledoc "Experimental retained discovery; bounded parent filters, complete name hints and whole-segment time envelopes."
  alias Pulse.Codec.NIF
  alias Pulse.QueryRunner
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Traces.Protobuf
  alias Pulse.Traces.SearchExpression
  alias Pulse.Traces.SearchExpression.Evaluator
  alias Pulse.Traces.Selector
  alias Pulse.Traces.TempoFloat
  alias Pulse.Traces.TempoIntrinsics
  alias Pulse.Traces.TempoRootDiscovery
  alias Pulse.Traces.TempoSearch

  @max 1_048_576

  def query(tenant, scope, key, version \\ 2, format \\ "json", query \\ nil, window \\ nil, limit \\ 0) do
    with :ok <- TempoSearch.available(),
         :ok <- target(scope, key),
         :ok <- public_mode(scope, key, version),
         :ok <- S3.validate_tenant(tenant),
         :ok <- validate_window(window),
         true <- is_integer(limit) and limit in 0..4_294_967_295,
         {:ok, _} <- filter(scope, key, query) do
      QueryRunner.run(tenant, :traces, fn deadline ->
        opts =
          QueryRunner.storage_opts(deadline)
          |> Keyword.put(:discovery_query, query)
          |> Keyword.put(:discovery_window, window)
          |> Keyword.put(:discovery_limit, limit)

        run(tenant, scope, key, version, format, opts)
      end)
    else
      false -> {:error, :unsupported_trace_discovery}
      error -> error
    end
  end

  @doc false
  def validate_window(nil), do: :ok

  def validate_window({start, finish})
      when is_integer(start) and is_integer(finish) and start > 0 and start <= finish and
             finish <= 9_223_372_036_854_775_807, do: :ok

  def validate_window(_), do: {:error, :unsupported_trace_discovery}

  @doc false
  def filter("intrinsic", key, query)
      when key in ~w(trace:id span:id span:parentID link:traceID link:spanID) and (is_binary(query) or is_nil(query)) do
    expression_filter(if(query in [nil, ""], do: "{}", else: query))
  end

  def filter(_scope, _key, query) when query in [nil, "", "{}"], do: {:ok, []}

  def filter(scope, key, query) when is_binary(key) and is_binary(query) and byte_size(query) <= 16_384 do
    case Selector.parse(query) do
      {:ok, predicates} -> selector_filter(predicates, scope, key, query)
      _ -> expression_filter(query)
    end
  end

  def filter(_scope, _key, _query), do: {:error, :unsupported_trace_discovery}

  defp selector_filter(predicates, "intrinsic", key, query) do
    if TempoIntrinsics.dynamic_key?(key) and String.ends_with?(String.trim_trailing(query), "}"),
      do: {:ok, predicates},
      else: expression_filter(query)
  end

  defp selector_filter(predicates, scope, key, query) do
    same_target? =
      Enum.any?(predicates, fn {s, k, op, _} ->
        (s == scope or scope == "none") and k == key and op == "="
      end)

    if String.ends_with?(String.trim_trailing(query), "}") and not same_target?,
      do: {:ok, predicates},
      else: {:error, :unsupported_trace_discovery}
  end

  defp expression_filter(query) do
    with true <- String.ends_with?(String.trim_trailing(query), "}"),
         {:ok, {:expression, program}} <- SearchExpression.parse(query),
         false <- Enum.any?(program, fn {scope, _, _, _} -> scope in ["spanset", "select"] end) do
      {:ok, {:expression, program}}
    else
      _ -> {:error, :unsupported_trace_discovery}
    end
  end

  @doc false
  def target("intrinsic", key), do: TempoIntrinsics.validate(key)
  def target(scope, key), do: validate(scope, key)

  defp public_mode("intrinsic", key, 1) when key != "",
    do: if(TempoIntrinsics.dynamic_key?(key), do: :ok, else: {:error, :unsupported_trace_discovery})

  defp public_mode(_scope, _key, _version), do: :ok

  def validate("intrinsic", key),
    do: if(TempoIntrinsics.dynamic_key?(key), do: :ok, else: {:error, :unsupported_trace_discovery})

  def validate("none", key) when is_binary(key) do
    if byte_size(key) <= 256 and String.valid?(key) and key not in ["root.name", "root.service.name"],
      do: :ok,
      else: {:error, :unsupported_trace_discovery}
  end

  def validate(scope, key) do
    if scope in ["resource", "span", "instrumentation", "event", "link"] and is_binary(key) and byte_size(key) <= 256 and
         String.valid?(key),
       do: :ok,
       else: {:error, :unsupported_trace_discovery}
  end

  defp run(tenant, "intrinsic", key, version, format, opts) do
    if TempoIntrinsics.dynamic_key?(key),
      do: stored(tenant, "intrinsic", key, version, format, opts),
      else: encode(TempoIntrinsics.json(key), key, version, format, "intrinsic", opts[:discovery_limit] || 0)
  end

  defp run(tenant, scope, key, version, format, opts), do: stored(tenant, scope, key, version, format, opts)

  defp stored(tenant, scope, key, version, format, opts) do
    with {:ok, json} <- Storage.tempo_discovery_json(tenant, scope, key, opts),
         do: encode(json, key, version, format, scope, opts[:discovery_limit] || 0)
  end

  defp encode(json, _key, 2, "json", _scope, 0), do: {:ok, json}

  defp encode(json, key, version, format, scope, limit) do
    body = Pulse.JSON.decode!(json)
    body = if version == 1, do: v1(body, key, scope), else: body
    body = limit_values(body, key, limit)
    schema = response_schema(key, version)

    encoded = if format == "protobuf", do: Protobuf.encode(body, schema), else: Pulse.JSON.encode!(body)
    if byte_size(encoded) <= @max, do: {:ok, encoded}, else: {:error, :query_resource_limit}
  end

  # Output limiting never weakens dictionary, scan, work or whole-query error
  # checks. Tempo's names endpoint ignores limit; only values are capped.
  defp limit_values(body, "", _limit), do: body
  defp limit_values(body, _key, limit) when limit > 0, do: Map.update!(body, "tagValues", &Enum.take(&1, limit))
  defp limit_values(body, _key, _limit), do: body

  defp response_schema("", 1), do: :tags
  defp response_schema("", _version), do: :tags_v2
  defp response_schema(_key, 1), do: :tag_values
  defp response_schema(_key, _version), do: :tag_values_v2

  defp v1(body, "", scope) do
    scopes = if scope == "none", do: Enum.reject(body["scopes"], &(&1["name"] == "intrinsic")), else: body["scopes"]
    %{"tagNames" => scopes |> Enum.flat_map(& &1["tags"]) |> Enum.uniq() |> Enum.sort()}
  end

  defp v1(body, _key, _scope),
    do: %{"tagValues" => body["tagValues"] |> Enum.map(&Map.get(&1, "value", "")) |> Enum.uniq() |> Enum.sort()}

  @doc false
  def json(spans, scope, key, opts) do
    case filter(scope, key, opts[:discovery_query]) do
      {:ok, {:expression, program}} -> expression_segments_json([spans], scope, key, program, opts, false)
      {:ok, _} -> reference_json(spans, scope, key, opts)
      error -> error
    end
  end

  defp reference_json(spans, "intrinsic", key, opts)
       when key in ~w(rootName trace:rootName rootServiceName trace:rootService trace:duration),
       do: TempoRootDiscovery.json(spans, key, opts)

  defp reference_json(spans, scope, key, opts) do
    with :ok <- validate(scope, key),
         :ok <- reference_window(opts[:discovery_window]),
         :ok <- row_limit(spans, opts),
         {:ok, predicates} <- filter(scope, key, opts[:discovery_query]),
         prepared = Enum.map(predicates, &prepare/1),
         {:ok, values, _bytes, _work} <- collect(spans, scope, key, Keyword.put(opts, :prepared, prepared)),
         body = render(values, scope, key),
         true <- byte_size(body) <= @max do
      {:ok, body}
    else
      false -> {:error, :query_resource_limit}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, {:decode_failed, :invalid_trace_metadata}}
  end

  defp reference_window(nil), do: :ok
  defp reference_window(_), do: {:error, :unsupported_trace_discovery}

  # Expressions must see complete retained context before matching a source's
  # parents. Windows select immutable source envelopes, never individual rows.
  @doc false
  def expression_segments_json(segments, scope, key, program, opts, source_envelopes? \\ true) do
    floor = opts[:discovery_floor] || 0
    window = opts[:discovery_window]

    with :ok <- target(scope, key),
         :ok <- validate_window(window),
         :ok <- if(source_envelopes?, do: :ok, else: reference_window(window)),
         true <- is_integer(floor) and floor >= 0,
         true <- length(segments) <= min(opts[:max_scan_segments] || 1024, 1024),
         :ok <- segment_row_limit(segments, opts),
         true <- Enum.all?(segments, &valid_segment?/1),
         {:ok, {:expression, compiled}} <- Evaluator.prepare(program),
         rows = segments |> List.flatten() |> Enum.filter(&(&1.timestamp_ns >= floor)),
         :ok <- validate_expression_rows(rows, opts),
         {:ok, contexts, context_work} <- expression_contexts(rows, program),
         selected = expression_source_rows(segments, floor, window),
         {:ok, matches, _work} <- expression_matches(selected, compiled, contexts, context_work, opts),
         opts = Keyword.put(opts, :expression_filtered?, program != [{"constant", "", "true", ""}]),
         {:ok, body} <- expression_dictionary(rows, selected, matches, scope, key, opts),
         true <- byte_size(body) <= @max do
      {:ok, body}
    else
      false -> {:error, :query_scan_limit}
      error -> error
    end
  rescue
    _ -> {:error, {:decode_failed, :invalid_trace_metadata}}
  end

  defp expression_source_rows(segments, floor, nil),
    do: segments |> List.flatten() |> Enum.filter(&(&1.timestamp_ns >= floor))

  defp expression_source_rows(segments, floor, {start, finish}),
    do: Enum.flat_map(segments, &selected_rows(&1, start, finish, floor))

  defp validate_expression_rows(rows, opts) do
    Enum.reduce_while(rows, :ok, fn span, _ ->
      with :ok <- deadline(opts), :ok <- TempoSearch.validate_span(span), false <- is_nil(span.otlp) do
        {:cont, :ok}
      else
        true -> {:halt, {:error, :trace_metadata_unknown}}
        error -> {:halt, error}
      end
    end)
  end

  defp expression_contexts(rows, program) do
    cond do
      Enum.any?(program, fn {scope, key, _, _} ->
        scope == "intrinsic.string" and key in ~w(rootName rootServiceName)
      end) ->
        Evaluator.trace_context(rows, 0, :discovery)

      SearchExpression.context?(program) ->
        Enum.reduce_while(rows, {:ok, %{}, 0}, &add_trace_envelope/2)

      true ->
        {:ok, %{}, 0}
    end
  end

  defp add_trace_envelope(span, {:ok, contexts, work}) do
    previous = Map.get(contexts, span.trace_id)
    context = %{start: span.timestamp_ns, finish: span.end_timestamp_ns, root: nil}

    context =
      if previous,
        do: %{context | start: min(previous.start, context.start), finish: max(previous.finish, context.finish)},
        else: context

    if previous == nil and map_size(contexts) >= 65_536,
      do: {:halt, {:error, :trace_group_limit}},
      else: {:cont, {:ok, Map.put(contexts, span.trace_id, context), work + 1}}
  end

  defp expression_matches(rows, compiled, contexts, initial_work, opts) do
    Enum.reduce_while(rows, {:ok, [], initial_work}, fn span, {:ok, matches, work} ->
      context = Map.get(contexts, span.trace_id)

      with :ok <- deadline(opts),
           {:ok, matched, _, work} <- Evaluator.evaluate(span, Evaluator.with_context(compiled, context), work) do
        {:cont, {:ok, [matched | matches], work}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, matches, work} -> {:ok, Enum.reverse(matches), work}
      error -> error
    end
  end

  defp expression_dictionary(_rows, _selected, _matches, "intrinsic", key, _opts)
       when key in ["" | ~w(status span:status kind span:kind duration span:duration traceDuration)],
       do: {:ok, TempoIntrinsics.json(key)}

  defp expression_dictionary(rows, selected, matches, "intrinsic", key, opts)
       when key in ~w(rootName trace:rootName rootServiceName trace:rootService trace:duration) do
    ids = selected |> Enum.zip(matches) |> Enum.filter(&elem(&1, 1)) |> MapSet.new(fn {span, _} -> span.trace_id end)
    TempoRootDiscovery.expression_json(rows, ids, key, opts)
  end

  defp expression_dictionary(_rows, selected, matches, scope, key, opts) do
    names = if scope == "none" and key == "", do: Enum.map(TempoIntrinsics.names(), &{"intrinsic", &1}), else: []

    {:ok, set, bytes} =
      Enum.reduce(names, {:ok, MapSet.new(), 0}, fn pair, {:ok, set, bytes} -> keep(pair, set, bytes) end)

    opts = Keyword.put(opts, :prepared, [])

    Enum.zip(selected, matches)
    |> Enum.reduce_while({:ok, set, bytes, 0}, fn {span, matched}, {:ok, set, bytes, work} ->
      case add_span(span, scope, key, set, bytes, work, Keyword.put(opts, :expression_match, matched)) do
        {:ok, _, _, _} = result -> {:cont, result}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, set, _, _} -> {:ok, render(set, scope, key)}
      error -> error
    end
  end

  @doc false
  def segments_json(segments, scope, key, opts) do
    case filter(scope, key, opts[:discovery_query]) do
      {:ok, {:expression, program}} -> expression_segments_json(segments, scope, key, program, opts, true)
      {:ok, _} -> reference_segments_json(segments, scope, key, opts)
      error -> error
    end
  end

  defp reference_segments_json(segments, "intrinsic", key, opts)
       when key in ~w(rootName trace:rootName rootServiceName trace:rootService trace:duration),
       do: TempoRootDiscovery.segments_json(segments, key, opts)

  defp reference_segments_json(segments, scope, key, opts) do
    floor = opts[:discovery_floor] || 0

    with :ok <- validate(scope, key),
         :ok <- validate_window(opts[:discovery_window]),
         true <- is_integer(floor) and floor >= 0,
         :ok <- segment_row_limit(segments, opts),
         true <- Enum.all?(segments, &valid_segment?/1) do
      selected = expression_source_rows(segments, floor, opts[:discovery_window])
      json(selected, scope, key, Keyword.delete(opts, :discovery_window))
    else
      {:error, _} = error -> error
      _ -> {:error, {:decode_failed, :invalid_trace_metadata}}
    end
  end

  defp valid_segment?(rows), do: Enum.all?(rows, &valid_header?/1)

  defp valid_header?(%{timestamp_ns: start, end_timestamp_ns: finish}) when is_integer(start) and is_integer(finish),
    do: start >= 0 and finish >= start and finish <= 9_223_372_036_854_775_807

  defp valid_header?(_), do: false

  defp selected_rows(rows, start, finish, floor) do
    visible = Enum.filter(rows, &(&1.timestamp_ns >= floor))

    if visible != [] and finish >= floor and Enum.min_by(visible, & &1.timestamp_ns).timestamp_ns <= finish and
         Enum.max_by(visible, & &1.end_timestamp_ns).end_timestamp_ns >= max(start, floor), do: visible, else: []
  end

  defp segment_row_limit(segments, opts) do
    limit = min(opts[:max_scan_rows] || 1_000_000, 1_000_000)

    Enum.reduce_while(segments, 0, fn rows, count ->
      count = count + length(rows)
      if count > limit, do: {:halt, {:error, :query_scan_limit}}, else: {:cont, count}
    end)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  defp row_limit(spans, opts) do
    if length(spans) > min(opts[:max_scan_rows] || 1_000_000, 1_000_000), do: {:error, :query_scan_limit}, else: :ok
  end

  defp collect(spans, scope, key, opts) do
    names = if scope == "none" and key == "", do: Enum.map(TempoIntrinsics.names(), &{"intrinsic", &1}), else: []

    {:ok, initial, size} =
      Enum.reduce(names, {:ok, MapSet.new(), 0}, fn pair, {:ok, set, bytes} -> keep(pair, set, bytes) end)

    Enum.reduce_while(spans, {:ok, initial, size, 0}, fn span, {:ok, set, bytes, work} ->
      case add_span(span, scope, key, set, bytes, work, opts) do
        {:ok, _, _, _} = result -> {:cont, result}
        error -> {:halt, error}
      end
    end)
  end

  defp add_span(span, "intrinsic", key, set, bytes, work, opts) do
    with :ok <- deadline(opts),
         :ok <- TempoSearch.validate_span(span),
         false <- is_nil(span.otlp),
         next = work + dynamic_work(span.otlp, key),
         :ok <- work_limit(next),
         :ok <- validate_dynamic(span, key),
         values = if(parent_matches?(span, opts), do: dynamic_values(span, key), else: []),
         kind = if(TempoIntrinsics.event_time_key?(key), do: "int", else: "string"),
         {:ok, set, bytes} <- add_dynamic(values, kind, set, bytes) do
      {:ok, set, bytes, next}
    else
      true -> {:error, :trace_metadata_unknown}
      error -> error
    end
  end

  defp add_span(span, scope, key, set, bytes, work, opts) do
    with :ok <- deadline(opts),
         :ok <- TempoSearch.validate_span(span),
         false <- is_nil(span.otlp),
         scopes = requested_scopes(scope, key),
         groups = Enum.map(scopes, &{&1, owners(span.otlp, &1)}),
         next =
           work +
             Enum.reduce(groups, 0, fn {_, owners}, sum -> sum + Enum.reduce(owners, 0, &(1 + length(&1) + &2)) end),
         :ok <- work_limit(next),
         matched = parent_matches?(span, opts),
         {:ok, set, bytes} <-
           add_groups(
             groups,
             key,
             set,
             bytes,
             matched,
             scope == "none" or opts[:prepared] != [] or Keyword.has_key?(opts, :expression_match)
           ) do
      {:ok, set, bytes, next}
    else
      true -> {:error, :trace_metadata_unknown}
      error -> error
    end
  end

  defp dynamic_work(meta, "event:" <> _), do: 1 + Enum.reduce(meta["events"], 0, &(1 + length(&1) + &2))
  defp dynamic_work(meta, "instrumentation:" <> _), do: 1 + length(meta["scope"])
  defp dynamic_work(meta, "link:" <> _), do: 1 + Enum.reduce(meta["links"], 0, &(1 + length(&1) + &2))
  defp dynamic_work(meta, _key), do: 1 + length(meta["attributes"])
  defp dynamic_values(span, "trace:id"), do: [span.trace_id]
  defp dynamic_values(span, "span:id"), do: [span.span_id]
  defp dynamic_values(span, "span:parentID"), do: [span.parent_span_id || "0000000000000000"]
  defp dynamic_values(span, "link:traceID"), do: Enum.map(span.links, & &1["trace_id"])
  defp dynamic_values(span, "link:spanID"), do: Enum.map(span.links, & &1["span_id"])
  defp dynamic_values(span, key) when key in ["name", "span:name"], do: [span.name]

  defp dynamic_values(span, key) when key in ["statusMessage", "span:statusMessage"],
    do: [Map.get(span.status || %{}, "message", "")]

  defp dynamic_values(span, "instrumentation:name"), do: [Map.get(span.scope, "name", "")]
  defp dynamic_values(span, "instrumentation:version"), do: [Map.get(span.scope, "version", "")]
  defp dynamic_values(span, "event:name"), do: Enum.map(span.events, &Map.get(&1, "name", ""))

  defp dynamic_values(span, "event:timeSinceStart"),
    do: Enum.map(span.events, &Integer.to_string(Map.fetch!(&1, "timestamp_ns") - span.timestamp_ns))

  defp validate_dynamic(span, "event:timeSinceStart") do
    if Enum.all?(span.events, &valid_event_time?/1), do: :ok, else: {:error, {:decode_failed, :invalid_trace_metadata}}
  end

  defp validate_dynamic(_span, _key), do: :ok

  defp valid_event_time?(event) when is_map(event) do
    time = Map.get(event, "timestamp_ns")
    is_integer(time) and time >= 0 and time <= 9_223_372_036_854_775_807
  end

  defp valid_event_time?(_), do: false

  defp add_dynamic(values, kind, set, bytes) do
    Enum.reduce_while(values, {:ok, set, bytes}, fn value, {:ok, set, bytes} ->
      case keep({kind, value}, set, bytes) do
        {:ok, _, _} = result -> {:cont, result}
        error -> {:halt, error}
      end
    end)
  end

  defp requested_scopes("none", ""), do: ~w(resource span instrumentation event link)
  defp requested_scopes("none", _key), do: ~w(resource span instrumentation)
  defp requested_scopes(scope, _key), do: [scope]

  defp add_groups(groups, key, set, bytes, matched, filtered) do
    Enum.reduce_while(groups, {:ok, set, bytes}, fn {scope, owners}, {:ok, set, bytes} ->
      selected = if matched, do: owners, else: []
      hints = if key == "" and filtered, do: name_hints(owners, scope), else: []
      target = if key == "", do: {:names, scope}, else: key

      case add_owners([hints | selected], target, set, bytes) do
        {:ok, _, _} = result -> {:cont, result}
        error -> {:halt, error}
      end
    end)
  end

  defp name_hints(owners, scope) do
    promoted = for pairs <- owners, pair <- pairs, promoted_name?(scope, pair), do: pair
    if scope == "resource", do: [%{"key" => "service.name"} | promoted], else: promoted
  end

  defp promoted_name?("resource", %{"key" => key, "value" => %{"stringValue" => _}}),
    do: key in ~w(cluster namespace pod container k8s.cluster.name k8s.namespace.name k8s.pod.name k8s.container.name)

  defp promoted_name?("span", %{"key" => key, "value" => %{"stringValue" => _}}), do: key in ~w(http.method http.url)
  defp promoted_name?("span", %{"key" => "http.status_code", "value" => %{"intValue" => _}}), do: true
  defp promoted_name?(_scope, _pair), do: false

  defp owners(meta, "resource"), do: [meta["resource"]]
  defp owners(meta, "span"), do: [meta["attributes"]]
  defp owners(meta, "instrumentation"), do: [meta["scope"]]
  defp owners(meta, "event"), do: meta["events"]
  defp owners(meta, "link"), do: meta["links"]
  defp work_limit(work), do: if(work <= 2_000_000, do: :ok, else: {:error, :trace_discovery_work_limit})

  defp add_owners(owners, key, set, bytes) do
    Enum.reduce_while(owners, {:ok, set, bytes}, fn pairs, {:ok, set, bytes} ->
      case add_pairs(pairs, key, set, bytes) do
        {:ok, _, _} = result -> {:cont, result}
        error -> {:halt, error}
      end
    end)
  end

  defp add_pairs(pairs, key, set, bytes) do
    Enum.reduce_while(pairs, {:ok, set, bytes}, fn pair, {:ok, set, bytes} ->
      case add_pair(pair, key, set, bytes) do
        {:ok, _, _} = result -> {:cont, result}
        error -> {:halt, error}
      end
    end)
  end

  defp add_pair(pair, {:names, scope}, set, bytes), do: keep({scope, pair["key"]}, set, bytes)

  defp add_pair(%{"key" => key, "value" => value}, key, set, bytes) do
    with {:ok, pair} <- scalar(value), do: keep(pair, set, bytes)
  end

  defp add_pair(_pair, _key, set, bytes), do: {:ok, set, bytes}
  defp scalar(%{"stringValue" => v}), do: {:ok, {"string", v}}
  defp scalar(%{"intValue" => v}), do: {:ok, {"int", v}}
  defp scalar(%{"doubleValue" => v}), do: {:ok, {"float", TempoFloat.format(v)}}
  defp scalar(%{"boolValue" => v}), do: {:ok, {"bool", to_string(v)}}
  defp scalar(_value), do: {:error, :unsupported_trace_tag_type}

  defp keep({kind, value} = pair, set, bytes) do
    next = if MapSet.member?(set, pair), do: bytes, else: bytes + byte_size(kind) + byte_size(value) + 32

    if (MapSet.size(set) >= 5000 and not MapSet.member?(set, pair)) or next > @max,
      do: {:error, :query_resource_limit},
      else: {:ok, MapSet.put(set, pair), next}
  end

  defp render(set, _scope, "") do
    scopes =
      set
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort()
      |> Enum.map(fn {scope, tags} -> %{"name" => scope, "tags" => Enum.sort(tags)} end)

    Pulse.JSON.encode!(%{"scopes" => scopes})
  end

  defp render(set, _scope, _key),
    do:
      Pulse.JSON.encode!(%{
        "tagValues" =>
          set
          |> Enum.sort()
          |> Enum.map(fn {type, value} ->
            if(value == "", do: %{"type" => type}, else: %{"type" => type, "value" => value})
          end)
      })

  defp prepare({scope, key, "=~", value}) do
    :ok = NIF.validate_metric_regex(value)
    {:ok, regex} = NIF.compile_log_regex(Pulse.QueryRegex.anchor(value))
    {scope, key, "=~", regex}
  end

  defp prepare(predicate), do: predicate

  defp parent_matches?(span, opts),
    do: Keyword.get_lazy(opts, :expression_match, fn -> matches?(span.otlp, opts[:prepared]) end)

  defp matches?(metadata, predicates), do: Enum.all?(predicates, &matches_predicate?(metadata, &1))

  defp matches_predicate?(metadata, {scope, key, op, value}) do
    owner = if scope == "resource", do: "resource", else: "attributes"

    case Enum.find(metadata[owner], &(&1["key"] == key)) do
      %{"value" => %{"stringValue" => actual}} ->
        if op == "=", do: actual == value, else: NIF.match_log_regex(value, actual)

      _ ->
        false
    end
  end

  defp deadline(opts) do
    if is_integer(opts[:deadline_ms]) and System.monotonic_time(:millisecond) >= opts[:deadline_ms],
      do: {:error, :query_timeout},
      else: :ok
  end
end
