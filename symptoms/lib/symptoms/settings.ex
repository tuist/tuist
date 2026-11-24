defmodule Symptoms.Settings do
  @moduledoc """
  The settings in force: configuration (`config :symptoms, :detector` and
  `:policy`) overridden by the latest calibrated rows (`h`, Platt
  parameters, page prices, source weights).

  `:detector` keys, with defaults:

  - `h` (6.0): the CUSUM threshold before the weekly replay sets one per
    pipeline.
  - `drift` (0.0): the CUSUM drift.
  - `degraded_nats` (1.0): combined log-evidence above which an entity counts
    as degraded for `Symptoms.Evidence.Roots`.
  - `resolve_after_quiet_windows` (5), `reopen_hours` (24),
    `coalesce_minutes` (15), `min_history` (20), `new_entity_minutes` (60).
  - `calibrator` (`:power`) and `kappa` (0.5) for
    `Symptoms.Evidence.Calibration.e_value/2`.
  - `crossing_budget` (0.001): false crossings per entity-day for the weekly
    threshold replay.

  `:policy` keys: `day_price` (600), `night_price` (27_000), `floor_rate`
  (100) until the weekly price update writes a row, and `random`, an
  `{module, function, args}` returning a float in `[0, 1)` for delay draws.
  """

  import Ecto.Query

  alias Symptoms.Decision.Platt
  alias Symptoms.Repo
  alias Symptoms.Store.PlattParams
  alias Symptoms.Store.PriceSetting
  alias Symptoms.Store.SourceWeight
  alias Symptoms.Store.Threshold

  @detector_defaults [
    h: 6.0,
    drift: 0.0,
    degraded_nats: 1.0,
    resolve_after_quiet_windows: 5,
    reopen_hours: 24,
    coalesce_minutes: 15,
    min_history: 20,
    new_entity_minutes: 60,
    calibrator: :power,
    kappa: 0.5,
    crossing_budget: 0.001
  ]

  @adjacent_weights %{
    request_errors: %{"deploy.version_error_share_adjacent" => 0.5},
    latency: %{"deploy.version_latency_exceedance_adjacent" => 0.5}
  }

  @policy_defaults [day_price: 600.0, night_price: 27_000.0, floor_rate: 100.0]

  @doc "A `:detector` setting (see the module doc)."
  @spec detector(atom()) :: term()
  def detector(key) do
    :symptoms |> Application.get_env(:detector, []) |> Keyword.get(key, Keyword.fetch!(@detector_defaults, key))
  end

  @doc """
  The CUSUM threshold in force for the pipeline of `window_seconds` (60 or
  300): its latest weekly choice, or the configured `h`.
  """
  @spec h(pos_integer()) :: float()
  def h(window_seconds \\ 60) do
    Repo.one(
      from(t in Threshold,
        where: t.window_seconds == ^window_seconds,
        order_by: [desc: t.id],
        limit: 1,
        select: t.h
      )
    ) || detector(:h) * 1.0
  end

  @doc """
  The Platt parameters in force for the pipeline of `window_seconds`, or
  the prior mapping that pipeline's `h` to P = 0.5.
  """
  @spec platt(pos_integer()) :: Platt.params()
  def platt(window_seconds \\ 60) do
    case Repo.one(from(p in PlattParams, where: p.window_seconds == ^window_seconds, order_by: [desc: p.id], limit: 1)) do
      nil -> Platt.prior(h(window_seconds))
      params -> %{a: params.a, b: params.b}
    end
  end

  @doc "`%{day_price, night_price, floor_rate}` in force."
  @spec prices() :: %{day_price: float(), night_price: float(), floor_rate: float()}
  def prices do
    case Repo.one(from(p in PriceSetting, order_by: [desc: p.id], limit: 1)) do
      nil ->
        config = Keyword.merge(@policy_defaults, Application.get_env(:symptoms, :policy, []))

        %{
          day_price: config[:day_price] * 1.0,
          night_price: config[:night_price] * 1.0,
          floor_rate: config[:floor_rate] * 1.0
        }

      row ->
        %{day_price: row.day_price, night_price: row.night_price, floor_rate: row.floor_rate}
    end
  end

  @doc "Options for `Symptoms.Decision.Policy.decide/3`, without `:charged_roots`."
  @spec policy_opts() :: keyword()
  def policy_opts do
    prices = prices()
    opts = [day_price: prices.day_price, night_price: prices.night_price, floor_rate: prices.floor_rate]

    case :symptoms |> Application.get_env(:policy, []) |> Keyword.get(:random) do
      {module, function, args} -> Keyword.put(opts, :random, fn -> apply(module, function, args) end)
      nil -> opts
    end
  end

  @doc """
  Raw source weights `%{phenomenon_atom => %{source => weight}}` for
  `Symptoms.Evidence.Combine.score/3`. Sources without a row weigh 1, except
  `Symptoms.Deploys`' adjacent-window comparisons, which weigh 0.5.
  """
  @spec raw_weights() :: %{optional(atom()) => %{optional(String.t()) => float()}}
  def raw_weights do
    from(w in SourceWeight, select: {w.phenomenon, w.source, w.weight})
    |> Repo.all()
    |> Enum.reduce(@adjacent_weights, fn {phenomenon, source, weight}, acc ->
      Map.update(acc, String.to_existing_atom(phenomenon), %{source => weight}, &Map.put(&1, source, weight))
    end)
  end
end
