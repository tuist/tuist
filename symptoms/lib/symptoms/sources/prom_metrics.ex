defmodule Symptoms.Sources.PromMetrics do
  @moduledoc """
  Prometheus/Mimir metrics (README "Inputs", Metrics and Shared resources),
  evaluated every minute through `Symptoms.Sources.Prometheus`.

  The definitions come from `config :symptoms, #{inspect(__MODULE__)},
  entities: [...]` or the `:definitions` option, and default to
  `Symptoms.Sources.PromMetrics.Entities.all/0` (the 90 production series of
  the replay manifest). A definition is `%{key, phenomenon, role, split,
  units, promql}`; see that module for the roles.

  Entities are `%{service: <first key segment>, kind: "metric", key: key}`.
  A `:numerator` whose `x.requests` `:denominator` exists becomes one entity
  keyed `x` (for example `ingress.tuist-dev`).

  Streams. Every residual is `Statistics.robust_residual/3` against the
  hour-of-week baseline the `:baseline` option returns for the stream and
  entity: a list of numbers, such as `Statistics.hour_of_week_baseline/3` over
  the windows `history/3` returns. An entity without a baseline gets no
  residual record and is reported through `:discovered`.

  - `"metric.error_share"` (pairs): the residual of `numerator /
    denominator`. Impact: failed requests per minute (the increase is over
    5 minutes).
  - `"metric.robust_residual"` (every other role): the residual of the value.
  - `"metric.backlog_growth"` (`:backlog`, `:saturation`): the residual of
    `deriv((promql)[15m:1m])`, jobs per second.
  - `"metric.time_to_drain"` (`:backlog`, `:saturation`): the raw seconds
    until the backlog empties at its current slope, `value / -slope`, capped at
    one day, and one day when it is not draining. 0 when empty. Calibration
    ranks it against its own history, so it needs no baseline.

  A definition whose series is missing is unknown (its query uses `or (0 *
  ...)` where zero is meaningful); when no query succeeds the source returns
  `{:unknown, entities}`.
  """

  @behaviour Symptoms.Sources.Source

  alias Symptoms.Evidence.Statistics
  alias Symptoms.Sources.Prometheus
  alias Symptoms.Sources.PromMetrics.Entities
  alias Symptoms.Sources.Support

  @max_drain 86_400.0
  @history_days 28
  @history_step 300

  @impl true
  def name, do: "metric"

  @impl true
  def window_seconds, do: 60

  @doc "The configured definitions."
  @spec definitions(keyword()) :: [map()]
  def definitions(opts) do
    Keyword.get_lazy(opts, :definitions, fn ->
      :symptoms |> Application.get_env(__MODULE__, []) |> Keyword.get_lazy(:entities, &Entities.all/0)
    end)
  end

  @doc "The entity a definition's evidence is about."
  @spec entity(map(), [map()], keyword()) :: map()
  def entity(definition, definitions, opts) do
    key =
      case denominator(definition, definitions) do
        nil -> definition.key
        _ -> prefix(definition.key)
      end

    Support.entity(opts, key |> String.split(".") |> hd(), "metric", key)
  end

  @impl true
  def collect(window, opts) do
    definitions = definitions(opts)
    at = Support.finish(window)
    values = fetch(definitions, at, &Function.identity/1, opts)

    if map_size(values) == 0 do
      {:unknown, Enum.map(evaluated(definitions), &entity(&1, definitions, opts))}
    else
      backlogs = Enum.filter(definitions, &(&1.role == :backlog))
      slopes = fetch(backlogs, at, &"deriv((#{&1})[15m:1m])", opts)

      {records, missing} =
        definitions
        |> evaluated()
        |> Enum.map(&evaluate(&1, definitions, values, slopes, window, opts))
        |> Enum.reduce({[], []}, fn
          {:ok, records}, {acc, missing} -> {acc ++ records, missing}
          {:missing, entity}, {acc, missing} -> {acc, [entity | missing]}
        end)

      Support.report_unknown(opts, "metric", Enum.reverse(missing))
      {:ok, records}
    end
  end

  # Denominators feed their numerator's share; they are not evaluated alone.
  defp evaluated(definitions) do
    Enum.reject(definitions, fn d ->
      d.role == :denominator and Enum.any?(definitions, &(denominator(&1, definitions) == d))
    end)
  end

  defp evaluate(definition, definitions, values, slopes, window, opts) do
    entity = entity(definition, definitions, opts)

    case {definition.role, denominator(definition, definitions)} do
      {:numerator, %{} = denominator} ->
        with {:ok, numerator} <- Map.fetch(values, definition.key),
             {:ok, total} <- Map.fetch(values, denominator.key) do
          {:ok, share_records(definition, entity, numerator, total, window, opts)}
        else
          :error -> {:missing, entity}
        end

      {_role, _} ->
        case Map.fetch(values, definition.key) do
          {:ok, value} -> {:ok, level_records(definition, entity, value, slopes, window, opts)}
          :error -> {:missing, entity}
        end
    end
  end

  defp level_records(definition, entity, value, slopes, window, opts) do
    level = residual_records(definition, entity, "metric.robust_residual", value, window, opts)

    if definition.role == :backlog,
      do: level ++ backlog_records(definition, entity, value, slopes, window, opts),
      else: level
  end

  defp share_records(definition, entity, numerator, total, window, opts) do
    share = if total > 0, do: numerator / total, else: 0.0

    case Support.baseline(opts, "metric.error_share", entity) do
      [_ | _] = baseline ->
        [
          Support.record(window, entity,
            phenomenon: definition.phenomenon,
            source: "metric.error_share",
            statistic: Statistics.robust_residual(share, baseline),
            observed: share,
            expected: Statistics.median(baseline),
            n: round(total),
            impact: %{unit: "failed_requests_per_min", rate: max(numerator, 0.0) / 5}
          )
        ]

      _ ->
        Support.report_discovered(opts, [entity])
        []
    end
  end

  defp residual_records(definition, entity, source, value, window, opts) do
    case Support.baseline(opts, source, entity) do
      [_ | _] = baseline ->
        [
          Support.record(window, entity,
            phenomenon: definition.phenomenon,
            source: source,
            statistic: Statistics.robust_residual(value, baseline),
            observed: value,
            expected: Statistics.median(baseline)
          )
        ]

      _ ->
        Support.report_discovered(opts, [entity])
        []
    end
  end

  defp backlog_records(definition, entity, value, slopes, window, opts) do
    case Map.fetch(slopes, definition.key) do
      {:ok, slope} ->
        residual_records(definition, entity, "metric.backlog_growth", slope, window, opts) ++
          [
            Support.record(window, entity,
              phenomenon: :saturation,
              source: "metric.time_to_drain",
              statistic: time_to_drain(value, slope),
              observed: value,
              expected: nil
            )
          ]

      :error ->
        Support.report_unknown(opts, "metric.backlog_growth", [entity])
        []
    end
  end

  @doc """
  Seconds until a backlog of `value` empties at `slope` per second: `value /
  -slope` when draining, capped at one day; one day when it is not draining;
  0 when it is empty.
  """
  @spec time_to_drain(number(), number()) :: float()
  def time_to_drain(value, _slope) when value <= 0, do: 0.0
  def time_to_drain(value, slope) when slope < 0, do: min(value / -slope, @max_drain)
  def time_to_drain(_value, _slope), do: @max_drain

  # Runs each distinct query once at `at` and picks every definition's series.
  defp fetch(definitions, at, wrap, opts) do
    definitions
    |> Enum.group_by(& &1.promql)
    |> Enum.flat_map(fn {promql, group} -> fetch_group(wrap.(promql), group, at, opts) end)
    |> Map.new()
  end

  defp fetch_group(promql, group, at, opts) do
    case Prometheus.query(promql, at, opts) do
      {:ok, series} -> for d <- group, {:ok, value} <- [pick(series, d.split)], do: {d.key, value}
      {:error, _} -> []
    end
  end

  defp pick([], _split), do: :error
  defp pick(series, nil), do: {:ok, series |> Enum.map(& &1.value) |> Enum.sum()}

  defp pick(series, {label, value}) do
    case Enum.filter(series, &(&1.metric[label] == value)) do
      [] -> :error
      matching -> {:ok, matching |> Enum.map(& &1.value) |> Enum.sum()}
    end
  end

  defp denominator(%{role: :numerator, key: key}, definitions) do
    Enum.find(definitions, &(&1.role == :denominator and &1.key == prefix(key) <> ".requests"))
  end

  defp denominator(_definition, _definitions), do: nil

  defp prefix(key), do: key |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")

  @doc """
  The trailing #{@history_days} days of an entity's stream before `at`, at
  #{@history_step}-second steps, as `[%{window_start, statistic}]` for
  `Statistics.hour_of_week_baseline/3`. `stream` is one of
  `"metric.error_share"`, `"metric.robust_residual"` or `"metric.backlog_growth"`.
  Known but inapplicable streams return `{:ok, []}` without querying: share
  requires a paired numerator, level an unpaired definition, and growth a
  backlog. Unknown entities and failed applicable queries remain errors.
  """
  @spec history(String.t(), String.t(), integer(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def history(entity_key, stream, at, opts) do
    definitions = definitions(opts)
    start = at - @history_days * 86_400

    case Enum.find(evaluated(definitions), &(entity(&1, definitions, opts).key == entity_key)) do
      nil ->
        {:error, :unknown_entity}

      definition ->
        history_stream({stream, denominator(definition, definitions), definition.role}, definition, start, at, opts)
    end
  end

  defp history_stream(kind, definition, start, at, opts) do
    case kind do
      {"metric.error_share", %{} = denominator, :numerator} ->
        with {:ok, numerator} <- range(definition, & &1, start, at, opts),
             {:ok, total} <- range(denominator, & &1, start, at, opts) do
          {:ok, for({t, n} <- numerator, d = total[t], d > 0, do: point(t, n / d))}
        end

      {"metric.robust_residual", nil, _} ->
        with {:ok, values} <- range(definition, & &1, start, at, opts) do
          {:ok, values |> Enum.sort() |> Enum.map(fn {t, v} -> point(t, v) end)}
        end

      {"metric.backlog_growth", _, :backlog} ->
        with {:ok, values} <- range(definition, &"deriv((#{&1})[15m:1m])", start, at, opts) do
          {:ok, values |> Enum.sort() |> Enum.map(fn {t, v} -> point(t, v) end)}
        end

      _ ->
        {:ok, []}
    end
  end

  defp range(definition, wrap, start, finish, opts) do
    with {:ok, series} <- Prometheus.query_range(wrap.(definition.promql), start, finish, @history_step, opts) do
      series =
        case definition.split do
          nil -> series
          {label, value} -> Enum.filter(series, &(&1.metric[label] == value))
        end

      {:ok,
       series
       |> Enum.flat_map(& &1.values)
       |> Enum.reduce(%{}, fn {t, v}, acc -> Map.update(acc, t, v, &(&1 + v)) end)}
    end
  end

  defp point(t, value), do: %{window_start: DateTime.from_unix!(t), statistic: value}
end
