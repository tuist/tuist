defmodule Pulse.Parity do
  @moduledoc """
  Compares the answers two Prometheus- and Loki-compatible backends give to
  the same queries, for migrations that run Pulse next to an existing store
  (`mix pulse.parity`).

  Queries come from Grafana dashboard JSON, Grafana alert rule exports
  (provisioning API or an inventory with a `"rules"` list) or a plain list of
  `%{"expr" => ..., "language" => "promql" | "logql", "kind" => "range" | "instant"}`.
  Dashboard template variables are substituted; unset ones match anything.

  Both backends receive identical, step-aligned bounds. Results match when
  they have the same series (or streams) with the same timestamps, and values
  agree within a relative tolerance (default 1e-9); NaN matches NaN and
  infinities must be equal. Log streams must hold the same entries.
  """

  @default_tolerance 1.0e-9

  ## Query extraction

  @doc "Queries in a dashboard, rule export or plain query list, decoded from JSON."
  @type query :: %{
          expr: String.t(),
          language: :promql | :logql,
          kind: :range | :instant,
          source: String.t(),
          tolerance: float() | nil
        }

  @spec extract(term(), String.t(), map()) :: [query()]
  def extract(document, source, datasources \\ %{})

  def extract(%{"dashboard" => dashboard}, source, datasources), do: extract(dashboard, source, datasources)

  def extract(%{"kind" => "Dashboard", "spec" => dashboard}, source, datasources),
    do: extract(dashboard, source, datasources)

  def extract(%{"elements" => elements}, source, datasources) do
    elements
    |> Map.values()
    |> Enum.flat_map(fn
      %{"kind" => "Panel", "spec" => panel} ->
        for %{"spec" => %{"query" => %{"group" => group, "spec" => target}}} <-
              get_in(panel, ["data", "spec", "queries"]) || [],
            group in ["prometheus", "loki"],
            expr = target["expr"],
            is_binary(expr),
            expr != "" do
          %{
            expr: expr,
            language: language(%{"type" => group}, expr, datasources),
            kind: if(target["instant"] == true, do: :instant, else: :range),
            source: "#{source}: #{panel["title"]}",
            tolerance: nil
          }
        end

      _ ->
        []
    end)
  end

  def extract(%{"panels" => panels}, source, datasources) do
    panels
    |> Enum.flat_map(&[&1 | Map.get(&1, "panels", [])])
    |> Enum.flat_map(&panel_queries(&1, source, datasources))
  end

  def extract(%{"rules" => rules}, source, datasources), do: extract(rules, source, datasources)

  def extract(%{"queries" => queries}, source, datasources), do: extract(queries, source, datasources)

  def extract(rules, source, datasources) when is_list(rules) do
    Enum.flat_map(rules, fn
      %{"data" => data} = rule ->
        for %{"model" => %{"expr" => expr}} = node <- data, is_binary(expr), expr != "" do
          language = language(node["datasourceUid"], expr, datasources)

          %{
            expr: expr,
            language: language,
            kind: :instant,
            source: "#{source}: #{rule["title"]} (#{node["refId"]})",
            tolerance: nil
          }
        end

      %{"expr" => expr, "modes" => modes} = query ->
        for {mode, kind} <- [{"i", :instant}, {"r", :range}], String.contains?(modes, mode) do
          %{
            expr: expr,
            language: plain_language(query["language"], expr),
            kind: kind,
            source: "#{source}: #{query["id"]}",
            tolerance: query["tolerance"]
          }
        end

      %{"expr" => expr} = query ->
        [
          %{
            expr: expr,
            language: plain_language(query["language"], expr),
            kind: if(query["kind"] == "instant", do: :instant, else: :range),
            source: query["source"] || "#{source}: #{expr}",
            tolerance: query["tolerance"]
          }
        ]

      _ ->
        []
    end)
  end

  def extract(_document, _source, _datasources), do: []

  defp panel_queries(panel, source, datasources) do
    for target <- Map.get(panel, "targets", []), expr = target["expr"], is_binary(expr), expr != "" do
      language = language(target["datasource"] || panel["datasource"], expr, datasources)
      kind = if target["instant"] == true, do: :instant, else: :range
      %{expr: expr, language: language, kind: kind, source: "#{source}: #{panel["title"]}", tolerance: nil}
    end
  end

  defp plain_language("logql", _expr), do: :logql
  defp plain_language("promql", _expr), do: :promql
  defp plain_language(_, expr), do: guess_language(expr)

  defp language(%{"type" => "loki"}, _expr, _datasources), do: :logql
  defp language(%{"type" => "prometheus"}, _expr, _datasources), do: :promql
  defp language(%{"uid" => uid}, expr, datasources), do: language(uid, expr, datasources)

  defp language(uid, expr, datasources) when is_binary(uid) do
    case Map.get(datasources, uid) do
      "loki" -> :logql
      "prometheus" -> :promql
      _ -> guess_language(expr)
    end
  end

  defp language(_, expr, _datasources), do: guess_language(expr)

  # LogQL stream selectors are followed by a pipeline or sit inside a range
  # aggregation; PromQL selectors never are.
  defp guess_language(expr) do
    if Regex.match?(~r/\}\s*(\||!=|!~)|\(\s*\{[^}]*\}\s*(\||\[|!=|!~)/, expr), do: :logql, else: :promql
  end

  ## Substitution and bounds

  @doc """
  Replace Grafana variables for one window: `$__interval`, `$__rate_interval`
  and `$__range` from the step and window (seconds), named variables from
  `vars`, and unset variables in label matchers by a match-anything regex.
  """
  @spec substitute(String.t(), pos_integer(), pos_integer(), map(), pos_integer()) :: String.t()
  def substitute(expr, step, window, vars, scrape_interval \\ 15) do
    rate = max(step + scrape_interval, 4 * scrape_interval)

    expr
    |> String.replace(~r/\$\{?__rate_interval\}?/, "#{rate}s")
    |> String.replace(~r/\$\{?__range_s\}?/, "#{window}")
    |> String.replace(~r/\$\{?__range_ms\}?/, "#{window * 1000}")
    |> String.replace(~r/\$\{?__interval_ms\}?/, "#{step * 1000}")
    |> String.replace(~r/\$\{?__interval\}?/, "#{step}s")
    |> String.replace(~r/\$\{?__auto\}?/, "#{step}s")
    |> String.replace(~r/\$\{?__range\}?/, "#{window}s")
    |> substitute_named(vars)
    |> String.replace(~r/(=~?|!~|!=)\s*"[^"]*\$\{?\w+(?::\w+)?\}?[^"]*"/, ~s(=~".+"))
    |> String.replace(~r/\[\$\{?\w+\}?\]/, "[5m]")
  end

  defp substitute_named(expr, vars) do
    Enum.reduce(vars, expr, fn {name, value}, acc ->
      String.replace(acc, ~r/\$\{#{Regex.escape(name)}(?::\w+)?\}|\$#{Regex.escape(name)}\b/, value)
    end)
  end

  @doc "Step-aligned bounds for a window ending `lag` seconds before `now`, with about 300 points."
  @spec bounds(integer(), pos_integer(), non_neg_integer()) :: {integer(), integer(), pos_integer()}
  def bounds(now, window, lag) do
    step = max(div(window, 300), 15)
    finish = div(now - lag, step) * step
    {finish - window, finish, step}
  end

  ## Execution

  @doc """
  Run `query` over a window against both backends. `endpoints` maps
  `{side, language}` (`side` is `:reference` or `:candidate`) to
  `{base_url, headers}`.
  """
  def run(query, endpoints, window, opts) do
    {start, finish, step} = bounds(Keyword.fetch!(opts, :now), window, Keyword.get(opts, :lag, 300))
    expr = substitute(query.expr, step, window, Keyword.get(opts, :vars, %{}), Keyword.get(opts, :scrape_interval, 15))
    request = %{expr: expr, kind: query.kind, start: start, end: finish, step: step}
    tolerance = query.tolerance || Keyword.get(opts, :tolerance, @default_tolerance)
    fetch = Keyword.get(opts, :fetch, &fetch/3)

    reference = fetch.(Map.fetch!(endpoints, {:reference, query.language}), query.language, request)
    candidate = fetch.(Map.fetch!(endpoints, {:candidate, query.language}), query.language, request)

    outcome =
      case {reference, candidate} do
        {{:ok, a}, {:ok, b}} -> compare(a, b, tolerance)
        {{:error, a}, {:error, b}} -> {:both_error, %{reference: a, candidate: b}}
        {{:error, a}, _} -> {:reference_error, a}
        {_, {:error, b}} -> {:candidate_error, b}
      end

    %{source: query.source, language: query.language, window: window, expr: expr, outcome: outcome}
  end

  defp fetch({base, headers}, language, request) do
    {path, params} =
      case {language, request.kind} do
        {:promql, :range} ->
          {"/api/v1/query_range", [start: request.start, end: request.end, step: request.step]}

        {:promql, :instant} ->
          {"/api/v1/query", [time: request.end]}

        {:logql, :range} ->
          {"/loki/api/v1/query_range", [start: request.start, end: request.end, step: request.step, limit: 1000]}

        {:logql, :instant} ->
          {"/loki/api/v1/query", [time: request.end, limit: 1000]}
      end

    case Req.get(base <> path,
           params: [{:query, request.expr} | params],
           headers: headers,
           retry: false,
           decode_body: false,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: body}} -> normalize(Pulse.JSON.decode!(body))
      {:ok, %{status: status, body: body}} -> {:error, "HTTP #{status}: #{String.slice(body, 0, 300)}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  ## Comparison

  @doc "Normalize a Prometheus or Loki query response into `{type, %{labels => points}}`."
  def normalize(%{"status" => "success", "data" => %{"resultType" => type, "result" => result}}) do
    case type do
      "matrix" ->
        {:ok, {:samples, Map.new(result, &{&1["metric"], series_points(&1)})}}

      "vector" ->
        {:ok, {:samples, Map.new(result, &{&1["metric"], [point(&1["value"] || &1["histogram"])]})}}

      "scalar" ->
        {:ok, {:samples, %{%{} => [point(result)]}}}

      "streams" ->
        {:ok,
         {:entries, Map.new(result, &{&1["stream"], Enum.sort(Enum.map(&1["values"], fn [t, l | _] -> {t, l} end))})}}

      other ->
        {:error, "unsupported result type #{other}"}
    end
  end

  def normalize(body), do: {:error, "unexpected response #{inspect(body, limit: 10)}"}

  # Float points and native histogram points of a series, in time order.
  defp series_points(series),
    do: Enum.sort(Enum.map(Map.get(series, "values", []) ++ Map.get(series, "histograms", []), &point/1))

  defp point([time, %{} = histogram]), do: {time * 1.0, histogram(histogram)}
  defp point([time, value]), do: {time * 1.0, number(value)}

  # Count, sum and buckets as numbers, compared like floats.
  defp histogram(h) do
    buckets =
      for [rule, lower, upper, count] <- Map.get(h, "buckets", []),
          do: {rule, number(lower), number(upper), number(count)}

    {:histogram, number(h["count"]), number(h["sum"]), buckets}
  end

  defp number("NaN"), do: :nan
  defp number("+Inf"), do: :infinity
  defp number("Inf"), do: :infinity
  defp number("-Inf"), do: :negative_infinity

  defp number(text) when is_binary(text) do
    case Float.parse(text) do
      {value, ""} -> value
      _ -> text
    end
  end

  @doc "`:match` or `{:mismatch, details}` for two normalized results."
  def compare({type, a}, {type, b}, tolerance) do
    missing = Map.keys(a) -- Map.keys(b)
    extra = Map.keys(b) -- Map.keys(a)

    differing =
      for {labels, points} <- a, Map.has_key?(b, labels), not same?(type, points, b[labels], tolerance), do: labels

    if missing == [] and extra == [] and differing == [] do
      :match
    else
      {:mismatch,
       %{
         only_in_reference: Enum.take(missing, 5),
         only_in_candidate: Enum.take(extra, 5),
         differing: differing |> Enum.take(5) |> Enum.map(&diff(type, &1, a[&1], b[&1], tolerance)),
         counts: %{reference: map_size(a), candidate: map_size(b), differing: length(differing)}
       }}
    end
  end

  def compare({a, _}, {b, _}, _tolerance), do: {:mismatch, %{result_types: [a, b]}}

  defp same?(:entries, a, b, _tolerance), do: a == b

  defp same?(:samples, a, b, tolerance),
    do: length(a) == length(b) and Enum.all?(Enum.zip(a, b), fn {p, q} -> close?(p, q, tolerance) end)

  defp close?({t, x}, {t, y}, tolerance), do: value_close?(x, y, tolerance)
  defp close?(_, _, _), do: false

  defp value_close?(x, x, _tolerance), do: true

  defp value_close?({:histogram, c1, s1, b1}, {:histogram, c2, s2, b2}, tolerance) do
    value_close?(c1, c2, tolerance) and value_close?(s1, s2, tolerance) and length(b1) == length(b2) and
      Enum.all?(Enum.zip(b1, b2), fn {{r1, l1, u1, n1}, {r2, l2, u2, n2}} ->
        r1 == r2 and value_close?(l1, l2, tolerance) and value_close?(u1, u2, tolerance) and
          value_close?(n1, n2, tolerance)
      end)
  end

  defp value_close?(x, y, tolerance) when is_float(x) and is_float(y), do: abs(x - y) <= tolerance * max(abs(x), abs(y))

  defp value_close?(_, _, _), do: false

  defp diff(:entries, labels, a, b, _tolerance),
    do: %{labels: labels, reference_entries: length(a), candidate_entries: length(b)}

  defp diff(:samples, labels, a, b, tolerance) do
    first =
      a
      |> Enum.zip(b)
      |> Enum.find(fn {p, q} -> not close?(p, q, tolerance) end)

    %{labels: labels, reference_points: length(a), candidate_points: length(b), first_difference: first}
  end

  @doc "Counts of outcomes across results."
  def summary(results), do: Enum.frequencies_by(results, &outcome_name(&1.outcome))

  defp outcome_name(:match), do: :match
  defp outcome_name({name, _}), do: name
end
