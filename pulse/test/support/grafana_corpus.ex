defmodule Pulse.Test.GrafanaCorpus do
  @moduledoc """
  Tuist's Grafana query corpus (`test/fixtures/grafana/tuist-corpus.json`) and
  Grafana's variable interpolation for it.

  Interpolation follows Grafana's template service and the Prometheus/Loki
  datasources: `$name`, `${name}`, `${name:format}` and `[[name]]` reference
  dashboard variables or the interval/range macros; unknown names stay as
  written. Multi-value and include-All variables are regex-escaped and joined
  as `(a|b)` (one value stays bare), All uses the variable's custom all value
  or `.*`, and single-value variables are inserted as they are.
  """

  alias Pulse.PromQL.Parser

  @path Path.expand("../fixtures/grafana/tuist-corpus.json", __DIR__)
  @variable ~r/\$(\w+)|\[\[(\w+?)(?::(\w+))?\]\]|\$\{(\w+)(?::([^}]+))?\}/

  def fixture, do: @path |> File.read!() |> JSON.decode!()

  @doc "Query macros for one evaluation, from the step and range in seconds."
  def macros(step_s, range_s, scrape_s) do
    rate = max(step_s + scrape_s, 4 * scrape_s)

    %{
      "__interval" => hms(step_s),
      "__auto" => hms(step_s),
      "__interval_ms" => Integer.to_string(step_s * 1000),
      "__rate_interval" => hms(rate),
      "__range" => hms(range_s),
      "__range_s" => Integer.to_string(range_s),
      "__range_ms" => Integer.to_string(range_s * 1000)
    }
  end

  @doc "Interpolates `expr` for `language` with dashboard `variables` and `macros`."
  def interpolate(expr, language, variables, macros) do
    Regex.replace(@variable, expr, fn match, a, b, b_format, c, c_format ->
      name = Enum.find([a, b, c], &(&1 != ""))
      format = Enum.find([b_format, c_format], "", &(&1 != ""))

      cond do
        Map.has_key?(macros, name) -> macros[name]
        Map.has_key?(variables, name) -> render(variables[name], format, language)
        true -> match
      end
    end)
  end

  defp render(variable, format, language) do
    value = Map.fetch!(variable, "value")
    multi? = Map.get(variable, "multi", false) or Map.get(variable, "include_all", false)

    value =
      if value == "$__all" or value == ["$__all"], do: {:all, Map.get(variable, "all_value", ".*")}, else: value

    case {value, format} do
      {{:all, all}, _} -> all
      {value, "regex"} -> join(value, &regex_escape(&1, :plain))
      {value, "raw"} -> join(value, & &1)
      {value, _} when multi? -> join(value, &regex_escape(&1, language))
      {value, _} -> List.wrap(value) |> Enum.join(",") |> regular_escape()
    end
  end

  defp join(values, escape) do
    List.wrap(values)
    |> Enum.map(escape)
    |> case do
      [one] -> one
      many -> "(" <> Enum.join(many, "|") <> ")"
    end
  end

  # prometheusSpecialRegexEscape / lokiSpecialRegexEscape: the escapes land in
  # a double-quoted query string, so each backslash is doubled once more.
  defp regex_escape(value, :plain), do: Regex.replace(~r/[\\^$*+?.()|{}\[\]\/]/, value, "\\\\\\0")

  defp regex_escape(value, _language) do
    value
    |> String.replace("\\", "\\\\\\\\")
    |> then(&Regex.replace(~r/[$^*{}\[\]'+?.()|]/, &1, "\\\\\\\\\\0"))
  end

  defp regular_escape(value), do: value |> String.replace("\\", "\\\\") |> String.replace("'", "\\\\'")

  # -- Evaluation scenario --------------------------------------------------

  # Hour-aligned end; range panels span the last hour at a 5-minute step,
  # instant panels and alerts evaluate at the end. Samples cover two hours.
  @end_s 1_759_996_800
  @scrape_s 60
  @range_s 3600
  @step_s 300
  @data_s 4800

  def scenario, do: %{end_s: @end_s, scrape_s: @scrape_s, range_s: @range_s, step_s: @step_s, data_s: @data_s}

  @doc "Every corpus query interpolated for the scenario, with its HTTP parameters."
  def requests(fixture \\ fixture()) do
    macros = macros(@step_s, @range_s, @scrape_s)
    dashboards = fixture["variables"]["dashboards"]

    for query <- fixture["queries"] do
      variables = Map.get(dashboards, List.first(query["dashboards"] || []), %{})
      expr = interpolate(query["expr"], query["language"], variables, macros)

      params =
        if String.contains?(query["modes"], "r"),
          do: %{"query" => expr, "start" => @end_s - @range_s, "end" => @end_s, "step" => @step_s},
          else: %{"query" => expr, "time" => @end_s}

      Map.merge(query, %{"interpolated" => expr, "params" => params})
    end
  end

  @doc """
  `{backend, path, params}` for one request: `:prometheus` or `:loki`, the
  instant or range query path, and form parameters. Log range queries return
  the newest 100 entries, as a logs panel does with a smaller line limit.
  """
  def http_request(%{"language" => language, "params" => params}) do
    instant? = Map.has_key?(params, "time")
    kind = if instant?, do: "query", else: "query_range"
    params = Map.new(params, fn {k, v} -> {k, to_string(v)} end)

    case language do
      "promql" ->
        {:prometheus, "/api/v1/" <> kind, params}

      "logql" ->
        params = if instant?, do: params, else: Map.merge(params, %{"limit" => "100", "direction" => "backward"})
        {:loki, "/loki/api/v1/" <> kind, params}
    end
  end

  @doc """
  The parts of a decoded query response that the comparison reads, with
  vector, matrix and stream results sorted by label set so regenerations are
  byte-stable (the comparison ignores result order).
  """
  def reference_result(%{"status" => "success", "data" => data}) do
    data = Map.take(data, ["resultType", "result"])

    data =
      if data["resultType"] in ["vector", "matrix", "streams"],
        do:
          Map.update!(data, "result", fn result -> Enum.sort_by(result, &Enum.sort(&1["metric"] || &1["stream"])) end),
        else: data

    %{"status" => "success", "data" => data}
  end

  def reference_result(%{} = body), do: Map.take(body, ["status", "errorType", "error"])

  @doc "The reference document as JSON with one result per line, sorted by query id."
  def encode_reference(%{"results" => results} = reference) do
    header = reference |> Map.delete("results") |> Pulse.JSON.encode!()
    header = binary_part(header, 0, byte_size(header) - 1)

    lines =
      results
      |> Enum.sort()
      |> Enum.map_join(",\n", fn {id, result} ->
        "  " <> Pulse.JSON.encode!(id) <> ": " <> Pulse.JSON.encode!(result)
      end)

    header <> ~s(,"results":{\n) <> lines <> "\n}}\n"
  end

  @doc """
  `:match` or `{:mismatch, details}` for Pulse's decoded response against the
  reference result, at `Pulse.Parity` tolerance. Responses where both sides
  reject match. Log streams drop the two stream labels Pulse mirrors from
  pushed ones (`service` from `service_name`, `detected_level` from `level`)
  when the pushed stream did not carry them, after checking they mirror it.
  """
  def compare(reference, candidate) do
    case {Pulse.Parity.normalize(reference), Pulse.Parity.normalize(candidate)} do
      {{:ok, a}, {:ok, b}} -> Pulse.Parity.compare(a, unmirror(b, a), 1.0e-9)
      {{:error, _}, {:error, _}} -> :match
      other -> {:mismatch, other}
    end
  end

  defp unmirror({:entries, series}, {:entries, reference}) do
    {:entries,
     Map.new(series, fn {labels, points} ->
       stripped = Enum.reduce([{"service", "service_name"}, {"detected_level", "level"}], labels, &unmirror_label/2)
       if Map.has_key?(reference, stripped), do: {stripped, points}, else: {labels, points}
     end)}
  end

  defp unmirror(result, _reference), do: result

  defp unmirror_label({mirror, source}, labels) do
    if Map.has_key?(labels, mirror) and labels[mirror] == labels[source], do: Map.delete(labels, mirror), else: labels
  end

  # -- Synthetic metrics ----------------------------------------------------

  # Two entities (k = 0, 1) share topology labels, so joins on pod, node,
  # instance and region meet across metrics; every selector's matchers then
  # override the labels they constrain.
  @entities [
    %{
      "cluster" => "tuist-canary",
      "env" => "canary",
      "namespace" => "tuist-canary",
      "pod" => "kura-canary-0",
      "node" => "node-0",
      "instance" => "node-0",
      "region" => "fr-par",
      "job" => "kura",
      "site" => "ber1"
    },
    %{
      "cluster" => "tuist-canary",
      "env" => "canary",
      "namespace" => "tuist-canary",
      "pod" => "kura-canary-1",
      "node" => "node-1",
      "instance" => "node-1",
      "region" => "nl-ams",
      "job" => "kura",
      "site" => "ber1"
    }
  ]
  @default_buckets ["0.005", "0.1", "1", "10", "100", "1000", "10000", "+Inf"]

  @doc """
  Synthetic series `{labels, [{timestamp_s, value}]}` shaped like the metric
  names and labels every PromQL query selects.
  """
  def metric_series(requests) do
    # Per metric: every label any query selects, groups or joins it by, the
    # labels used for joins, and every selector's matchers.
    metrics =
      requests
      |> Enum.filter(&(&1["language"] == "promql"))
      |> Enum.flat_map(fn request ->
        {:ok, ast} = Parser.parse(request["interpolated"])
        {grouping, joins} = referenced_labels(ast)
        unique = unique_sides(ast)

        for matchers <- selectors(ast) do
          name = metric_name(matchers)
          labels = MapSet.new(grouping ++ joins ++ Enum.map(matchers, &elem(&1, 0)))
          {name, labels, MapSet.new(joins), matchers, name in unique}
        end
      end)
      |> Enum.group_by(&elem(&1, 0))

    metrics
    |> Enum.flat_map(fn {name, uses} ->
      labels =
        uses
        |> Enum.map(&elem(&1, 1))
        |> Enum.reduce(&MapSet.union/2)
        |> MapSet.difference(MapSet.new(["__name__", "le"]))

      joins = uses |> Enum.map(&elem(&1, 2)) |> Enum.reduce(&MapSet.union/2)
      unique? = Enum.any?(uses, &elem(&1, 4))
      bases = base_series(name, labels, joins, unique?)

      for {_, _, _, matchers, _} <- uses,
          {base, k} <- bases,
          series = satisfy_all(base, matchers, k),
          series,
          do: series
    end)
    |> expand_buckets()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&{&1, samples(&1)})
  end

  defp metric_name(matchers) do
    {_, :eq, name} = List.keyfind(matchers, "__name__", 0)
    name
  end

  # Metrics on the "one" side of a vector match: the right of group_left, the
  # left of group_right, both sides of one-to-one arithmetic/comparison.
  defp unique_sides(ast) do
    term_fold(ast, [], fn
      {:binary, op, modifiers, left, right}, acc when op not in ["and", "or", "unless"] ->
        one_sides(modifiers, left, right) ++ acc

      _, acc ->
        acc
    end)
  end

  defp one_sides(modifiers, left, right) do
    groups = for [modifier, _] <- modifiers, modifier in ["group_left", "group_right"], do: modifier
    matched? = Enum.any?(modifiers, &match?([m, _] when m in ["on", "ignoring"], &1))

    case groups do
      ["group_left"] -> unaggregated_names(right)
      ["group_right"] -> unaggregated_names(left)
      _ when matched? -> unaggregated_names(left) ++ unaggregated_names(right)
      _ -> []
    end
  end

  # Selectors whose labels reach the operand: aggregations already group.
  defp unaggregated_names({kind, _, _, _}) when kind in [:aggregate], do: []
  defp unaggregated_names({:parameter_aggregate, _, _, _, _}), do: []
  defp unaggregated_names(term) when is_list(term), do: Enum.flat_map(term, &unaggregated_names/1)

  defp unaggregated_names(term) when is_tuple(term) do
    case term do
      {:selector, matchers, _} -> [metric_name(matchers)]
      {:range, matchers, _, _} -> [metric_name(matchers)]
      _ -> term |> Tuple.to_list() |> unaggregated_names()
    end
  end

  defp unaggregated_names(_), do: []

  # One series per entity; metrics with dimension labels (grouped by, never
  # joined on, not topology) get two variants per entity unless they are the
  # "one" side of some vector match.
  defp base_series(name, labels, joins, unique?) do
    variant_labels =
      if unique?, do: [], else: labels |> MapSet.difference(joins) |> Enum.reject(&Map.has_key?(hd(@entities), &1))

    variants = if variant_labels == [], do: [0], else: [0, 1]

    for {entity, k} <- Enum.with_index(@entities), variant <- variants do
      labels
      |> Map.new(&{&1, label_value(&1, entity, k, variant_labels, variant)})
      |> Map.merge(Map.take(entity, ~w(cluster env pod instance job)))
      |> Map.put("__name__", name)
      |> then(&{&1, k})
    end
  end

  defp label_value(label, entity, k, variant_labels, variant) do
    cond do
      Map.has_key?(entity, label) -> entity[label]
      label in variant_labels -> "#{label}-#{variant}"
      true -> "#{label}-e#{k}"
    end
  end

  # A topology label pinned to one literal value exists once, not per entity.
  defp satisfy_all(base, matchers, k) do
    Enum.reduce_while(matchers, base, fn {name, op, value}, labels ->
      current = Map.get(labels, name)

      case satisfy(current, op, value, name, k) do
        nil ->
          {:halt, nil}

        pinned when k > 0 and name in ~w(pod node instance) and pinned != current and op in [:eq, :re] ->
          pin(labels, name, pinned, k)

        "" ->
          {:cont, Map.delete(labels, name)}

        satisfied ->
          {:cont, Map.put(labels, name, satisfied)}
      end
    end)
  end

  defp pin(labels, name, pinned, k) do
    if String.contains?(pinned, "w#{k}"), do: {:cont, Map.put(labels, name, pinned)}, else: {:halt, nil}
  end

  defp selectors(ast) do
    term_fold(ast, [], fn
      list, acc when is_list(list) and list != [] ->
        if Enum.all?(list, &matcher?/1) and Enum.any?(list, &match?({"__name__", :eq, _}, &1)),
          do: [list | acc],
          else: acc

      _, acc ->
        acc
    end)
  end

  defp matcher?({name, op, value}) when is_binary(name) and is_binary(value), do: op in [:eq, :neq, :re, :nre]
  defp matcher?(_), do: false

  # {grouping labels, join labels}
  defp referenced_labels(ast) do
    {grouping, joins} =
      term_fold(ast, {[], []}, fn
        {:grouping, _, labels}, {grouping, joins} ->
          {labels ++ grouping, joins}

        [modifier, labels], {grouping, joins} when modifier in ["on", "ignoring", "group_left", "group_right"] ->
          {grouping, labels ++ joins}

        {:call, "label_replace", [_, _, _, {:string, source}, _]}, {grouping, joins} ->
          {grouping, [source | joins]}

        _, acc ->
          acc
      end)

    clean = &(&1 |> Enum.reject(fn label -> label in ["", "__name__", "le"] end) |> Enum.uniq())
    {clean.(grouping), clean.(joins)}
  end

  defp term_fold(term, acc, fun) do
    acc = fun.(term, acc)

    cond do
      is_list(term) -> Enum.reduce(term, acc, &term_fold(&1, &2, fun))
      is_tuple(term) -> term |> Tuple.to_list() |> Enum.reduce(acc, &term_fold(&1, &2, fun))
      is_map(term) and not is_struct(term) -> term |> Map.values() |> Enum.reduce(acc, &term_fold(&1, &2, fun))
      true -> acc
    end
  end

  defp satisfy(_current, :eq, value, _name, _k), do: value
  defp satisfy(current, :neq, value, name, _k), do: if(current == value, do: "#{name}-other", else: current || "")

  defp satisfy(current, op, pattern, name, k) do
    {:ok, regex} = Regex.compile("^(?:" <> pattern <> ")$")
    matches? = &Regex.match?(regex, &1 || "")
    wanted? = if op == :re, do: matches?, else: &(not matches?.(&1))

    candidates =
      if op == :re,
        do: [current | regex_examples(pattern, k)],
        else: [current, "#{name}-other", "x#{current}"]

    Enum.find(candidates, &(is_binary(&1) and wanted?.(&1))) ||
      if(wanted?.(""), do: "")
  end

  # Candidate strings for a selector regex: each top-level alternative with
  # wildcards and classes replaced by literal characters.
  defp regex_examples(pattern, k) do
    alternatives = split_alternatives(pattern)

    Enum.flat_map(alternatives, fn alternative ->
      literal =
        alternative
        |> String.replace(~r/\(\?[a-z]+\)/, "")
        |> String.replace(~r/\[\^[^\]]*\][*+?]?/, "a")
        |> String.replace(~r/\[([^\]^])[^\]]*\]\{\d+\}/, "\\1\\1\\1\\1\\1")
        |> String.replace(~r/\[([^\]^])[^\]]*\][+]?/, "\\1")
        |> String.replace(~r/\[([^\]^])[^\]]*\][*?]/, "")
        |> String.replace(~r/\.\*|\.\+|\.\?/, "w#{k}")
        |> String.replace(".", "0")
        |> String.replace(~r/\\(.)/, "\\1")
        |> String.replace(~r/[()?*+]/, "")
        |> String.replace(~r/\|.*/, "")

      [literal, String.replace(literal, "w#{k}", "")]
    end)
  end

  defp split_alternatives(pattern) do
    {parts, current, _depth} =
      pattern
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        "(", {parts, current, depth} -> {parts, current <> "(", depth + 1}
        ")", {parts, current, depth} -> {parts, current <> ")", depth - 1}
        "|", {parts, current, 0} -> {[current | parts], "", 0}
        char, {parts, current, depth} -> {parts, current <> char, depth}
      end)

    Enum.reverse([current | parts])
  end

  # A histogram selector without `le` reads every bucket; with `le` it pins
  # the buckets it names. Each bucket family gets the union.
  defp expand_buckets(series) do
    {buckets, others} = Enum.split_with(series, &String.ends_with?(&1["__name__"], "_bucket"))

    families =
      buckets
      |> Enum.group_by(&Map.delete(&1, "le"), &Map.get(&1, "le"))
      |> Enum.map(fn {family, les} ->
        les =
          les
          |> Enum.reject(&(is_nil(&1) or (Float.parse(&1) == :error and &1 not in ["+Inf"])))
          |> Kernel.++(@default_buckets)

        {family, les |> Enum.uniq_by(&le_value/1) |> Enum.sort_by(&le_value/1)}
      end)

    others ++ for {family, les} <- families, le <- les, do: Map.put(family, "le", le)
  end

  defp le_value("+Inf"), do: :infinity
  defp le_value(le), do: le |> Float.parse() |> elem(0)

  # -- Synthetic sample values ---------------------------------------------

  defp samples(labels) do
    name = labels["__name__"]
    seed = :erlang.phash2(Map.delete(labels, "le"))
    count = div(@data_s, @scrape_s) + 1
    first = @end_s - @data_s
    # A tenth of the series stop 20 minutes early (lookback and absence).
    stop = if rem(seed, 10) == 3, do: count - div(1200, @scrape_s), else: count
    # Real scrapes have a per-target phase and millisecond jitter, so window
    # edges rarely coincide with samples (rate/increase extrapolation).
    phase_ms = rem(seed, @scrape_s * 1000)
    times = for i <- 0..(stop - 1), do: (first + i * @scrape_s) * 1000 + phase_ms + rem(i * 37, 250)
    Enum.zip(times, values(kind(name), labels, seed, length(times)))
  end

  defp kind(name) do
    cond do
      String.ends_with?(name, "_bucket") ->
        :bucket

      String.ends_with?(name, ["_total", "_count", "_sum"]) ->
        :counter

      String.ends_with?(name, "_info") or name == "kube_pod_info" ->
        :info

      String.contains?(name, ["timestamp", "_time_seconds", "_created", "mtime"]) ->
        :timestamp

      name == "up" or
          String.ends_with?(
            name,
            ~w(_up _ready _healthy _success _reachable _redundant _has_leader _observed _good _state _level)
          ) ->
        :flag

      true ->
        :gauge
    end
  end

  defp values(:info, _labels, _seed, n), do: List.duplicate(1.0, n)
  defp values(:flag, _labels, seed, n), do: for(i <- 1..n, do: if(rem(seed + div(i, 10), 7) == 0, do: 0.0, else: 1.0))

  defp values(:timestamp, _labels, seed, n) do
    first = @end_s - @data_s
    for i <- 0..(n - 1), do: (first + i * @scrape_s - rem(seed, 1800)) * 1.0
  end

  defp values(:gauge, _labels, seed, n) do
    for i <- 1..n, do: rem(:erlang.phash2({seed, div(i, 2)}), 4000) / 4
  end

  defp values(:counter, _labels, seed, n), do: counter(seed, n, 1.0)

  defp values(:bucket, labels, seed, n) do
    fraction =
      case labels["le"] do
        "+Inf" -> 1.0
        le -> min(1.0, 0.2 + :math.log10(1 + max(le_value(le), 0.0)) / 6)
      end

    counter(seed, n, fraction)
  end

  # Monotonic with one reset in the middle for a third of the series.
  defp counter(seed, n, fraction) do
    reset = if rem(seed, 3) == 0, do: div(n, 2)

    {values, _} =
      Enum.map_reduce(1..n, rem(seed, 500) * 1.0, fn i, total ->
        total = if i == reset, do: 0.0, else: total + Float.floor(rem(:erlang.phash2({seed, i}), 40) * fraction)
        {total, total}
      end)

    values
  end

  # -- Synthetic logs -------------------------------------------------------

  @doc """
  Synthetic log streams `{labels, [{timestamp_ns, line}]}` shaped like the
  streams and lines the LogQL queries select: Faro web vitals (logfmt),
  runner agents (JSON), Phoenix request logs, ingress-nginx access lines,
  kura (JSON), cache usage events (pattern) and synthetic monitoring.
  Every stream writes one line per 30 seconds over the data window, with
  variety chosen so filters, parsers and unwraps both keep and drop lines,
  including malformed values.
  """
  def log_streams do
    first = @end_s - @data_s
    steps = div(@data_s, 30)

    streams = [
      {%{"service_name" => "tuist-web", "source" => "faro"}, &web_vital/1},
      {%{"service_name" => "tuist-web", "source" => "faro-replica"}, &web_vital(&1 + 7)},
      {%{"service_name" => "agent", "cluster" => "tuist-production", "namespace" => "tuist-runners"}, &linux_agent/1},
      {%{"job" => "tuist-macos-tart-kubelet", "env" => "production"}, &macos_kubelet/1},
      {%{"app" => "docker", "instance" => "cache-eu-1"}, &cache_usage/1},
      {%{"app" => "docker", "instance" => "cache-us-1"}, &cache_usage(&1 + 3)},
      {%{"cluster" => "tuist-production", "namespace" => "tuist", "container" => "server", "pod" => "server-0"},
       &server_vm/1},
      {%{"cluster" => "tuist-production", "namespace" => "tuist", "container" => "server", "pod" => "server-1"},
       &server_vm(&1 + 5)},
      {%{"service_name" => "tuist", "env" => "production", "container" => "server", "cluster" => "tuist-production"},
       &phoenix/1},
      {%{
         "source" => "synthetic-monitoring-agent",
         "probe_success" => "0",
         "instance" => "https://tuist.dev",
         "job" => "home"
       }, &probe/1},
      {%{
         "source" => "synthetic-monitoring-agent",
         "probe_success" => "0",
         "instance" => "https://cache.tuist.dev",
         "job" => "cache"
       }, &probe(&1 + 1)},
      {%{"namespace" => "tuist-canary", "container" => "postgres", "k8s_cluster_name" => "tuist-canary"}, &postgres/1},
      {%{"namespace" => "tuist", "container" => "postgres", "k8s_cluster_name" => "tuist-production"},
       &postgres(&1 + 2)},
      {%{"service_name" => "kura-fr-par-ingress-nginx", "cluster" => "tuist-production"}, &ingress/1},
      {%{"service_name" => "kura-nl-ams-ingress-nginx", "cluster" => "tuist-production"}, &ingress(&1 + 4)},
      {%{"job" => "cache-nginx", "instance" => "cache-eu-1"}, &cache_nginx/1},
      {%{"cluster" => "kura-tuist", "instance" => "kura-1"}, plain("kura edge")},
      {%{"env" => "canary", "pod" => "registry-0", "container" => "registry"}, plain("registry")},
      {%{"service_name" => "tuist-server"}, &tuist_server/1},
      {%{"service_namespace" => "tuist", "level" => "warning"}, &bandit/1}
    ]

    kura =
      for {pod, k} <- [{"kura-canary-0", 0}, {"kura-canary-1", 1}, {"kura-tuist-scw-fr-par-0", 2}] do
        {%{"cluster" => "tuist-canary", "env" => "canary", "namespace" => "kura", "container" => "kura", "pod" => pod},
         &kura(&1 + k)}
      end

    for {labels, line} <- streams ++ kura do
      {labels, for(i <- 0..(steps - 1), do: {(first + i * 30) * 1_000_000_000 + rem(i, 7) * 1000, line.(i)})}
    end
  end

  defp pick(list, i), do: Enum.at(list, rem(i, length(list)))

  defp web_vital(i) do
    lcp = pick(["840", "1250", "2600", "4100", "12000", "", "350", "n/a"], i)
    surface = pick(["auth", "dashboard_authenticated", "docs", "marketing", "dashboard_public"], div(i, 2))
    schema = pick(["1", "1", "1", "0"], div(i, 3))
    quality = pick(["eligible", "eligible", "bot"], i)
    dedup = pick(["unique", "unique", "duplicate", ""], div(i, 5))
    ray = pick(["8f1a", "", "9c2b"], div(i, 4))
    kind = pick(["measurement", "measurement", "measurement", "event"], i)
    env = pick(["prod", "prod", "prod", "staging"], div(i, 7))

    page =
      if rem(i, 8) == 7,
        do: "https://tuist.dev/users/log_in",
        else: pick(["https://tuist.dev/", "https://tuist.dev/docs"], i)

    ~s(level=info kind=#{kind} type=web-vitals app_environment=#{env} lcp=#{lcp} session_id=s#{rem(i, 9)} ) <>
      ~s(page_url="#{page}" context_rum_schema=#{schema} context_rum_quality=#{quality} ) <>
      ~s(context_rum_surface=#{surface} context_rum_deduplication=#{dedup} context_rum_ray_id=#{ray})
  end

  defp linux_agent(i) do
    msg = pick(["cache volume operation", "cache volume operation", "job started"], i)
    operation = pick(["publish", "acquire", "checkout_acquire", "publish"], div(i, 2))

    result =
      pick(
        ["success", "error", "unchanged", "execution_pending", "timeout", "cancelled", "incomplete", "withheld"],
        div(i, 3)
      )

    ~s({"level":"info","msg":"#{msg}","operation":"#{operation}","result":"#{result}","use":"use-#{rem(i, 4)}"})
  end

  defp macos_kubelet(i) do
    case rem(i, 6) do
      5 ->
        ~s({"level":"warn","msg":"custom cache volume not authorized; skipping","use":"use-#{rem(i, 3)}"})

      4 ->
        ~s({"level":"warn","msg":"custom cache volume not authorized in time","use":"use-#{rem(i, 3)}"})

      _ ->
        operation = pick(["publish", "attach"], i)

        result =
          pick(
            [
              "success",
              "invalid_image",
              "incomplete",
              "unchanged",
              "release_pending",
              "cancelled",
              "execution_pending"
            ],
            div(i, 2)
          )

        ~s({"level":"info","msg":"cache phase","operation":"#{operation}","result":"#{result}","use":"use-#{rem(i, 3)}"})
    end
  end

  defp cache_usage(i) do
    if rem(i, 3) == 2,
      do: "level=info msg=\"request served\"",
      else:
        "ts=#{i} event=cache_usage account_handle=#{pick(["tuist", "acme", "globex"], i)} cache_type=#{pick(["cas", "module"], div(i, 2))} " <>
          "action=download count=#{rem(i, 5) + 1} window_start=#{i * 30} window_end=#{i * 30 + 60}"
  end

  defp server_vm(i),
    do: if(rem(i, 11) == 0, do: "eheap_alloc: literal_alloc: Cannot allocate 1024 bytes", else: "GET /api/ready 200")

  defp phoenix(i) do
    case rem(i, 9) do
      8 ->
        "request_id=r#{i} execution token disagrees with the recorded execution"

      7 ->
        "request_id=r#{i} auth_account_handle=tuist selected_account_handle=acme Sent 200 in 30ms"

      6 ->
        "request_id=r#{i} anonymous Sent 200 in 12ms"

      _ ->
        "request_id=r#{i} auth_account_handle=tuist Sent #{pick(["200", "200", "404", "500", "503"], i)} in #{pick(["45", "180", "650", "1200", "3900", "5200"], div(i, 2))}ms"
    end
  end

  defp probe(i),
    do:
      ~s(level=#{pick(["error", "info"], i)} msg="#{pick(["Check failed", "Check failed", "Check succeeded"], div(i, 2))}" probe=Frankfurt)

  defp postgres(i),
    do:
      pick(
        [
          "LOG:  checkpoint complete",
          "LOG:  terminating walsender process due to replication timeout",
          "FATAL:  terminating walreceiver due to timeout"
        ],
        i
      )

  defp ingress(i) do
    status = pick(["200", "502", "000", "404", "504"], i)
    upstream = pick(["kura-kura-80", "kura-kura-81"], div(i, 3))

    ~s(10.0.0.#{rem(i, 9)} - - [09/Oct/2025:08:00:00 +0000] "GET /api/cache/cas HTTP/1.1" #{status} 512 "-" "tuist/4.0" 230 0.004 [#{upstream}] [] 10.1.0.5:4000 512 0.004 #{status} req#{i})
  end

  defp cache_nginx(i), do: "status=#{pick(["200", "502", "200", "404"], i)} method=GET path=/api/cache"
  defp plain(prefix), do: fn i -> "#{prefix} event #{i}" end

  defp tuist_server(i) do
    case rem(i, 4) do
      0 -> ~s(level=error selected_account_handle=tuist msg="project lookup failed")
      1 -> ~s(level=warn selected_account_handle=acme msg="slow query")
      2 -> ~s(level=info msg="GET /api/projects/tuist/tuist/previews")
      3 -> ~s(level=warn selected_account_handle=tuist msg="GET /api/projects/tuist/app retried")
    end
  end

  defp bandit(i),
    do:
      pick(
        [
          "Bandit request body read timed out",
          "Thousand Island connection dropped",
          "Bandit request raised an exception",
          "Thousand Island connection send_error",
          "unrelated warning"
        ],
        i
      )

  defp kura(i) do
    level = pick(["INFO", "INFO", "WARN", "ERROR", "DEBUG"], i)

    ~s({"level":"#{level}","msg":"segment refreshed","kura.tenant_id":"#{pick(["tuist", "acme"], div(i, 2))}","duration_ms":#{rem(i * 37, 900)}})
  end

  @doc "The streams as one Loki JSON push body."
  def loki_push(streams) do
    pushed =
      for {labels, entries} <- streams do
        %{"stream" => labels, "values" => Enum.map(entries, fn {ts, line} -> [Integer.to_string(ts), line] end)}
      end

    Pulse.JSON.encode!(%{"streams" => pushed})
  end

  @doc "The series as OpenMetrics text with timestamps (for `promtool tsdb create-blocks-from openmetrics`)."
  def openmetrics(series) do
    lines =
      for {labels, samples} <- series, {time, value} <- samples do
        {name, rest} = Map.pop(labels, "__name__")
        pairs = rest |> Enum.sort() |> Enum.map_join(",", fn {k, v} -> ~s(#{k}="#{escape_label(v)}") end)

        "#{name}{#{pairs}} #{format(value)} #{div(time, 1000)}.#{String.pad_leading(Integer.to_string(rem(time, 1000)), 3, "0")}\n"
      end

    [lines, "# EOF\n"]
  end

  defp escape_label(value),
    do: value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"") |> String.replace("\n", "\\n")

  defp format(value) when value == trunc(value), do: Integer.to_string(trunc(value))
  defp format(value), do: Float.to_string(value)

  # Grafana's rangeUtil.secondsToHms: only the largest unit.
  defp hms(seconds) do
    Enum.find_value([{31_536_000, "y"}, {86_400, "d"}, {3600, "h"}, {60, "m"}, {1, "s"}], fn {unit, suffix} ->
      if div(seconds, unit) > 0, do: "#{div(seconds, unit)}#{suffix}"
    end)
  end
end
