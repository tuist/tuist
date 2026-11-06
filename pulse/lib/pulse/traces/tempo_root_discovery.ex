defmodule Pulse.Traces.TempoRootDiscovery do
  @moduledoc false
  alias Pulse.Codec.NIF
  alias Pulse.Traces.{TempoDiscovery, TempoIntrinsics, TempoSearch}
  alias Pulse.Traces.TempoDuration

  @max 16_777_216
  @dictionary 1_048_576

  # Flat adapters cannot establish source envelopes. Segment reference replay
  # first selects parents, then recovers their complete retained trace context.
  def json(spans, key, opts) do
    if opts[:discovery_window], do: {:error, :unsupported_trace_discovery}, else: segments_json([spans], key, opts)
  end

  @doc false
  def expression_json(rows, ids, key, opts) do
    opts = Keyword.put(opts, :trace_duration?, TempoIntrinsics.trace_duration_key?(key))
    rows = Enum.map(rows, &{&1, false})

    with {:ok, groups} <- context(rows, ids, 0, opts),
         :ok <- complete(groups, key),
         do: dictionary(groups, key, Keyword.get(opts, :expression_filtered?, true))
  end

  def segments_json(segments, key, opts) do
    floor = opts[:discovery_floor] || 0
    opts = Keyword.put(opts, :trace_duration?, TempoIntrinsics.trace_duration_key?(key))

    with true <- TempoIntrinsics.root_key?(key) or TempoIntrinsics.trace_duration_key?(key),
         :ok <- TempoDiscovery.validate_window(opts[:discovery_window]),
         true <- is_integer(floor) and floor >= 0,
         :ok <- source_bounds(segments, opts),
         {:ok, predicates} <- TempoDiscovery.filter("intrinsic", key, opts[:discovery_query]),
         prepared = Enum.map(predicates, &prepare/1),
         true <- Enum.all?(List.flatten(segments), &header?/1),
         rows = source_rows(segments, floor, opts[:discovery_window]),
         {:ok, ids, work} <- candidates(rows, prepared, opts),
         {:ok, groups} <- context(rows, ids, work, opts),
         :ok <- complete(groups, key),
         {:ok, result} <- dictionary(groups, key, prepared != []) do
      {:ok, result}
    else
      false -> {:error, {:decode_failed, :invalid_trace_metadata}}
      error -> error
    end
  rescue
    _ -> {:error, {:decode_failed, :invalid_trace_metadata}}
  end

  defp source_bounds(segments, opts) do
    if length(segments) > min(opts[:max_scan_segments] || 1024, 1024) or
         Enum.reduce(segments, 0, &(length(&1) + &2)) > min(opts[:max_scan_rows] || 1_000_000, 1_000_000),
       do: {:error, :query_scan_limit},
       else: :ok
  end

  defp header?(span),
    do:
      is_integer(span.timestamp_ns) and is_integer(span.end_timestamp_ns) and span.timestamp_ns >= 0 and
        span.end_timestamp_ns >= span.timestamp_ns and span.end_timestamp_ns <= 9_223_372_036_854_775_807

  defp source_rows(segments, floor, window) do
    Enum.flat_map(segments, fn rows ->
      visible = Enum.filter(rows, &(&1.timestamp_ns >= floor))
      selected = selected?(visible, floor, window)
      Enum.map(visible, &{&1, selected})
    end)
  end

  defp selected?(_rows, _floor, nil), do: true
  defp selected?([], _floor, _window), do: false

  defp selected?(rows, floor, {start, finish}),
    do:
      finish >= floor and Enum.min_by(rows, & &1.timestamp_ns).timestamp_ns <= finish and
        Enum.max_by(rows, & &1.end_timestamp_ns).end_timestamp_ns >= max(start, floor)

  defp candidates(rows, predicates, opts) do
    Enum.reduce_while(rows, {:ok, MapSet.new(), 0}, &candidate_step(&1, &2, predicates, opts))
  end

  defp candidate_step({_span, false}, acc, _predicates, _opts), do: {:cont, acc}

  defp candidate_step({span, true}, {:ok, ids, work}, predicates, opts) do
    with :ok <- deadline(opts),
         :ok <- validate(span),
         {:ok, next} <- charge(span, work, opts),
         ids = if(matches?(span, predicates), do: MapSet.put(ids, span.trace_id), else: ids),
         true <- MapSet.size(ids) <= 65_536 do
      {:cont, {:ok, ids, next}}
    else
      false -> {:halt, {:error, :trace_group_limit}}
      error -> {:halt, error}
    end
  end

  defp context(rows, ids, initial_work, opts) do
    rows = Enum.filter(rows, fn {span, _} -> MapSet.member?(ids, span.trace_id) end)

    Enum.reduce_while(rows, {:ok, %{}, initial_work, 0}, &context_step(&1, &2, opts))
    |> case do
      {:ok, groups, _, _} -> {:ok, groups}
      error -> error
    end
  end

  defp context_step({span, selected}, {:ok, groups, work, bytes}, opts) do
    with :ok <- deadline(opts),
         :ok <- validate(span),
         {:ok, work} <- if(selected, do: {:ok, work}, else: charge(span, work, opts)),
         {next, extra} = observe(span, Map.get(groups, span.trace_id), opts[:trace_duration?]),
         true <- bytes + extra <= @max do
      {:cont, {:ok, Map.put(groups, span.trace_id, next), work, bytes + extra}}
    else
      false -> {:halt, {:error, :query_resource_limit}}
      error -> {:halt, error}
    end
  end

  defp validate(span) do
    with :ok <- TempoSearch.validate_span(span), false <- is_nil(span.otlp) do
      :ok
    else
      true -> {:error, :trace_metadata_unknown}
      error -> error
    end
  end

  defp charge(span, work, opts) do
    meta = span.otlp

    next =
      work + 2 + length(meta["resource"]) + length(meta["attributes"]) +
        link_work(meta, opts[:trace_duration?])

    if next > 2_000_000, do: {:error, :trace_discovery_work_limit}, else: {:ok, next}
  end

  defp link_work(_meta, true), do: 0
  defp link_work(meta, false), do: Enum.reduce(meta["links"], 0, &(1 + length(&1) + &2))

  defp observe(span, nil, true),
    do: {%{start: span.timestamp_ns, finish: span.end_timestamp_ns}, byte_size(span.trace_id) + 48}

  defp observe(span, group, true),
    do: {%{start: min(group.start, span.timestamp_ns), finish: max(group.finish, span.end_timestamp_ns)}, 0}

  defp observe(span, nil, false),
    do: observe(span, %{root: nil, id: nil, known: true, conflict: false, flags: %{}}, false)

  defp observe(span, group, false) do
    child_link =
      Enum.any?(span.otlp["links"], &(Map.get(strings(&1), "opentracing.ref_type") == "child_of"))

    root = is_nil(span.parent_span_id) and not child_link
    previous = Map.get(group.flags, span.span_id)
    extra = if is_nil(previous), do: byte_size(span.span_id) + 64, else: 0

    group = %{
      group
      | flags: Map.put(group.flags, span.span_id, root),
        conflict: group.conflict or (not is_nil(previous) and previous != root)
    }

    if root, do: root(span, group, extra), else: {group, extra}
  end

  defp root(span, group, extra) do
    service = Map.get(strings(span.otlp["resource"]), "service.name")
    pair = {service || "", span.name}

    conflict =
      group.conflict or different?(group.id, span.span_id) or different?(group.root, pair)

    extra =
      extra + if(is_nil(group.id), do: byte_size(span.span_id) + 32, else: 0) +
        if(is_nil(group.root), do: byte_size(elem(pair, 0)) + byte_size(span.name) + 32, else: 0)

    {%{
       group
       | id: group.id || span.span_id,
         root: group.root || pair,
         known: group.known and is_binary(service),
         conflict: conflict
     }, extra}
  end

  defp different?(nil, _next), do: false
  defp different?(previous, next), do: previous != next

  defp complete(_groups, "trace:duration"), do: :ok

  defp complete(groups, key) do
    service? = key in ["rootServiceName", "trace:rootService"]

    cond do
      Enum.any?(groups, fn {_, g} -> g.conflict end) -> {:error, :trace_root_conflict}
      Enum.any?(groups, fn {_, g} -> is_nil(g.root) or (service? and not g.known) end) -> {:error, :trace_root_unknown}
      true -> :ok
    end
  end

  defp dictionary(groups, "trace:duration", formatted) do
    values =
      Enum.map(groups, fn {_, g} ->
        ns = g.finish - g.start
        if formatted, do: TempoDuration.format(ns), else: Integer.to_string(ns)
      end)

    make_dictionary(values, if(formatted, do: "duration", else: "int"))
  end

  defp dictionary(groups, key, _formatted) do
    index = if key in ["rootServiceName", "trace:rootService"], do: 0, else: 1
    make_dictionary(Enum.map(groups, fn {_, g} -> elem(g.root, index) end), "string")
  end

  defp make_dictionary(values, type) do
    values = values |> Enum.uniq() |> Enum.sort()
    bytes = Enum.reduce(values, 0, &(byte_size(&1) + 38 + &2))

    if length(values) > 5000 or bytes > @dictionary do
      {:error, :query_resource_limit}
    else
      body = Pulse.JSON.encode!(%{"tagValues" => Enum.map(values, &value(&1, type))})
      if byte_size(body) > @dictionary, do: {:error, :query_resource_limit}, else: {:ok, body}
    end
  end

  defp value("", "string"), do: %{"type" => "string"}
  defp value(v, type), do: %{"type" => type, "value" => v}

  defp strings(attrs),
    do: for(%{"key" => key, "value" => %{"stringValue" => value}} <- attrs, into: %{}, do: {key, value})

  defp prepare({scope, key, "=~", pattern}) do
    :ok = NIF.validate_metric_regex(pattern)
    {:ok, regex} = NIF.compile_log_regex(Pulse.QueryRegex.anchor(pattern))
    {scope, key, "=~", regex}
  end

  defp prepare(p), do: p

  defp matches?(span, predicates) do
    resource = strings(span.otlp["resource"])
    attrs = strings(span.otlp["attributes"])

    Enum.all?(predicates, fn {scope, key, op, value} ->
      actual = Map.get(if(scope == "resource", do: resource, else: attrs), key)
      is_binary(actual) and if(op == "=", do: actual == value, else: NIF.match_log_regex(value, actual))
    end)
  end

  defp deadline(opts),
    do:
      if(is_integer(opts[:deadline_ms]) and System.monotonic_time(:millisecond) > opts[:deadline_ms],
        do: {:error, :query_timeout},
        else: :ok
      )
end
