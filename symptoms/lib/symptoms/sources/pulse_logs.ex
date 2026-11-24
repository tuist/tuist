defmodule Symptoms.Sources.PulseLogs do
  @moduledoc """
  Log template counts against their service's total, from the Pulse Flows
  `symptoms_log_counts_1m` (`service`, `level`, `template_key`, `line_count`)
  and `symptoms_log_totals_1m` (`service`, `line_count`), every minute.

  The entity is `%{service: service, kind: "log_template", key: template_key}`.
  The Flows carry no route group or queue, so the key alone identifies the
  template within its service.

  Streams:

  - `"log.template_share"`: the beta-binomial residual of the template's lines
    out of the service's lines. Baseline (same stream name): `%{p: float,
    rho: float}`, from `baselines/2`. Error-level templates (`error`, `fatal`,
    `critical`, `emergency`, `alert`) are `:request_errors`, the rest
    `:platform_events`. Impact: lines per minute.
  - `"log.template_vanished"` (`:availability`): a known template that wrote
    nothing although `p × service total ≥ 20` lines were expected this
    window, and an explicit `:removed_by_deploy?` lookup confirms its code
    remains. Without removal metadata this stream is disabled: a time-based
    deploy guard would only postpone false evidence for deleted templates.
    The statistic is the residual's magnitude, so larger is worse.
  - `"log.novelty"` (`:novelty`): a template the catalogue does not know
    (`:known?`) in the window where it reaches 3 lines over at least 2 minutes
    within the last #{60} minutes; earlier sightings do not count twice. A key
    first seen within 30 minutes after a deploy of its service (`:deploys`, a
    list of `Symptoms.Sources.Source.change()`) counts only when it is
    error-level. The statistic is its line count so far. When a service has
    more than `:novelty_cap` (default 25) unknown keys in one window, its
    template keys are not stable (for example masking broke), so novelty is
    disabled for that service in that window and `:novelty_disabled`
    (`(service, unknown_key_count) -> any()`) is called.
  """

  @behaviour Symptoms.Sources.Source

  alias Symptoms.Evidence.Statistics
  alias Symptoms.Sources.Pulse
  alias Symptoms.Sources.Support

  require Logger

  @counts "symptoms_log_counts_1m"
  @totals "symptoms_log_totals_1m"
  @error_levels ~w(error fatal critical crit emergency emerg alert)
  @novelty_lines 3
  @novelty_windows 2
  @novelty_lookback 3600
  @deploy_window 1800
  @vanished_minimum 20
  @default_novelty_cap 25
  @baseline_days 28

  @impl true
  def name, do: "log"

  @impl true
  def window_seconds, do: 60

  @impl true
  def collect(window, opts) do
    finish = Support.finish(window)

    with :ok <- Pulse.complete?(@totals, finish, opts),
         :ok <- Pulse.complete?(@counts, finish, opts),
         {:ok, counts} <- Pulse.query(counts_sql(window.start, finish), opts),
         {:ok, totals} <- Pulse.query(totals_sql(window.start, finish), opts) do
      totals = Map.new(totals, &{&1["service"], &1["line_count"]})
      templates = templates_by_entity(counts, opts)
      {known, unknown} = Enum.split_with(Map.keys(templates), &Support.known?(opts, &1))

      with {:ok, novelty} <- novelty_records(unknown, templates, window, opts) do
        {:ok,
         share_records(known, templates, totals, window, opts) ++
           vanished_records(templates, totals, window, opts) ++ novelty}
      end
    else
      _ -> {:unknown, Support.expected_entities(opts)}
    end
  end

  @doc "Lines per `(service, level, template_key)` over `[start, finish)`."
  @spec counts_sql(integer(), integer()) :: String.t()
  def counts_sql(start, finish) do
    "SELECT service, \"level\", template_key, sum(line_count) AS line_count FROM #{@counts} " <>
      "WHERE #{Pulse.between("time_window", start, finish)} " <>
      ~s(GROUP BY service, "level", template_key ORDER BY service, template_key, "level")
  end

  @doc "Lines per service over `[start, finish)`."
  @spec totals_sql(integer(), integer()) :: String.t()
  def totals_sql(start, finish) do
    "SELECT service, sum(line_count) AS line_count FROM #{@totals} " <>
      "WHERE #{Pulse.between("time_window", start, finish)} GROUP BY service ORDER BY service"
  end

  @doc """
  Sightings of `keys` (`[{service, template_key}]`) over `[start, finish)`:
  lines, distinct minutes and the first minute (Unix seconds).
  """
  @spec sightings_sql([{String.t(), String.t()}], integer(), integer()) :: String.t()
  def sightings_sql(keys, start, finish) do
    services = keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.map_join(", ", &Pulse.literal/1)
    template_keys = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.map_join(", ", &Pulse.literal/1)

    "SELECT service, template_key, sum(line_count) AS line_count, count(DISTINCT time_window) AS windows, " <>
      "to_unixtime(min(time_window)) AS first_seen FROM #{@counts} " <>
      "WHERE #{Pulse.between("time_window", start, finish)} AND service IN (#{services}) " <>
      "AND template_key IN (#{template_keys}) GROUP BY service, template_key ORDER BY service, template_key"
  end

  # One entry per entity, with its levels (a template can log at several).
  defp templates_by_entity(counts, opts) do
    counts
    |> Enum.group_by(&Support.entity(opts, &1["service"], "log_template", &1["template_key"]))
    |> Map.new(fn {entity, rows} ->
      {entity,
       %{
         lines: rows |> Enum.map(& &1["line_count"]) |> Enum.sum(),
         error?: Enum.any?(rows, &error_level?(&1["level"]))
       }}
    end)
  end

  defp share_records(known, templates, totals, window, opts) do
    for entity <- known,
        %{p: p} = fit <- [Support.baseline(opts, "log.template_share", entity)],
        total = Map.get(totals, entity.service, 0),
        total > 0 do
      %{lines: lines, error?: error?} = Map.fetch!(templates, entity)

      Support.record(window, entity,
        phenomenon: if(error?, do: :request_errors, else: :platform_events),
        source: "log.template_share",
        statistic: Statistics.beta_binomial_residual(lines, total, fit),
        observed: lines / total,
        expected: p,
        n: total,
        impact: %{unit: "log_lines_per_min", rate: Support.per_minute(lines, window.seconds)}
      )
    end
  end

  defp vanished_records(templates, totals, window, opts) do
    for removed? when is_function(removed?, 1) <- [Keyword.get(opts, :removed_by_deploy?)],
        %{kind: "log_template"} = entity <- Support.expected_entities(opts),
        not Map.has_key?(templates, entity),
        %{p: p} = fit <- [Support.baseline(opts, "log.template_share", entity)],
        total = Map.get(totals, entity.service, 0),
        p * total >= @vanished_minimum,
        not removed?.(entity) do
      Support.record(window, entity,
        phenomenon: :availability,
        source: "log.template_vanished",
        statistic: -Statistics.beta_binomial_residual(0, total, fit),
        observed: 0.0,
        expected: p,
        n: total,
        impact: %{unit: "missing_log_lines_per_min", rate: Support.per_minute(p * total, window.seconds)}
      )
    end
  end

  defp novelty_records([], _templates, _window, _opts), do: {:ok, []}

  defp novelty_records(unknown, templates, window, opts) do
    cap = Keyword.get(opts, :novelty_cap, @default_novelty_cap)

    {capped, candidates} =
      unknown |> Enum.group_by(& &1.service) |> Enum.split_with(fn {_s, es} -> length(es) > cap end)

    Enum.each(capped, fn {service, entities} -> disable_novelty(service, length(entities), opts) end)
    candidates = Enum.flat_map(candidates, &elem(&1, 1))
    finish = Support.finish(window)

    if candidates == [] do
      {:ok, []}
    else
      keys = Enum.map(candidates, &{&1.service, &1.key})

      with {:ok, rows} <- Pulse.query(sightings_sql(keys, finish - @novelty_lookback, finish), opts) do
        sightings = Map.new(rows, &{{&1["service"], &1["template_key"]}, &1})

        {:ok,
         for entity <- candidates,
             %{} = seen <- [sightings[{entity.service, entity.key}]],
             new_now?(seen, Map.fetch!(templates, entity).lines),
             counts_as_novelty?(entity, seen, Map.fetch!(templates, entity).error?, opts) do
           Support.record(window, entity,
             phenomenon: :novelty,
             source: "log.novelty",
             statistic: seen["line_count"] * 1.0,
             observed: seen["line_count"],
             n: seen["windows"],
             impact: %{
               unit: "log_lines_per_min",
               rate: Support.per_minute(Map.fetch!(templates, entity).lines, window.seconds)
             }
           )
         end}
      end
    end
  end

  @doc """
  Whether a key becomes new in this window: it has #{@novelty_lines} lines in
  #{@novelty_windows} distinct minutes now, and did not before this window's
  `current_lines` (one minute) were added.
  """
  @spec new_now?(map(), non_neg_integer()) :: boolean()
  def new_now?(%{"line_count" => lines, "windows" => windows}, current_lines) do
    now? = lines >= @novelty_lines and windows >= @novelty_windows
    before? = lines - current_lines >= @novelty_lines and windows - 1 >= @novelty_windows
    now? and not before?
  end

  defp counts_as_novelty?(entity, seen, error?, opts) do
    error? or not deploy_introduced?(entity.service, seen["first_seen"], Keyword.get(opts, :deploys, []))
  end

  defp deploy_introduced?(service, first_seen, deploys) do
    Enum.any?(deploys, fn deploy ->
      deploy.kind == :deploy and deploy.service == service and first_seen >= deploy.at and
        first_seen < deploy.at + @deploy_window
    end)
  end

  defp disable_novelty(service, count, opts) do
    Logger.warning("log novelty disabled for #{service}: #{count} unknown template keys in one window")

    case Keyword.get(opts, :novelty_disabled) do
      fun when is_function(fun, 2) -> fun.(service, count)
      _ -> :ok
    end
  end

  defp error_level?(level) when is_binary(level), do: String.downcase(level) in @error_levels
  defp error_level?(_level), do: false

  @doc """
  Baselines for every template from the trailing #{@baseline_days} days
  before `at`: `%{entity => %{p: float, rho: float}}`, the beta-binomial fit of
  its lines out of its service's lines per minute (minutes where the template
  wrote nothing count as zero).
  """
  @spec baselines(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def baselines(at, opts) do
    with {:ok, rows} <-
           Pulse.query(baseline_sql(at - @baseline_days * 86_400, at), Keyword.put_new(opts, :max_rows, 200_000)) do
      {:ok,
       Map.new(rows, fn row ->
         {Support.entity(opts, row["service"], "log_template", row["template_key"]), Support.beta_binomial_from_sums(row)}
       end)}
    end
  end

  # Per template, the sums over the service's minutes. Minutes where the
  # template is absent add only to Σn, Σn² and Σn(n-1).
  @doc false
  def baseline_sql(start, finish) do
    range = Pulse.between("time_window", start, finish)

    "SELECT k.service, k.template_key, k.errors, s.total, s.pairs, k.errors_sq, k.errors_total, s.total_sq FROM " <>
      "(SELECT c.service, c.template_key, sum(c.lines) AS errors, sum(c.lines * c.lines) AS errors_sq, " <>
      "sum(c.lines * t.line_count) AS errors_total FROM " <>
      "(SELECT service, template_key, time_window, sum(line_count) AS lines FROM #{@counts} WHERE #{range} " <>
      "GROUP BY service, template_key, time_window) AS c JOIN " <>
      "(SELECT service, time_window, sum(line_count) AS line_count FROM #{@totals} WHERE #{range} " <>
      "GROUP BY service, time_window) AS t ON c.service = t.service AND c.time_window = t.time_window " <>
      "GROUP BY c.service, c.template_key) AS k JOIN " <>
      "(SELECT service, sum(n) AS total, sum(n * n) AS total_sq, sum(n * (n - 1)) AS pairs FROM " <>
      "(SELECT service, time_window, sum(line_count) AS n FROM #{@totals} WHERE #{range} GROUP BY service, time_window) AS m " <>
      "GROUP BY service) AS s ON k.service = s.service ORDER BY k.service, k.template_key"
  end
end
