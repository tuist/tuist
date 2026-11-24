defmodule Symptoms.Evidence.Calibration do
  @moduledoc """
  Turns a raw statistic into a capped e-value (`symptoms/README.md`
  "Calibration"):

  1. `null_history/3` takes the stream's trailing windows at the same hour of
     week, excluding windows with an open symptom.
  2. `conformal_p_value/2` ranks the statistic against them:
     `p = (1 + \#{history >= s}) / (1 + n)`.
  3. `e_value/2` applies a p-to-e calibrator, `κ p^(κ-1)` with κ = 0.5 by
     default or the admissible mixture `(1 - p + p ln p) / (p (ln p)²)`, and
     caps it at 20.

  Both calibrators integrate to 1 over `p ∈ [0, 1]`, so a valid
  (super-uniform) p-value gives an e-value with mean at most 1; the cap only
  lowers it.

  ## The effective cap

  A conformal p-value is at least `1/(n+1)`, so a history of `n` windows
  gives at most `max_e/2` = `κ (n+1)^(1-κ)` (power) per window. An entity's
  own history at one hour of week over 28 days has `n` = 240 one-minute or
  48 five-minute windows, so the effective per-window maximum is
  `0.5 · √241 ≈ 7.76` (2.05 nats) and `0.5 · √49 = 3.5` (1.25 nats), not 20.
  The cap of 20 binds only when `n + 1 ≥ 1600` (borrowed family history),
  for statistics a source declares confirmed (`confirmed_statistic/0`,
  probes) and for the deploy version tests, which are e-values already.
  Raising the effective maximum would need a longer history or a calibrator
  that is no longer valid, so it stays. A loud failure still crosses the
  default `h` = 6 in 3 one-minute windows (3 · 2.05 = 6.15), as it would at
  the nominal cap (2 · 3.0 = 5.99 < 6); on 5-minute windows it needs 5
  (5 · 1.25 = 6.26).
  """

  @cap 20.0
  @default_kappa 0.5
  @default_days 28

  @type window :: %{
          required(:window_start) => DateTime.t(),
          required(:statistic) => number(),
          optional(:open_symptom) => boolean()
        }
  @type calibrator :: :power | :mixture

  @doc "The per-window e-value cap (20, about 3 nats)."
  @spec cap() :: float()
  def cap, do: @cap

  @doc """
  The largest e-value a history of `n` windows can give: the calibrator at
  the smallest conformal p-value `1/(n+1)`, capped (see "The effective
  cap"). Takes the options of `e_value/2`.
  """
  @spec max_e(non_neg_integer(), keyword()) :: float()
  def max_e(n, opts \\ []), do: e_value(1 / (n + 1), opts)

  @doc "Hour of week of a `DateTime` in its own zone: Monday 00:00 is 0, Sunday 23:00 is 167."
  @spec hour_of_week(DateTime.t()) :: 0..167
  def hour_of_week(%DateTime{} = at) do
    (Date.day_of_week(DateTime.to_date(at)) - 1) * 24 + at.hour
  end

  @doc """
  The null history for a statistic observed at `at`: the `:statistic` of
  every window that started before `at`, within the trailing `:days`
  (default #{@default_days}), at the same hour of week, and without
  `open_symptom: true`.
  """
  @spec null_history([window()], DateTime.t(), keyword()) :: [number()]
  def null_history(windows, at, opts \\ []) do
    earliest = DateTime.shift(at, day: -Keyword.get(opts, :days, @default_days))
    hour = hour_of_week(at)

    for %{window_start: start, statistic: statistic} = window <- windows,
        DateTime.before?(start, at),
        not DateTime.before?(start, earliest),
        hour_of_week(start) == hour,
        not Map.get(window, :open_symptom, false),
        do: statistic
  end

  @doc "The conformal p-value `(1 + \#{history >= s}) / (1 + n)`."
  @spec conformal_p_value(number(), [number()]) :: float()
  def conformal_p_value(statistic, history) do
    (1 + Enum.count(history, &(&1 >= statistic))) / (1 + length(history))
  end

  @doc "`conformal_p_value/2` against `null_history/3`."
  @spec p_value(number(), DateTime.t(), [window()], keyword()) :: float()
  def p_value(statistic, at, windows, opts \\ []) do
    conformal_p_value(statistic, null_history(windows, at, opts))
  end

  @doc """
  The capped e-value for a p-value.

  Options: `:calibrator` (`:power`, the default, or `:mixture`) and `:kappa`
  for the power calibrator (default #{@default_kappa}, must be in `(0, 1)`).
  """
  @spec e_value(float(), keyword()) :: float()
  def e_value(p, opts \\ [])
  def e_value(p, _opts) when p <= 0, do: @cap

  def e_value(p, opts) do
    raw =
      case Keyword.get(opts, :calibrator, :power) do
        :power -> power_calibrator(p, Keyword.get(opts, :kappa, @default_kappa))
        :mixture -> mixture_calibrator(p)
      end

    min(raw, @cap)
  end

  @doc "The uncapped power calibrator `κ p^(κ-1)` for `0 < p ≤ 1` and `0 < κ < 1`."
  @spec power_calibrator(float(), float()) :: float()
  def power_calibrator(p, kappa) when p > 0 and kappa > 0 and kappa < 1 do
    kappa * :math.pow(p, kappa - 1)
  end

  @doc """
  The uncapped admissible mixture calibrator `(1 - p + p ln p) / (p (ln p)²)`
  for `0 < p ≤ 1`. Its limit at `p → 1` is 1/2; within 1e-6 of 1 the limit is
  returned to avoid cancellation.
  """
  @spec mixture_calibrator(float()) :: float()
  def mixture_calibrator(p) when p > 0 and p > 1 - 1.0e-6, do: 0.5

  def mixture_calibrator(p) when p > 0 do
    log = :math.log(p)
    (1 - p + p * log) / (p * log * log)
  end
end
