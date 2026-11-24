defmodule Symptoms.Evidence.Threshold do
  @moduledoc """
  Chooses the CUSUM threshold `h` by replaying combined scores over quiet
  weeks (`symptoms/README.md` "Calibration", step 4), not from Lorden's bound.

  Count actual openings: a detector stays open until five consecutive
  non-positive windows, then resolves and resets its CUSUM, even if that
  score is still positive. A closed detector does not reset on quiet alone.
  These resets depend on `h`, so uninterrupted excursion peaks are not a
  sufficient replay summary and monotonicity must not be assumed.
  """

  alias Symptoms.Evidence.Calibration
  alias Symptoms.Evidence.Combine

  @day_seconds 86_400

  @type choice :: %{
          h: float(),
          crossings: non_neg_integer(),
          entity_days: float(),
          rate: float()
        }

  @doc "The peak of each CUSUM excursion over one entity's combined log-evidence."
  @spec excursion_peaks([number()], number()) :: [float()]
  def excursion_peaks(xs, drift) do
    {peaks, current} =
      xs
      |> Combine.cusum(drift)
      |> Enum.reduce({[], nil}, fn
        s, {peaks, nil} when s == 0 -> {peaks, nil}
        s, {peaks, current} when s == 0 -> {[current | peaks], nil}
        s, {peaks, current} -> {peaks, max(s, current || s)}
      end)

    Enum.reverse(if current, do: [current | peaks], else: peaks)
  end

  @doc "The number of detector openings, with live quiet-window reset semantics."
  @spec crossings([[number()]], number(), number(), keyword()) :: non_neg_integer()
  def crossings(series, h, drift, opts \\ []) do
    series |> Enum.map(fn xs -> elem(replay(xs, h, drift, opts), 0) end) |> Enum.sum()
  end

  # With non-negative drift, raising h up to an open episode's peak may
  # delay its opening but cannot move its five-quiet-window resolution.
  # Thus the count stays fixed until the smallest episode peak is passed.
  # For negative drift (quiet can increase S), use opening scores instead.
  defp replay(xs, h, drift, opts) do
    resolve_after = Keyword.get(opts, :resolve_after_quiet_windows, 5)
    use_peaks = drift >= 0 and h > 0

    {_, _, _, count, boundary, peak} =
      Enum.reduce(xs, {0.0, 0, false, 0, nil, nil}, fn x, {s, quiet, open, count, boundary, peak} ->
        s = Combine.cusum_step(s, x, drift)
        quiet = if x <= 0, do: quiet + 1, else: 0

        {s, quiet, open, boundary, peak} =
          if open and quiet >= resolve_after,
            do: {0.0, 0, false, smaller(boundary, peak), nil},
            else: {s, quiet, open, boundary, peak}

        if not open and s >= h do
          {s, quiet, true, count + 1, boundary, s}
        else
          peak = update_peak(open and use_peaks, peak, s)
          {s, quiet, open, count, boundary, peak}
        end
      end)

    {count, smaller(boundary, peak)}
  end

  defp update_peak(true, peak, score), do: max(peak, score)
  defp update_peak(false, peak, _score), do: peak

  defp smaller(nil, b), do: b
  defp smaller(a, nil), do: a
  defp smaller(a, b), do: min(a, b)

  @doc """
  The smallest `h` whose false-crossing rate on quiet replays is at most
  `budget` crossings per entity-day.

  `series` is one list of per-window combined log-evidence per entity, over
  windows known to be quiet. Options: `:drift` (default `0.0`),
  `:window_seconds` (default 60) to convert windows to entity-days, and
  `:min_h` (default `ln(20)`, one window at the cap), a floor for `h`.
  """
  @spec choose([[number()]], number(), keyword()) :: choice()
  def choose(series, budget, opts \\ []) do
    drift = Keyword.get(opts, :drift, 0.0)
    min_h = Keyword.get(opts, :min_h, default_min_h())
    choose_summaries(Enum.map(series, &summary(&1, drift, min_h, opts)), budget, opts)
  end

  @doc """
  One series reduced to `{steps, windows}`. Each step `{h, openings}` is
  the count from that threshold until the next step. Replays advance past
  the smallest open episode's peak (opening score for negative drift),
  stopping once no opening is possible.
  This preserves threshold-dependent resets without retaining raw series
  between entity batches. It may require many replays on adversarial data.
  Options include `:resolve_after_quiet_windows` (default 5).
  """
  @spec summary([number()], number(), number(), keyword()) :: {[{number(), non_neg_integer()}], non_neg_integer()}
  def summary(xs, drift, min_h, opts \\ []) do
    {steps(xs, drift, min_h, opts, []), length(xs)}
  end

  defp steps(xs, drift, h, opts, acc) do
    {count, boundary} = replay(xs, h, drift, opts)
    acc = [{h, count} | acc]

    if boundary == nil,
      do: Enum.reverse(acc),
      else: steps(xs, drift, next_above(boundary), opts, acc)
  end

  @doc """
  `choose/3` over `summary/3` results (made with the same `:drift` and
  `:min_h` and quiet-window setting), so a caller can discard each raw series.
  """
  @spec choose_summaries([{[{number(), non_neg_integer()}], non_neg_integer()}], number(), keyword()) :: choice()
  def choose_summaries(summaries, budget, opts \\ []) do
    window_seconds = Keyword.get(opts, :window_seconds, 60)
    min_h = Keyword.get(opts, :min_h, default_min_h())

    entity_days = (summaries |> Enum.map(&elem(&1, 1)) |> Enum.sum()) * window_seconds / @day_seconds
    allowed = floor(budget * entity_days)
    # Each series contributes a count delta at each step; scanning their
    # union finds the first acceptable threshold even for nonmonotone counts.
    deltas =
      Enum.flat_map(summaries, fn {steps, _windows} ->
        {deltas, _} = Enum.map_reduce(steps, 0, fn {h, count}, previous -> {{h, count - previous}, count} end)
        deltas
      end)

    {h, found} =
      deltas
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.update(min_h, [0], &[0 | &1])
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce_while(0, fn {h, changes}, count ->
        count = count + Enum.sum(changes)
        if count <= allowed, do: {:halt, {h, count}}, else: {:cont, count}
      end)

    %{
      h: h,
      crossings: found,
      entity_days: entity_days,
      rate: if(entity_days == 0, do: 0.0, else: found / entity_days)
    }
  end

  @doc "The default floor of `h`: one window at the e-value cap, `ln(20)`."
  @spec default_min_h() :: float()
  def default_min_h, do: :math.log(Calibration.cap())

  # CUSUM scores are non-negative. Advance exactly one representable float,
  # not an arbitrary epsilon that could skip a valid threshold interval.
  defp next_above(value) do
    <<bits::unsigned-64>> = <<value * 1.0::float-64>>
    <<next::float-64>> = <<bits + 1::unsigned-64>>
    next
  end
end
