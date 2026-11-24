defmodule Symptoms.Sources.Presence do
  @moduledoc """
  Whether telemetry arrived (README "Inputs", Presence), every minute.

  - `"presence.volume"` (`:availability`), per `%{service, kind: "telemetry",
    key: "traces" | "logs"}`: what arrived in the window (spans from
    `symptoms_trace_counts_1m`, log lines from `symptoms_log_totals_1m`)
    against the hour-of-week baseline the `:baseline` option returns (a list
    of per-minute counts). The statistic is the robust residual with its sign
    flipped, so less data is worse. A known entity without a baseline yet
    gets statistic 0, so its stored counts build the baseline
    (`Symptoms.Baselines` serves them). Expected entities (`:entities`) that sent
    nothing count as zero, which is the point: missing data is evidence of a
    pipeline failure. Impact: missing items per minute against the median.
  - `"presence.pulse_lag"` (`:availability`), per `%{service: "pulse", kind:
    "pipeline", key: table}`: seconds between `:now` and the end of the
    table's newest window, raw (calibration ranks it against its history).

  A Flow sink that has not reached the window's end has no volume records:
  its entities are reported through `:unknown` as `"presence.volume"`, and
  its lag record carries the evidence. When Pulse cannot be read at all the
  source returns `{:unknown, entities}`.
  """

  @behaviour Symptoms.Sources.Source

  alias Symptoms.Evidence.Statistics
  alias Symptoms.Sources.Pulse
  alias Symptoms.Sources.Support

  @tables [
    {"traces", "symptoms_trace_counts_1m", "service_name", "span_count"},
    {"logs", "symptoms_log_totals_1m", "service", "line_count"}
  ]
  @lag_lookback 3600

  @impl true
  def name, do: "presence"

  @impl true
  def window_seconds, do: 60

  @impl true
  def collect(window, opts) do
    finish = Support.finish(window)
    now = Support.now(opts)

    results = Enum.map(@tables, &read_table(&1, window.start, finish, now, opts))

    if Enum.any?(results, &match?({:error, _}, &1)) do
      {:unknown, Support.expected_entities(opts)}
    else
      {:ok, Enum.flat_map(results, fn {:ok, result} -> records(result, window, now, opts) end)}
    end
  end

  # The table's newest window, and its volumes when it has reached `finish`.
  defp read_table({type, table, column, count}, start, finish, now, opts) do
    with {:ok, latest} <- Pulse.latest_window(table, now - @lag_lookback, opts),
         {:ok, rows} <- volumes(is_integer(latest) and latest >= finish, table, column, count, start, finish, opts) do
      {:ok, {type, table, latest, rows}}
    end
  end

  defp volumes(true, table, column, count, start, finish, opts),
    do: Pulse.query(volume_sql(table, column, count, start, finish), opts)

  defp volumes(false, _table, _column, _count, _start, _finish, _opts), do: {:ok, nil}

  @doc "Items per service in `[start, finish)` from a Flow sink."
  @spec volume_sql(String.t(), String.t(), String.t(), integer(), integer()) :: String.t()
  def volume_sql(table, service_column, count_column, start, finish) do
    "SELECT #{service_column} AS service, sum(#{count_column}) AS items FROM #{table} " <>
      "WHERE #{Pulse.between("time_window", start, finish)} GROUP BY #{service_column} ORDER BY #{service_column}"
  end

  defp records({type, table, latest, rows}, window, now, opts) do
    lag_entity = Support.entity(opts, "pulse", "pipeline", table)
    # The newest window ends a minute after it starts; no data in the last hour is the full hour.
    lag = if is_integer(latest), do: max(now - (latest + 60), 0), else: @lag_lookback

    lag_record =
      Support.record(window, lag_entity,
        phenomenon: :availability,
        source: "presence.pulse_lag",
        statistic: lag * 1.0,
        observed: lag
      )

    expected = Enum.filter(Support.expected_entities(opts), &(&1.kind == "telemetry" and &1.key == type))

    case rows do
      nil ->
        Support.report_unknown(opts, "presence.volume", expected)
        [lag_record]

      rows ->
        arrived = Map.new(rows, &{Support.entity(opts, &1["service"], "telemetry", type), &1["items"]})
        entities = Enum.uniq(Map.keys(arrived) ++ expected)
        [lag_record | Enum.flat_map(entities, &volume_record(&1, Map.get(arrived, &1, 0), window, opts))]
    end
  end

  defp volume_record(entity, items, window, opts) do
    case Support.baseline(opts, "presence.volume", entity) do
      [_ | _] = baseline ->
        median = Statistics.median(baseline)

        [
          Support.record(window, entity,
            phenomenon: :availability,
            source: "presence.volume",
            statistic: -Statistics.robust_residual(items, baseline),
            observed: items,
            expected: median,
            n: items,
            impact: %{unit: "missing_items_per_min", rate: Support.per_minute(max(median - items, 0), window.seconds)}
          )
        ]

      _ ->
        if Support.known?(opts, entity) do
          [
            Support.record(window, entity,
              phenomenon: :availability,
              source: "presence.volume",
              statistic: 0.0,
              observed: items,
              n: items
            )
          ]
        else
          Support.report_discovered(opts, [entity])
          []
        end
    end
  end
end
