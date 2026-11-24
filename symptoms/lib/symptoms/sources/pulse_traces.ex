defmodule Symptoms.Sources.PulseTraces do
  @moduledoc """
  Request errors and latency per `(service, span kind, span name)` from the
  Pulse Flows `symptoms_trace_counts_1m` and `symptoms_trace_latency_5m`
  (`infra/helm/pulse/symptoms.sql`). The service version is a dimension: the
  evidence sums every version, and `version_stats/2` keeps them apart for the
  deploy comparison.

  The entity is `%{service: service_name, kind: "span_<kind>", key: span_name}`,
  where `<kind>` is the lowercased OTLP span kind without its prefix
  (`SPAN_KIND_SERVER` gives `span_server`).

  Streams, and the `:baseline` each reads (`baselines/2` computes both from
  28 days of the same tables):

  - `"trace.error_betabinomial"` (`:request_errors`, every minute): the
    beta-binomial residual of errors out of spans
    (`Statistics.beta_binomial_residual/3`). Baseline: `%{p: float, rho: float}`.
    Impact: failed requests per minute.
  - `"trace.latency_p95"` and `"trace.latency_p50"` (`:latency`, on minutes
    that close a 5-minute window): the binomial residual of the spans above the
    baseline's p95 or median bucket against the baseline's own share above it
    (`Statistics.latency_exceedance/3`). Baseline (stream `"trace.latency"`):
    `%{histogram: %{bucket => count}}`, optionally with `rho_p95` and `rho_p50`.
    Impact: slow requests per minute.

  Bucket indices are the Flow's (`b` holds `[1.1^b, 1.1^(b+1))` ms); the window
  and its baseline use the same indexing, which is all the exceedance needs.

  Every window it also reports each entity's per-version counts through the
  injected `:put_version_counts` (`Symptoms.Store.put_version_counts/2`), for
  the deploy tests: 1-minute errors and spans, and on minutes that close a
  5-minute window the 5-minute counts with the version's latency histogram
  and p95 (the upper bound of its p95 bucket, in ms).

  The window is unknown until the Flow sink has a later window: Pulse has no
  backfill, so a missing minute is never read as zero. Even with a complete
  sink, expected entities without positive span counts or latency buckets
  are reported unknown for the corresponding stream.
  """

  @behaviour Symptoms.Sources.Source

  alias Symptoms.Evidence.Statistics
  alias Symptoms.Sources.Pulse
  alias Symptoms.Sources.Support

  @counts "symptoms_trace_counts_1m"
  @latency "symptoms_trace_latency_5m"
  @latency_seconds 300
  @baseline_days 28
  @version_lookback 86_400
  @quantiles [{"trace.latency_p95", 0.95, :rho_p95}, {"trace.latency_p50", 0.5, :rho_p50}]

  @impl true
  def name, do: "trace"

  @impl true
  def window_seconds, do: 60

  @impl true
  def collect(window, opts) do
    finish = Support.finish(window)

    with :ok <- Pulse.complete?(@counts, finish, opts),
         {:ok, rows} <- Pulse.query(counts_sql(window.start, finish), opts) do
      by_entity = rows |> Enum.group_by(&entity(&1, opts)) |> Map.new(fn {e, rs} -> {e, sum_counts(rs)} end)
      seen = for {entity, %{spans: spans}} <- by_entity, spans > 0, do: entity
      report_missing(opts, "trace.error_betabinomial", seen)
      put_version_counts(opts, version_counts(rows, window, opts, %{}))

      by_entity
      |> Map.keys()
      |> Enum.reject(&Support.baseline(opts, "trace.error_betabinomial", &1))
      |> then(&Support.report_discovered(opts, &1))

      {:ok, error_records(by_entity, window, opts) ++ latency_records(finish, opts)}
    else
      _ -> {:unknown, Support.expected_entities(opts)}
    end
  end

  @doc "The SQL that sums span and error counts per entity and version over `[start, finish)`."
  @spec counts_sql(integer(), integer()) :: String.t()
  def counts_sql(start, finish) do
    "SELECT service_name, span_kind, span_name, service_version, sum(span_count) AS span_count, " <>
      "sum(error_count) AS error_count FROM #{@counts} WHERE #{Pulse.between("time_window", start, finish)} " <>
      "GROUP BY service_name, span_kind, span_name, service_version " <>
      "ORDER BY service_name, span_kind, span_name, service_version"
  end

  @doc "The SQL that sums the latency histogram per entity, version and bucket over `[start, finish)`."
  @spec latency_sql(integer(), integer()) :: String.t()
  def latency_sql(start, finish) do
    "SELECT service_name, span_kind, span_name, service_version, latency_bucket, sum(span_count) AS span_count " <>
      "FROM #{@latency} WHERE #{Pulse.between("time_window", start, finish)} " <>
      "GROUP BY service_name, span_kind, span_name, service_version, latency_bucket " <>
      "ORDER BY service_name, span_kind, span_name, service_version, latency_bucket"
  end

  defp error_records(by_entity, window, opts) do
    for {entity, %{spans: spans, errors: errors}} <- by_entity,
        spans > 0,
        %{p: p} = fit <- [Support.baseline(opts, "trace.error_betabinomial", entity)] do
      Support.record(window, entity,
        phenomenon: :request_errors,
        source: "trace.error_betabinomial",
        statistic: Statistics.beta_binomial_residual(errors, spans, fit),
        observed: errors / spans,
        expected: p,
        n: spans,
        impact: %{unit: "failed_requests_per_min", rate: Support.per_minute(errors, window.seconds)}
      )
    end
  end

  defp latency_records(finish, opts) when rem(finish, @latency_seconds) == 0 do
    window = %{start: finish - @latency_seconds, seconds: @latency_seconds}

    with :ok <- Pulse.complete?(@latency, finish, opts),
         {:ok, rows} <- Pulse.query(latency_sql(window.start, finish), opts) do
      by_version = version_histograms(rows, opts)

      with {:ok, counts} <- Pulse.query(counts_sql(window.start, finish), opts) do
        put_version_counts(opts, version_counts(counts, window, opts, by_version))
      end

      histograms = histograms(rows, opts)
      seen = for {entity, histogram} <- histograms, Enum.sum(Map.values(histogram)) > 0, do: entity
      for {stream, _, _} <- @quantiles, do: report_missing(opts, stream, seen)

      Enum.flat_map(histograms, fn {entity, histogram} -> latency_entity(entity, histogram, window, opts) end)
    else
      _ ->
        for {stream, _, _} <- @quantiles, do: Support.report_unknown(opts, stream, Support.expected_entities(opts))
        []
    end
  end

  defp latency_records(_finish, _opts), do: []

  defp report_missing(opts, stream, seen) do
    seen = MapSet.new(seen)
    Support.report_unknown(opts, stream, Enum.reject(Support.expected_entities(opts), &MapSet.member?(seen, &1)))
  end

  defp latency_entity(entity, histogram, window, opts) do
    case Support.baseline(opts, "trace.latency", entity) do
      %{histogram: baseline} = stored when map_size(baseline) > 0 ->
        baseline_total = baseline |> Map.values() |> Enum.sum()

        for {source, q, rho_key} <- @quantiles,
            %{n: n} = exceedance when n > 0 <- [Statistics.latency_exceedance(histogram, baseline, q)] do
          # A quantile in the top bucket leaves no baseline share above it;
          # smooth it like Statistics.fit_beta_binomial/1 so the variance stays positive.
          p = max(exceedance.expected, 0.5 / (baseline_total + 1))
          fit = %{p: p, rho: Map.get(stored, rho_key, 0.0)}

          Support.record(window, entity,
            phenomenon: :latency,
            source: source,
            statistic: Statistics.beta_binomial_residual(exceedance.exceeding, n, fit),
            observed: exceedance.observed,
            expected: exceedance.expected,
            n: n,
            impact: %{unit: "slow_requests_per_min", rate: Support.per_minute(exceedance.exceeding, window.seconds)}
          )
        end

      _ ->
        []
    end
  end

  @doc """
  Baselines for every entity from the trailing #{@baseline_days} days before
  `at` (Unix seconds): `%{entity => %{"trace.error_betabinomial" => fit,
  "trace.latency" => %{histogram: histogram}}}`. The error fit is
  `Statistics.fit_beta_binomial/1` over per-minute windows, computed from
  sufficient statistics so Pulse returns one row per entity.
  """
  @spec baselines(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def baselines(at, opts) do
    start = at - @baseline_days * 86_400

    with {:ok, errors} <- Pulse.query(error_baseline_sql(start, at), opts),
         {:ok, buckets} <- Pulse.query(latency_baseline_sql(start, at), Keyword.put_new(opts, :max_rows, 200_000)) do
      fits = Map.new(errors, &{entity(&1, opts), %{"trace.error_betabinomial" => Support.beta_binomial_from_sums(&1)}})

      histograms =
        buckets
        |> Enum.group_by(&entity(&1, opts))
        |> Map.new(fn {entity, rows} ->
          {entity, %{"trace.latency" => %{histogram: Map.new(rows, &{&1["latency_bucket"], &1["span_count"]})}}}
        end)

      {:ok, Map.merge(fits, histograms, fn _entity, a, b -> Map.merge(a, b) end)}
    end
  end

  @doc false
  def error_baseline_sql(start, finish) do
    "SELECT service_name, span_kind, span_name, sum(errors) AS errors, sum(total) AS total, " <>
      "sum(total * (total - 1)) AS pairs, sum(errors * errors) AS errors_sq, sum(errors * total) AS errors_total, " <>
      "sum(total * total) AS total_sq FROM (SELECT service_name, span_kind, span_name, time_window, " <>
      "sum(error_count) AS errors, sum(span_count) AS total FROM #{@counts} " <>
      "WHERE #{Pulse.between("time_window", start, finish)} " <>
      "GROUP BY service_name, span_kind, span_name, time_window) AS minutes " <>
      "WHERE total > 0 GROUP BY service_name, span_kind, span_name ORDER BY service_name, span_kind, span_name"
  end

  @doc false
  def latency_baseline_sql(start, finish) do
    "SELECT service_name, span_kind, span_name, latency_bucket, sum(span_count) AS span_count FROM #{@latency} " <>
      "WHERE #{Pulse.between("time_window", start, finish)} " <>
      "GROUP BY service_name, span_kind, span_name, latency_bucket " <>
      "ORDER BY service_name, span_kind, span_name, latency_bucket"
  end

  @doc """
  Per-version counts and latency histograms over `range` (`%{start, seconds}`,
  any length; latency needs 5-minute alignment) for the deploy comparison:
  `%{entity => %{version => %{spans: n, errors: n, histogram: map}}}`.
  """
  @spec version_stats(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def version_stats(range, opts) do
    finish = Support.finish(range)

    with :ok <- Pulse.complete?(@counts, finish, opts),
         {:ok, counts} <- Pulse.query(counts_sql(range.start, finish), opts),
         {:ok, buckets} <- Pulse.query(latency_sql(range.start, finish), opts) do
      histograms =
        buckets
        |> Enum.group_by(&{entity(&1, opts), version(&1)})
        |> Map.new(fn {key, rows} -> {key, Map.new(rows, &{&1["latency_bucket"], &1["span_count"]})} end)

      stats =
        counts
        |> Enum.group_by(&entity(&1, opts))
        |> Map.new(fn {entity, rows} ->
          {entity,
           Map.new(rows, fn row ->
             {version(row),
              %{
                spans: row["span_count"],
                errors: row["error_count"],
                histogram: Map.get(histograms, {entity, version(row)}, %{})
              }}
           end)}
        end)

      {:ok, stats}
    end
  end

  @impl true
  @doc """
  A deploy change per `(service, service_version)` first seen in the window,
  looking back #{div(@version_lookback, 3600)} hours (`:version_lookback`
  seconds). `before` is the service's most recently seen other version.

  `touched_entities` are the service's entities that served traffic on both
  the new version (in the window) and the old one (in the lookback). The
  design wants the entities whose code the commit range changed, but the
  evaluator has no commit-to-module mapping, so every route both versions
  serve counts as touched.
  """
  def changes(window, opts) do
    finish = Support.finish(window)
    lookback = Keyword.get(opts, :version_lookback, @version_lookback)

    with :ok <- Pulse.complete?(@counts, finish, opts),
         {:ok, rows} <- Pulse.query(versions_sql(finish - lookback, finish), opts) do
      deploys =
        rows
        |> Enum.group_by(& &1["service_name"])
        |> Enum.flat_map(fn {service, versions} -> deploys(service, versions, window.start) end)
        |> Enum.sort_by(&{&1.at, &1.service})

      with {:ok, touched} <- touched(deploys, finish - lookback, finish, opts) do
        {:ok, Enum.map(deploys, &%{&1 | touched_entities: Map.get(touched, {&1.service, &1.before, &1.after}, [])})}
      end
    end
  end

  defp touched([], _start, _finish, _opts), do: {:ok, %{}}

  defp touched(deploys, start, finish, opts) do
    pairs = Enum.filter(deploys, & &1.before)

    if pairs == [] do
      {:ok, %{}}
    else
      with {:ok, rows} <- Pulse.query(entity_versions_sql(pairs, start, finish), opts) do
        by_version = Enum.group_by(rows, &{&1["service_name"], version(&1)}, &entity(&1, opts))

        {:ok,
         Map.new(pairs, fn d ->
           both =
             MapSet.intersection(
               MapSet.new(by_version[{d.service, d.before}] || []),
               MapSet.new(by_version[{d.service, d.after}] || [])
             )

           {{d.service, d.before, d.after}, both |> MapSet.to_list() |> Enum.sort_by(& &1.key)}
         end)}
      end
    end
  end

  @doc false
  def entity_versions_sql(deploys, start, finish) do
    services = deploys |> Enum.map(& &1.service) |> Enum.uniq() |> Enum.map_join(", ", &Pulse.literal/1)
    versions = deploys |> Enum.flat_map(&[&1.before, &1.after]) |> Enum.uniq() |> Enum.map_join(", ", &Pulse.literal/1)

    "SELECT DISTINCT service_name, span_kind, span_name, service_version FROM #{@counts} " <>
      "WHERE #{Pulse.between("time_window", start, finish)} AND service_name IN (#{services}) " <>
      "AND service_version IN (#{versions}) ORDER BY service_name, span_kind, span_name, service_version"
  end

  @doc false
  def versions_sql(start, finish) do
    "SELECT service_name, service_version, to_unixtime(min(time_window)) AS first_seen, " <>
      "to_unixtime(max(time_window)) AS last_seen FROM #{@counts} " <>
      "WHERE #{Pulse.between("time_window", start, finish)} AND service_version IS NOT NULL AND service_version <> '' " <>
      "GROUP BY service_name, service_version ORDER BY service_name, service_version"
  end

  defp deploys(service, versions, start) do
    for %{"first_seen" => first} = new <- versions, first >= start do
      before =
        versions
        |> Enum.filter(&(&1["first_seen"] < start))
        |> Enum.max_by(& &1["last_seen"], fn -> nil end)

      %{
        kind: :deploy,
        ref: new["service_version"],
        at: first,
        service: service,
        touched_entities: [],
        before: before && before["service_version"],
        after: new["service_version"],
        subjects: []
      }
    end
  end

  defp put_version_counts(opts, counts) do
    case Keyword.get(opts, :put_version_counts) do
      fun when is_function(fun, 1) and counts != [] -> fun.(counts)
      _ -> :ok
    end
  end

  # One count per entity and version from count rows; with histograms (5-minute
  # windows) each count carries its version's histogram and p95.
  defp version_counts(rows, window, opts, histograms) do
    for row <- rows, (row["span_count"] || 0) > 0 do
      entity = entity(row, opts)

      count = %{
        entity: entity,
        version: version(row),
        window_start: Support.window_start(window),
        window_seconds: window.seconds,
        errors: row["error_count"] || 0,
        total: row["span_count"]
      }

      case Map.get(histograms, {entity, version(row)}) do
        nil -> count
        histogram -> Map.merge(count, %{histogram: histogram, p95_ms: p95_ms(histogram)})
      end
    end
  end

  defp p95_ms(histogram) do
    case Statistics.quantile_bucket(histogram, 0.95) do
      nil -> nil
      bucket -> Statistics.bucket_upper_bound(bucket + 1)
    end
  end

  defp version_histograms(rows, opts) do
    rows
    |> Enum.group_by(&{entity(&1, opts), version(&1)})
    |> Map.new(fn {key, rows} ->
      {key,
       Enum.reduce(rows, %{}, &Map.update(&2, &1["latency_bucket"], &1["span_count"], fn c -> c + &1["span_count"] end))}
    end)
  end

  defp histograms(rows, opts) do
    rows
    |> Enum.group_by(&entity(&1, opts))
    |> Map.new(fn {entity, rows} ->
      {entity,
       Enum.reduce(rows, %{}, fn row, acc ->
         Map.update(acc, row["latency_bucket"], row["span_count"], &(&1 + row["span_count"]))
       end)}
    end)
  end

  defp sum_counts(rows) do
    Enum.reduce(rows, %{spans: 0, errors: 0}, fn row, acc ->
      %{spans: acc.spans + (row["span_count"] || 0), errors: acc.errors + (row["error_count"] || 0)}
    end)
  end

  defp version(row), do: row["service_version"] || ""

  @doc false
  def entity(row, opts), do: Support.entity(opts, row["service_name"], span_kind(row["span_kind"]), row["span_name"])

  defp span_kind("SPAN_KIND_" <> kind), do: "span_" <> String.downcase(kind)
  defp span_kind(kind) when is_binary(kind) and kind != "", do: "span_" <> String.downcase(kind)
  defp span_kind(_kind), do: "span_unspecified"
end
