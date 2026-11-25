defmodule Symptoms.Sources.PulseSpanEdges do
  @moduledoc """
  Hourly caller → callee edges for root finding (README "Combining", step 5).

  Each `collect/2` picks the hour that ended at least 10 minutes before
  `:now` (default: the end of the window), reads that hour's edges with
  `span-edges.sql` (a read-only `SELECT`, `{{hour_start}}` set to the hour)
  and passes them to the injected `:put_edges` function,
  `(hour_start :: DateTime.t(), [edge]) -> :ok | {:error, term()}`
  (`Symptoms.Store.put_edges/2`, the evaluator's own database). Nothing is
  written to Pulse, so the evaluator needs no Pulse write credential. It produces no evidence: `{:ok, []}`, or
  `{:unknown, entities}` when the hour could not be built or stored.

  An edge is `%{caller: entity, callee: entity, count: n, caller_seconds:
  float | nil, callee_seconds: float | nil}`. Span nodes are
  `%{service, kind: "span_<kind>", key: span_name}` like
  `Symptoms.Sources.PulseTraces` (kind `"span"` when a span name has several
  kinds that hour).

  Shared resources: database client spans (`db.system` set) are grouped by
  `server.address` into one resource node, `%{service: name, kind:
  "resource", key: name}`, after merging aliases (`resource_name/2`): the
  Postgres hosts `tuist-tuist-pg-rw`, `tuist-tuist-pg-pooler-rw` and
  `tuist-pg-pooler-production.taild6d7bb.ts.net` are `postgres`, and every
  ClickHouse host (both nodes) is `clickhouse`. Override with
  `:resource_aliases`, a list of `{exact_host | Regex, name}`. Ecto's pool
  checkout time (`ecto.queue_time.duration`) is part of the client span but
  counts against the caller: an edge into a resource carries it as
  `caller_seconds`, and the rest of the span time as `callee_seconds`. The
  database client span is a caller of its resource too, so when the resource
  fails, its callers (the route and its client span) degrade together: a
  shared cause (`Symptoms.Evidence.Roots`).

  The SQL below is a copy of `infra/helm/pulse/span-edges.sql`, because the
  image builds from `symptoms/` alone; a test fails when they differ.
  """

  @behaviour Symptoms.Sources.Source

  alias Symptoms.Sources.Pulse
  alias Symptoms.Sources.Support

  @settle 600
  @hour 3600
  @max_edges 50_000

  @span_edges_sql """
  SELECT
    parent.service_name AS caller_service,
    parent.span_name AS caller_span_name,
    child.service_name AS callee_service,
    child.span_name AS callee_span_name,
    count(*) AS edge_count
  FROM opentelemetry_traces AS child
  JOIN opentelemetry_traces AS parent
    ON parent.trace_id = child.trace_id AND parent.span_id = child.parent_span_id
  WHERE child."timestamp" >= CAST('{{hour_start}}' AS TIMESTAMP(9))
    AND child."timestamp" < CAST('{{hour_start}}' AS TIMESTAMP(9)) + INTERVAL '1 hour'
    AND parent."timestamp" >= CAST('{{hour_start}}' AS TIMESTAMP(9)) - INTERVAL '1 hour'
    AND parent."timestamp" < CAST('{{hour_start}}' AS TIMESTAMP(9)) + INTERVAL '1 hour'
    AND child.parent_span_id IS NOT NULL
    AND child.parent_span_id <> ''
  GROUP BY parent.service_name, parent.span_name, child.service_name, child.span_name
  """

  @default_aliases [
    {"tuist-tuist-pg-rw", "postgres"},
    {"tuist-tuist-pg-pooler-rw", "postgres"},
    {"tuist-pg-pooler-production.taild6d7bb.ts.net", "postgres"},
    {~r/clickhouse/i, "clickhouse"}
  ]

  @impl true
  def name, do: "span_edges"

  @impl true
  def window_seconds, do: @hour

  @impl true
  def collect(window, opts) do
    hour = hour_start(Keyword.get(opts, :now, Support.finish(window)))
    put_edges = Keyword.fetch!(opts, :put_edges)

    with {:ok, edges} <- Pulse.query(span_edges_sql(hour), Keyword.put(opts, :max_rows, @max_edges)),
         {:ok, kinds} <- Pulse.query(kinds_sql(hour), Keyword.put(opts, :max_rows, @max_edges)),
         {:ok, resources} <- Pulse.query(resources_sql(hour), Keyword.put(opts, :max_rows, @max_edges)),
         :ok <- put_edges.(DateTime.from_unix!(hour), build_edges(edges, kinds, resources, opts)) do
      {:ok, []}
    else
      _ -> {:unknown, Support.expected_entities(opts)}
    end
  end

  @doc "The start (Unix seconds) of the latest hour that ended at least 10 minutes before `now`."
  @spec hour_start(integer()) :: integer()
  def hour_start(now), do: div(now - @settle, @hour) * @hour - @hour

  @doc "`span-edges.sql` for the hour starting at `hour` (Unix seconds)."
  @spec span_edges_sql(integer()) :: String.t()
  def span_edges_sql(hour) do
    String.replace(@span_edges_sql, "{{hour_start}}", hour |> DateTime.from_unix!() |> DateTime.to_iso8601())
  end

  @doc false
  def span_edges_template, do: @span_edges_sql

  @doc "The span kinds of each `(service, span name)` in the hour."
  @spec kinds_sql(integer()) :: String.t()
  def kinds_sql(hour) do
    "SELECT DISTINCT service_name, span_name, span_kind FROM symptoms_trace_counts_1m " <>
      "WHERE #{Pulse.between("time_window", hour, hour + @hour)} ORDER BY service_name, span_name, span_kind"
  end

  @doc "Database client spans in the hour by server address, with pool checkout time."
  @spec resources_sql(integer()) :: String.t()
  def resources_sql(hour) do
    "SELECT service_name, span_name, \"span_attributes.server.address\" AS address, count(*) AS span_count, " <>
      "sum(duration_nano) / 1000000000.0 AS duration_seconds, " <>
      "sum(\"span_attributes.ecto.queue_time.duration\") AS queue_seconds FROM opentelemetry_traces " <>
      "WHERE #{Pulse.between("\"timestamp\"", hour, hour + @hour)} AND span_kind = 'SPAN_KIND_CLIENT' " <>
      "AND \"span_attributes.db.system\" IS NOT NULL " <>
      "GROUP BY service_name, span_name, address ORDER BY service_name, span_name, address"
  end

  @doc """
  The shared resource a host or service name belongs to, or `nil`.
  `aliases` is a list of `{exact_name | Regex, resource}`.
  """
  @spec resource_name(String.t() | nil, list()) :: String.t() | nil
  def resource_name(nil, _aliases), do: nil

  def resource_name(host, aliases) do
    host = host |> String.downcase() |> String.replace(~r/:\d+$/, "")

    Enum.find_value(aliases, fn
      {%Regex{} = pattern, name} -> if Regex.match?(pattern, host), do: name
      {exact, name} -> if host == exact or String.starts_with?(host, exact <> "."), do: name
    end)
  end

  @doc false
  def build_edges(edges, kinds, resources, opts) do
    aliases = Keyword.get(opts, :resource_aliases, @default_aliases)

    kinds =
      kinds
      |> Enum.group_by(&{&1["service_name"], &1["span_name"]}, & &1["span_kind"])
      |> Map.new(fn {k, v} -> {k, Enum.uniq(v)} end)

    shares = resource_shares(resources, aliases)
    node = &span_node(&1, &2, kinds, opts)

    edges
    |> Enum.flat_map(&edge_rows(&1, shares, node, aliases, opts))
    |> Enum.reject(&(&1.caller == &1.callee))
    |> Enum.group_by(&{&1.caller, &1.callee})
    |> Enum.map(fn {{caller, callee}, group} ->
      %{
        caller: caller,
        callee: callee,
        count: sum(group, :count),
        caller_seconds: sum(group, :caller_seconds),
        callee_seconds: sum(group, :callee_seconds)
      }
    end)
    |> Enum.sort_by(&{&1.caller.service, &1.caller.key, &1.callee.service, &1.callee.key})
  end

  # One stored edge becomes one edge, or one per resource for a database client span.
  defp edge_rows(row, shares, node, aliases, opts) do
    caller = node_or_resource(row["caller_service"], row["caller_span_name"], node, aliases, opts)
    count = row["edge_count"]

    case Map.get(shares, {row["callee_service"], row["callee_span_name"]}) do
      nil ->
        callee = node_or_resource(row["callee_service"], row["callee_span_name"], node, aliases, opts)
        [%{caller: caller, callee: callee, count: count, caller_seconds: nil, callee_seconds: nil}]

      by_resource ->
        client = node.(row["callee_service"], row["callee_span_name"])

        for {resource, share} <- by_resource,
            edge <- [
              resource_edge(caller, resource, share, count, opts),
              client_edge(client, resource, share, count, opts)
            ],
            do: edge
    end
  end

  defp client_edge(client, resource, share, count, opts),
    do: %{
      caller: client,
      callee: resource_node(resource, opts),
      count: count * share.fraction,
      caller_seconds: nil,
      callee_seconds: nil
    }

  defp resource_edge(caller, resource, share, count, opts) do
    %{
      caller: caller,
      callee: resource_node(resource, opts),
      count: count * share.fraction,
      caller_seconds: count * share.queue_per_span,
      callee_seconds: count * share.service_per_span
    }
  end

  # For each database client span, the share of its spans per resource and the
  # mean pool checkout and service time per span.
  defp resource_shares(resources, aliases) do
    resources
    |> Enum.filter(&resource_name(&1["address"], aliases))
    |> Enum.group_by(&{&1["service_name"], &1["span_name"]})
    |> Map.new(fn {key, rows} ->
      total = rows |> Enum.map(& &1["span_count"]) |> Enum.sum()

      by_resource =
        rows
        |> Enum.group_by(&resource_name(&1["address"], aliases))
        |> Map.new(fn {resource, group} ->
          spans = group |> Enum.map(& &1["span_count"]) |> Enum.sum()
          queue = group |> Enum.map(&(&1["queue_seconds"] || 0)) |> Enum.sum()
          duration = group |> Enum.map(&(&1["duration_seconds"] || 0)) |> Enum.sum()

          {resource,
           %{
             fraction: spans / total,
             queue_per_span: queue / total,
             service_per_span: max(duration - queue, 0) / total
           }}
        end)

      {key, by_resource}
    end)
  end

  defp node_or_resource(service, span_name, node, aliases, opts) do
    case resource_name(service, aliases) do
      nil -> node.(service, span_name)
      resource -> resource_node(resource, opts)
    end
  end

  defp span_node(service, span_name, kinds, opts) do
    kind =
      case Map.get(kinds, {service, span_name}, []) do
        [one] -> "span_" <> (one |> String.replace_prefix("SPAN_KIND_", "") |> String.downcase())
        _ -> "span"
      end

    Support.entity(opts, service, kind, span_name)
  end

  defp resource_node(resource, opts), do: Support.entity(opts, resource, "resource", resource)

  defp sum(group, key) do
    case group |> Enum.map(&Map.fetch!(&1, key)) |> Enum.reject(&is_nil/1) do
      [] -> nil
      values -> Enum.sum(values)
    end
  end
end
