defmodule Pulse.Traces.TempoSearch do
  @moduledoc "Bounded stored-trace-wide single-spanset most-recent search, independent of window-local search."
  alias Pulse.Codec.NIF
  alias Pulse.QueryRunner
  alias Pulse.Storage
  alias Pulse.Traces.Protobuf
  alias Pulse.Traces.Search
  alias Pulse.Traces.SearchExpression
  alias Pulse.Traces.SearchExpression.Evaluator
  alias Pulse.Traces.Selector

  @max 16_777_216
  def query(tenant, query, opts, format \\ "json") do
    with :ok <- available(),
         {:ok, predicates} <- parse(query) do
      QueryRunner.run(tenant, :raw, fn deadline ->
        run_query(tenant, predicates, opts ++ QueryRunner.storage_opts(deadline), format)
      end)
    end
  end

  def available do
    if Keyword.get(Pulse.Runtime.get_env(:pulse, __MODULE__, []), :enabled, false),
      do: :ok,
      else: {:error, :tempo_search_disabled}
  end

  defp run_query(tenant, predicates, opts, format) do
    with {:ok, json} <- Storage.tempo_search_json(tenant, predicates, opts), do: encode_result(json, format)
  end

  defp encode_result(json, "json"), do: {:ok, json}

  defp encode_result(json, "protobuf") do
    body = json |> Pulse.JSON.decode!() |> Protobuf.encode(:search)
    if byte_size(body) <= @max, do: {:ok, body}, else: {:error, :query_resource_limit}
  end

  # Results are always the most recent matching traces, so `with
  # (most_recent=true)` is accepted but optional: without it Tempo may return
  # any matching traces, and the most recent ones are such an answer. Grafana
  # sends selectors without the hint by default.
  def parse(query) do
    case Selector.parse(query) do
      {:ok, predicates} -> {:ok, predicates}
      _ -> SearchExpression.parse(query)
    end
  end

  @doc false
  def json(spans, predicates, opts) do
    opts = Keyword.merge([limit: 100, spss: 3], opts)

    with :ok <- bounds(spans, opts),
         {:ok, predicates} <- prepare_predicates(predicates),
         {:ok, groups, work} <- collect(spans, predicates, opts),
         {:ok, groups} <- resolve(groups, predicates, opts, work),
         {:ok, rows} <- selected(groups, opts),
         body = Pulse.JSON.encode!(%{"traces" => rows}),
         true <- byte_size(body) <= @max do
      {:ok, body}
    else
      false -> {:error, :query_resource_limit}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, {:decode_failed, :invalid_trace_metadata}}
  end

  defp bounds(spans, opts) do
    cond do
      length(spans) > min(opts[:max_scan_rows] || 1_000_000, 1_000_000) -> {:error, :query_scan_limit}
      opts[:limit] not in 1..1000 or opts[:spss] not in 1..100 -> {:error, :invalid_query_limit}
      opts[:trace_start] < 0 or opts[:trace_end] < opts[:trace_start] -> {:error, :invalid_trace_window}
      true -> :ok
    end
  end

  defp collect(spans, predicates, opts) do
    with {:ok, ids, work} <- candidates(spans, predicates, opts),
         do: collect_candidates(spans, predicates, opts, ids, work)
  end

  defp prepare_predicates({:expression, program}), do: Evaluator.prepare(program)
  defp prepare_predicates(predicates), do: {:ok, Enum.map(predicates, &prepare/1)}

  defp candidates(spans, predicates, opts) do
    Enum.reduce_while(spans, {:ok, MapSet.new(), 0}, fn span, {:ok, ids, work} ->
      with :ok <- deadline(opts),
           :ok <- validate_span(span),
           {:ok, potential, _, work} <- evaluate_span(span, predicates, work) do
        candidate_result(span, potential, ids, work)
      else
        error -> {:halt, error}
      end
    end)
  end

  defp candidate_result(span, potential, ids, work) do
    if potential do
      if MapSet.size(ids) >= 65_536 and not MapSet.member?(ids, span.trace_id),
        do: {:halt, {:error, :trace_group_limit}},
        else: {:cont, {:ok, MapSet.put(ids, span.trace_id), work}}
    else
      {:cont, {:ok, ids, work}}
    end
  end

  defp collect_candidates(spans, predicates, opts, ids, work) do
    spans = Enum.filter(spans, &MapSet.member?(ids, &1.trace_id))

    Enum.reduce_while(spans, {:ok, %{}, 0, work}, fn span, {:ok, groups, bytes, work} ->
      with :ok <- deadline(opts),
           :ok <- validate_span(span),
           true <- Map.has_key?(groups, span.trace_id) or map_size(groups) < 65_536,
           previous = Map.get(groups, span.trace_id, initial(span)),
           {:ok, next, work} <- observe(span, previous, predicates, opts[:spss], work),
           extra = group_size(next) - group_size(previous),
           true <- bytes + extra <= @max do
        {:cont, {:ok, Map.put(groups, span.trace_id, next), bytes + extra, work}}
      else
        false ->
          {:halt,
           {:error,
            if(map_size(groups) >= 65_536 and not Map.has_key?(groups, span.trace_id),
              do: :trace_group_limit,
              else: :query_resource_limit
            )}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, groups, _, work} -> {:ok, groups, work}
      error -> error
    end
  end

  @doc false
  def validate_span(span) do
    if is_integer(span.timestamp_ns) and is_integer(span.end_timestamp_ns) and span.timestamp_ns >= 0 and
         span.end_timestamp_ns >= span.timestamp_ns and Regex.match?(~r/\A[0-9a-f]{32}\z/, span.trace_id) and
         span.trace_id != String.duplicate("0", 32) and header?(span),
       do: if(is_nil(span.otlp), do: :ok, else: Search.validate_metadata(span)),
       else: {:error, {:decode_failed, :invalid_trace_metadata}}
  end

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{16}\z/, id) and id != String.duplicate("0", 16)

  defp header?(span) do
    id?(span.span_id) and (is_nil(span.parent_span_id) or id?(span.parent_span_id)) and
      is_binary(span.name) and String.valid?(span.name) and codes?(span)
  end

  defp codes?(span),
    do: span.kind in 0..5 and span.flags in 0..4_294_967_295 and is_map(span.status) and span.status["code"] in 0..2

  # Legacy types cannot be guessed, but unrelated traces outside the overlap
  # window must not stop a post-cutover search. Defer uncertainty until selection.
  defp initial(span),
    do: %{
      start: span.timestamp_ns,
      finish: span.end_timestamp_ns,
      unknown: false,
      root: nil,
      conflict: false,
      matched: 0,
      samples: [],
      links: [],
      services: %{}
    }

  defp observe(span, group, predicates, spss, work) do
    group = %{group | start: min(group.start, span.timestamp_ns), finish: max(group.finish, span.end_timestamp_ns)}

    if is_nil(span.otlp) do
      {:ok, %{group | unknown: true}, work}
    else
      resource = strings(span.otlp["resource"])
      service = Map.get(resource, "service.name", "")

      services =
        Map.update(group.services, service, {1, error_count(span)}, fn {n, e} -> {n + 1, e + error_count(span)} end)

      group = %{group | services: services} |> root(span, service)

      observe_sample(span, group, predicates, spss, work)
    end
  end

  # Structural matches need the complete trace: keep each span's links and
  # resolve them once every retained span is observed.
  defp observe_sample(span, group, {:expression, compiled}, _spss, work) when compiled.relations != [] do
    with {:ok, matched, mask, attributes, work} <- Evaluator.evaluate_mask(span, compiled, work) do
      link = {span.span_id, span.parent_span_id, mask, if(matched, do: sample(span, attributes))}
      {:ok, %{group | links: [link | group.links]}, work}
    end
  end

  defp observe_sample(span, group, predicates, spss, work) do
    with {:ok, matched, attributes, work} <- evaluate_span(span, predicates, work) do
      if matched do
        samples =
          [sample(span, attributes) | group.samples]
          |> Enum.sort_by(&{String.to_integer(&1["startTimeUnixNano"]), &1["spanID"]})
          |> Enum.take(spss)

        {:ok, %{group | matched: group.matched + 1, samples: samples}, work}
      else
        {:ok, group, work}
      end
    end
  end

  defp strings(attrs),
    do: for(%{"key" => key, "value" => %{"stringValue" => value}} <- attrs, into: %{}, do: {key, value})

  defp error_count(span), do: if(span.status["code"] == 2, do: 1, else: 0)

  defp root(group, %{parent_span_id: nil} = span, service) do
    child_link? = Enum.any?(span.otlp["links"], &(Map.get(strings(&1), "opentracing.ref_type") == "child_of"))
    candidate = {service, span.name}

    cond do
      child_link? -> group
      is_nil(group.root) -> %{group | root: candidate}
      group.root != candidate -> %{group | conflict: true}
      true -> group
    end
  end

  defp root(group, _span, _service), do: group

  # Share the admitted query-local RE2-subset compiler, not PCRE semantics or
  # per-row compilation. Aggregation/metadata rendering remain independent.
  defp prepare({scope, key, "=~", value}) do
    :ok = NIF.validate_metric_regex(value)
    {:ok, regex} = NIF.compile_log_regex(Pulse.QueryRegex.anchor(value))
    {scope, key, "=~", regex}
  end

  defp prepare(predicate), do: predicate

  defp matches?(predicates, resource, attrs) do
    Enum.all?(predicates, fn {scope, key, op, value} ->
      actual = Map.get(if(scope == "resource", do: resource, else: attrs), key)

      is_binary(actual) and
        if(op == "=", do: actual == value, else: NIF.match_log_regex(value, actual))
    end)
  end

  defp evaluate_span(%{otlp: nil}, _, work), do: {:ok, true, [], work}
  defp evaluate_span(span, {:expression, program}, work), do: Evaluator.evaluate(span, program, work)

  defp evaluate_span(span, predicates, work) do
    resource = strings(span.otlp["resource"])
    attrs = strings(span.otlp["attributes"])
    matched = matches?(predicates, resource, attrs)
    {:ok, matched, if(matched, do: sample_attributes(predicates, resource, attrs), else: []), work}
  end

  defp sample_attributes(predicates, resource, attrs) do
    predicates
    |> Map.new(fn {scope, key, _, _} ->
      {{key, scope}, Map.fetch!(if(scope == "resource", do: resource, else: attrs), key)}
    end)
    |> Enum.sort()
    |> Enum.map(fn {{key, _}, value} -> %{"key" => key, "value" => %{"stringValue" => value}} end)
  end

  defp sample(span, attributes) do
    sample = %{
      "spanID" => span.span_id,
      "startTimeUnixNano" => Integer.to_string(span.timestamp_ns)
    }

    sample = if attributes == [], do: sample, else: Map.put(sample, "attributes", attributes)

    if span.end_timestamp_ns > span.timestamp_ns,
      do: Map.put(sample, "durationNanos", Integer.to_string(span.end_timestamp_ns - span.timestamp_ns)),
      else: sample
  end

  defp group_size(group) do
    root =
      if group.root, do: elem(group.root, 0) |> byte_size() |> Kernel.+(byte_size(elem(group.root, 1)) + 32), else: 0

    services = Enum.reduce(group.services, 0, fn {name, _}, n -> n + byte_size(name) + 32 end)

    services =
      Enum.reduce(group.links, services, fn {_, _, _, sample}, n ->
        n + 48 + if(sample, do: byte_size(Pulse.JSON.encode!(sample)), else: 0)
      end)

    Enum.reduce(group.samples, root + services, fn sample, n ->
      n + byte_size(Pulse.JSON.encode!(sample)) + byte_size(sample["spanID"]) + 32
    end)
  end

  defp resolve(groups, {:expression, compiled}, opts, work) when compiled.relations != [] do
    Enum.reduce_while(groups, {:ok, %{}, work}, fn {id, group}, {:ok, acc, work} ->
      links = Enum.reverse(group.links)
      work = work + length(links) * length(compiled.relations)

      if work > 20_000_000,
        do: {:halt, {:error, :query_resource_limit}},
        else: {:cont, {:ok, Map.put(acc, id, resolve_group(group, links, compiled.relations, opts[:spss])), work}}
    end)
    |> case do
      {:ok, groups, _} -> {:ok, groups}
      error -> error
    end
  end

  defp resolve(groups, _predicates, _opts, _work), do: {:ok, groups}

  defp resolve_group(group, links, relations, spss) do
    kept = Evaluator.structural(relations, Enum.map(links, fn {id, parent, mask, _} -> {id, parent, mask} end))
    samples = for {{_, _, _, sample}, true} <- Enum.zip(links, kept), do: sample
    ordered = Enum.sort_by(samples, &{String.to_integer(&1["startTimeUnixNano"]), &1["spanID"]})
    %{group | links: [], matched: length(samples), samples: Enum.take(ordered, spss)}
  end

  defp selected(groups, opts) do
    overlapping =
      Enum.filter(groups, fn {_, g} ->
        opts[:trace_start] == 0 or opts[:trace_end] == 0 or
          (g.start <= opts[:trace_end] and g.finish >= opts[:trace_start])
      end)

    cond do
      Enum.any?(overlapping, &unknown?/1) ->
        {:error, :trace_metadata_unknown}

      Enum.any?(overlapping, &unknown_time?/1) ->
        {:error, :trace_timestamp_unknown}

      Enum.any?(overlapping, &conflict?/1) ->
        {:error, :trace_root_conflict}

      Enum.any?(overlapping, &oversized?/1) ->
        {:error, :trace_duration_limit}

      true ->
        {:ok,
         overlapping
         |> Enum.filter(fn {_, g} -> g.matched > 0 end)
         |> Enum.sort_by(fn {id, g} -> {-g.start, id} end)
         |> Enum.take(opts[:limit])
         |> Enum.map(&row/1)}
    end
  end

  defp unknown_time?({_, g}), do: g.matched > 0 and g.start == 0
  defp unknown?({_, g}), do: g.unknown
  defp conflict?({_, g}), do: g.matched > 0 and g.conflict
  defp oversized?({_, g}), do: g.matched > 0 and div(g.finish - g.start, 1_000_000) > 4_294_967_295

  defp row({id, group}) do
    spanset = %{"spans" => group.samples, "matched" => group.matched}

    services =
      Map.new(group.services, fn {name, {n, e}} ->
        {name, if(e == 0, do: %{"spanCount" => n}, else: %{"spanCount" => n, "errorCount" => e})}
      end)

    row = %{
      "traceID" => String.trim_leading(id, "0"),
      "startTimeUnixNano" => Integer.to_string(group.start),
      "spanSet" => spanset,
      "spanSets" => [spanset],
      "serviceStats" => services
    }

    row =
      if group.finish - group.start >= 1_000_000,
        do: Map.put(row, "durationMs", div(group.finish - group.start, 1_000_000)),
        else: row

    case group.root do
      nil -> row
      {service, name} -> row |> nonempty("rootServiceName", service) |> nonempty("rootTraceName", name)
    end
  end

  defp nonempty(map, _key, ""), do: map
  defp nonempty(map, key, value), do: Map.put(map, key, value)

  defp deadline(opts) do
    if opts[:deadline_ms] && System.monotonic_time(:millisecond) >= opts[:deadline_ms],
      do: {:error, :query_timeout},
      else: :ok
  end
end
