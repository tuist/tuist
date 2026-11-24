defmodule Symptoms.Calibrate do
  @moduledoc """
  Calibration jobs (README "Deploys" cadence table and "Labels"), one Oban
  worker with a `task` argument:

  - `source_weights` (daily): for each phenomenon and source, the weighted
    share of independent `bad` labels among labelled symptoms the source
    contributed to, over the same share for the phenomenon, each with a
    `+1/+2` prior: `w = clamp(((bad_s + 1)/(n_s + 2)) / ((bad + 1)/(n + 2)),
    0.5, 2)`. `Symptoms.Evidence.Combine.source_weights/2` normalizes and
    bounds again.
  - `platt` (weekly): per pipeline (1- and 5-minute windows),
    `Symptoms.Decision.Platt.fit/2` on that pipeline's independent labels
    once there are `:min_labels` (default 20) with both outcomes, centred on
    the prior of that pipeline's `h`; then the page prices.
  - Page prices (weekly, with `platt`): replaying the stored root scores of
    the last 28 days, each under its pipeline's Platt parameters, each period's
    price becomes the expected cost of the root ranked just past the page
    budget (`:pages_per_week_day`, default 3, and `:pages_per_week_night`,
    default 1, in `config :symptoms, :policy`), so the replay would page at
    most the budget. With fewer roots than the budget the price stays.
  - `threshold` (weekly): `Symptoms.Evidence.Threshold.choose/3` per
    pipeline (1- and 5-minute windows each get their own `h`) over every
    entity's history of the last 28 days (read 200 entities per query), combined with the source weights
    in force, with budget `:crossing_budget` (default 0.001 false crossings
    per entity-day). Every window is replayed except those of runs whose
    symptom was labelled `bad`: crossings that turned out fine, or were
    never labelled, are the false crossings the budget is about. Gaps in a
    series are joined; replay has no observations for the missing windows.
  - `refit` (on a missed incident or a page labelled fine): per pipeline,
    `Symptoms.Decision.Platt.bounded_refit/3` (intercept within 0.5 logit)
    on its labels, applied only when a replay of its last 28 days of
    labelled root scores pages at least as many `bad` symptoms and no more
    `fine` ones.
  - `retention` (daily): stream windows, root scores and version counts
    after 35 days, revisions after 30 days.

  Every result is audited.
  """
  use Oban.Worker, queue: :calibration, max_attempts: 3

  import Ecto.Query

  alias Symptoms.Decision.Platt
  alias Symptoms.Decision.Policy
  alias Symptoms.Evidence.Combine
  alias Symptoms.Evidence.Threshold
  alias Symptoms.Labels
  alias Symptoms.Repo
  alias Symptoms.Settings
  alias Symptoms.Store
  alias Symptoms.Store.Entity
  alias Symptoms.Store.Label
  alias Symptoms.Store.PlattParams
  alias Symptoms.Store.PriceSetting
  alias Symptoms.Store.Revision
  alias Symptoms.Store.RootScore
  alias Symptoms.Store.SourceWeight
  alias Symptoms.Store.StreamWindow
  alias Symptoms.Store.VersionCount

  @replay_days 28
  @pipelines [60, 300]
  @batch_entities 200
  @batch_timeout 120_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => task}}) do
    now = DateTime.utc_now()

    case task do
      "source_weights" -> update_source_weights(now)
      "platt" -> weekly_platt(now)
      "threshold" -> weekly_threshold(now)
      "refit" -> refit(now)
      "retention" -> retention(now)
    end

    :ok
  end

  ## Source weights

  @doc "Recomputes the daily source weights. Returns `%{{phenomenon, source} => weight}`."
  @spec update_source_weights(DateTime.t()) :: map()
  def update_source_weights(now) do
    labels = Repo.all(from(l in Label, where: l.independent, select: {l.outcome, l.weight, l.phenomena}))
    weights = source_weights(labels)

    rows =
      Enum.map(weights, fn {{phenomenon, source}, {weight, samples}} ->
        %{phenomenon: phenomenon, source: source, weight: weight, samples: samples, updated_at: now}
      end)

    Repo.insert_all(SourceWeight, rows,
      on_conflict: {:replace, [:weight, :samples, :updated_at]},
      conflict_target: [:phenomenon, :source]
    )

    Store.audit("source_weights", now, data: %{count: length(rows)})
    Map.new(weights, fn {key, {weight, _}} -> {key, weight} end)
  end

  @doc """
  Pure: `%{{phenomenon, source} => {weight, samples}}` from `[{outcome,
  weight, phenomena}]` where `phenomena` is the snapshot's phenomena list.
  """
  @spec source_weights([{String.t(), float(), [map()]}]) :: map()
  def source_weights(labels) do
    entries =
      for {outcome, weight, phenomena} <- labels,
          %{"phenomenon" => phenomenon, "sources" => sources} <- phenomena,
          is_list(sources),
          do: {phenomenon, sources, outcome == "bad", weight}

    totals =
      entries
      |> Enum.group_by(&elem(&1, 0))
      |> Map.new(fn {phenomenon, list} -> {phenomenon, rate(list)} end)

    entries
    |> Enum.flat_map(fn {phenomenon, sources, bad, weight} -> Enum.map(sources, &{{phenomenon, &1}, bad, weight}) end)
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {{phenomenon, _} = key, list} ->
      samples = list |> Enum.map(&elem(&1, 2)) |> Enum.sum()
      ratio = rate(Enum.map(list, fn {_, bad, w} -> {nil, nil, bad, w} end)) / totals[phenomenon]
      {key, {ratio |> max(0.5) |> min(2.0), samples * 1.0}}
    end)
  end

  defp rate(list) do
    bad = list |> Enum.filter(&elem(&1, 2)) |> Enum.map(&elem(&1, 3)) |> Enum.sum()
    total = list |> Enum.map(&elem(&1, 3)) |> Enum.sum()
    (bad + 1) / (total + 2)
  end

  ## Platt and prices

  @doc """
  The weekly Platt fit per pipeline and the price update. Returns
  `%{platt: %{window_seconds => params | :skipped}, prices: map}`.
  """
  @spec weekly_platt(DateTime.t()) :: map()
  def weekly_platt(now) do
    min_labels = :symptoms |> Application.get_env(:policy, []) |> Keyword.get(:min_labels, 20)
    platt = Map.new(@pipelines, &{&1, weekly_platt(&1, min_labels, now)})
    %{platt: platt, prices: update_prices(now)}
  end

  defp weekly_platt(window_seconds, min_labels, now) do
    samples = Labels.training_samples(window_seconds)
    classes = samples |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length()

    if length(samples) >= min_labels and classes == 2 do
      params = Platt.fit(samples, prior: Platt.prior(Settings.h(window_seconds)))
      insert_platt(params, window_seconds, "weekly", length(samples), %{}, now)
      params
    else
      :skipped
    end
  end

  defp insert_platt(params, window_seconds, kind, samples, details, now) do
    Repo.insert!(%PlattParams{
      a: params.a,
      b: params.b,
      window_seconds: window_seconds,
      kind: kind,
      samples: samples,
      details: details,
      inserted_at: now
    })

    Store.audit("platt_#{kind}", now,
      data: Map.merge(details, %{a: params.a, b: params.b, samples: samples, window_seconds: window_seconds})
    )
  end

  defp platt_by_pipeline, do: Map.new(@pipelines, &{&1, Settings.platt(&1)})

  @doc "Replays root scores to set the day and night prices. Returns the prices in force."
  @spec update_prices(DateTime.t()) :: map()
  def update_prices(now) do
    current = Settings.prices()
    params = platt_by_pipeline()
    config = Application.get_env(:symptoms, :policy, [])
    weeks = @replay_days / 7

    costs = root_costs(params, DateTime.shift(now, day: -@replay_days))

    day = price(costs, :day, round(Keyword.get(config, :pages_per_week_day, 3) * weeks), current.day_price)
    night = price(costs, :night, round(Keyword.get(config, :pages_per_week_night, 1) * weeks), current.night_price)

    if {day, night} != {current.day_price, current.night_price} do
      Repo.insert!(%PriceSetting{
        day_price: day,
        night_price: night,
        floor_rate: current.floor_rate,
        reason: "weekly",
        details: %{roots: length(costs)},
        inserted_at: now
      })

      Store.audit("prices", now, data: %{day_price: day, night_price: night})
    end

    %{current | day_price: day, night_price: night}
  end

  defp price(costs, period, budget, current) do
    ranked = costs |> Enum.map(&Map.get(&1, period)) |> Enum.reject(&is_nil/1) |> Enum.sort(:desc)

    case Enum.at(ranked, budget) do
      nil -> current
      cost -> max(cost, 1.0e-9)
    end
  end

  # Per root key and symptom, the largest expected cost by day and by night.
  defp root_costs(params, since) do
    from(r in RootScore, where: r.window_start >= ^since)
    |> Repo.all()
    |> Enum.group_by(&{&1.root_key, &1.symptom_id})
    |> Enum.map(fn {_key, rows} ->
      rows
      |> Enum.map(&row_cost(&1, params))
      |> Enum.reject(&is_nil/1)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {period, values} -> {period, Enum.max(values)} end)
    end)
  end

  # Unknown impact has no monetary/request cost. It can page at the
  # probability floor but must not train the cost-based prices.
  defp row_cost(%{impact: nil}, _params), do: nil

  defp row_cost(row, params) do
    at = DateTime.shift(row.window_start, second: row.window_seconds)
    period = if Policy.night?(at), do: :night, else: :day

    {period,
     Platt.probability(params_for(params, row.window_seconds), row.score) * row.impact * Policy.minutes_until_review(at)}
  end

  ## Threshold

  @doc """
  The weekly threshold `h` of each pipeline. Returns `%{window_seconds =>
  choice | :skipped}` with the `Symptoms.Evidence.Threshold.choose/3` result.
  """
  @spec weekly_threshold(DateTime.t()) :: %{optional(pos_integer()) => map() | :skipped}
  def weekly_threshold(now) do
    Map.new([60, 300], &{&1, weekly_threshold(&1, now)})
  end

  defp weekly_threshold(window_seconds, now) do
    since = DateTime.shift(now, day: -@replay_days)
    budget = Settings.detector(:crossing_budget)
    weights = Settings.raw_weights()

    drift = Settings.detector(:drift)
    min_h = Threshold.default_min_h()
    replay_opts = [resolve_after_quiet_windows: Settings.detector(:resolve_after_quiet_windows)]

    # One query per batch of entities, each with its own timeout. Each
    # entity's series is reduced to threshold/count steps before the next
    # batch is read. Unlike excursion peaks, these summaries preserve the
    # threshold-dependent reset after an open symptom's quiet run.
    summaries =
      from(e in Entity, order_by: e.id, select: e.id)
      |> Repo.all(timeout: @batch_timeout)
      |> Enum.chunk_every(@batch_entities)
      |> Enum.flat_map(fn ids ->
        ids
        |> replay_series(window_seconds, since, weights)
        |> Enum.map(&Threshold.summary(&1, drift, min_h, replay_opts))
      end)

    if summaries == [] do
      :skipped
    else
      choice =
        Threshold.choose_summaries(summaries, budget, drift: drift, min_h: min_h, window_seconds: window_seconds)

      Repo.insert!(
        struct(Symptoms.Store.Threshold, Map.merge(choice, %{window_seconds: window_seconds, inserted_at: now}))
      )

      Store.audit("threshold", now, data: Map.put(choice, :window_seconds, window_seconds))
      choice
    end
  end

  defp replay_series(entity_ids, window_seconds, since, weights) do
    from(w in StreamWindow,
      left_join: l in Label,
      on: l.symptom_id == w.symptom_id and l.outcome == "bad",
      where: w.entity_id in ^entity_ids,
      where: w.window_seconds == ^window_seconds and w.window_start >= ^since and is_nil(l.symptom_id),
      order_by: [asc: w.entity_id, asc: w.window_start],
      select: {w.entity_id, w.window_start, w.phenomenon, w.source, w.e}
    )
    |> Repo.all(timeout: @batch_timeout)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn rows -> rows |> Enum.chunk_by(&elem(&1, 1)) |> Enum.map(&window_evidence(&1, weights)) end)
  end

  defp window_evidence(window, weights) do
    records =
      Enum.map(window, fn {_, _, phenomenon, source, e} ->
        %{phenomenon: String.to_existing_atom(phenomenon), source: source, e: e}
      end)

    Combine.score(records, weights).log_evidence
  end

  ## Event-triggered refit

  @doc """
  The bounded refit behind the replay gate, per pipeline. Returns
  `%{window_seconds => {:applied | :rejected, %{current, candidate, before,
  after}} | :skipped}`, `:skipped` for a pipeline without labels. The gate
  needs at least `:min_refit_bads` (default 3, `config :symptoms, :policy`)
  independent `bad` symptoms in the pipeline's replay; with fewer, "loses no
  recall" would hold vacuously, so it rejects (`reason: :too_few_bads`).
  """
  @spec refit(DateTime.t()) :: %{optional(pos_integer()) => {:applied | :rejected, map()} | :skipped}
  def refit(now) do
    replay = labelled_replay(DateTime.shift(now, day: -@replay_days))
    prices = Settings.prices()
    Map.new(@pipelines, &{&1, refit(&1, replay, prices, now)})
  end

  defp refit(window_seconds, replay, prices, now) do
    samples = Labels.training_samples(window_seconds)

    if samples == [] do
      :skipped
    else
      current = Settings.platt(window_seconds)
      candidate = Platt.bounded_refit(current, samples)

      replay =
        replay
        |> Map.new(fn {key, rows} -> {key, Enum.filter(rows, &(elem(&1, 3) == window_seconds))} end)
        |> Map.reject(fn {_key, rows} -> rows == [] end)

      bads = Enum.count(replay, fn {{_id, outcome}, _rows} -> outcome == "bad" end)
      min_bads = :symptoms |> Application.get_env(:policy, []) |> Keyword.get(:min_refit_bads, 3)
      before = gate_counts(replay, current, prices)
      after_refit = gate_counts(replay, candidate, prices)

      details = %{
        current: current,
        candidate: candidate,
        before: before,
        after: after_refit,
        window_seconds: window_seconds
      }

      cond do
        bads < min_bads ->
          details = Map.merge(details, %{reason: :too_few_bads, bads: bads})
          Store.audit("platt_refit_rejected", now, data: details)
          {:rejected, details}

        after_refit.recall >= before.recall and after_refit.false_pages <= before.false_pages ->
          insert_platt(candidate, window_seconds, "refit", length(samples), %{before: before, after: after_refit}, now)
          {:applied, details}

        true ->
          Store.audit("platt_refit_rejected", now, data: details)
          {:rejected, details}
      end
    end
  end

  defp labelled_replay(since) do
    from(r in RootScore,
      join: l in Label,
      on: l.symptom_id == r.symptom_id,
      where: r.window_start >= ^since and l.independent,
      select: {l.symptom_id, l.outcome, r.window_start, r.window_seconds, r.score, r.impact}
    )
    |> Repo.all()
    |> Enum.group_by(&{elem(&1, 0), elem(&1, 1)})
  end

  @doc """
  Pure replay gate counts: over `%{{symptom_id, outcome} => [{_, _,
  window_start, window_seconds, score, impact}]}`, how many `bad` symptoms
  and how many `fine` symptoms would page under `params` and `prices`.
  `params` is one fit for every row or `%{window_seconds => params}`, each
  row under its pipeline's.
  """
  @spec gate_counts(map(), Platt.params() | %{optional(pos_integer()) => Platt.params()}, map()) :: %{
          recall: non_neg_integer(),
          false_pages: non_neg_integer()
        }
  def gate_counts(replay, params, prices) do
    paged =
      for {{_id, outcome}, rows} <- replay, Enum.any?(rows, &pages?(&1, params, prices)), do: outcome

    %{recall: Enum.count(paged, &(&1 == "bad")), false_pages: Enum.count(paged, &(&1 == "fine"))}
  end

  defp pages?({_, _, window_start, window_seconds, score, impact}, params, prices) do
    at = DateTime.shift(window_start, second: window_seconds)
    p = Platt.probability(params_for(params, window_seconds), score)
    price = if Policy.night?(at), do: prices.night_price, else: prices.day_price

    if is_nil(impact),
      do: p >= 0.9,
      else: (p >= 0.9 and impact > prices.floor_rate) or p * impact * Policy.minutes_until_review(at) > price
  end

  defp params_for(%{a: _, b: _} = params, _window_seconds), do: params
  defp params_for(by_pipeline, window_seconds), do: Map.fetch!(by_pipeline, window_seconds)

  ## Retention

  @doc "Deletes stream history, root scores and version counts after 35 days and revisions after 30."
  @spec retention(DateTime.t()) :: :ok
  def retention(now) do
    keep35 = DateTime.shift(now, week: -5)
    keep30 = DateTime.shift(now, day: -30)
    Repo.delete_all(from(w in StreamWindow, where: w.window_start < ^keep35))
    Repo.delete_all(from(r in RootScore, where: r.window_start < ^keep35))
    Repo.delete_all(from(v in VersionCount, where: v.window_start < ^keep35))
    Repo.delete_all(from(r in Revision, where: r.inserted_at < ^keep30))
    :ok
  end
end
