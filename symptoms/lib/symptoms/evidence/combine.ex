defmodule Symptoms.Evidence.Combine do
  @moduledoc """
  Combines calibrated e-values into one score per window and runs the CUSUM
  (`symptoms/README.md` "Combining", steps 1–3).

  1. Within a phenomenon, for one entity, `phenomenon_e/2` takes the weighted
     mean of the sources' e-values. Weights come from `source_weights/2`:
     normalized to sum 1 and bounded to 0.5–2× the equal weight. A weighted
     mean of e-values is an e-value under any dependence.
  2. Across phenomena, `log_evidence/2` adds the natural logs with weight 1,
     each phenomenon clamped to `±ln(Calibration.cap())` nats by default.
  3. `cusum_step/3`: `S_t = max(0, S_{t-1} + x_t - drift)`.
  """

  alias Symptoms.Evidence.Calibration

  @min_ratio 0.5
  @max_ratio 2.0

  @type phenomenon_score :: %{
          phenomenon: atom(),
          e: float(),
          nats: float(),
          sources: [String.t()]
        }

  @doc """
  Normalized weights for `sources` from raw daily weights (`%{source => w}`;
  a missing source has raw weight 1). The result sums to 1 and each weight
  lies in `[0.5/k, 2/k]` for `k` sources. Among such weights it keeps the
  raw proportions where the bounds allow: `w_i = clamp(c · r_i)` with the
  scale `c` solved by bisection.
  """
  @spec source_weights(%{optional(term()) => number()}, [term()]) :: %{optional(term()) => float()}
  def source_weights(_raw, []), do: %{}

  def source_weights(raw, sources) do
    sources = Enum.uniq(sources)
    k = length(sources)
    lower = @min_ratio / k
    upper = @max_ratio / k
    weights = Enum.map(sources, &max(Map.get(raw, &1, 1.0), 0.0))
    largest = Enum.max(weights)

    if largest == 0 do
      Map.new(sources, &{&1, 1 / k})
    else
      # A zero weight would sit at the lower bound for any scale; a tiny floor
      # lets the bisection raise it when the bounds force mass onto it.
      weights = Enum.map(weights, &max(&1, largest * 1.0e-9))
      scale = bisect_scale(weights, lower, upper, 0.0, upper / Enum.min(weights), 200)

      sources
      |> Enum.zip(weights)
      |> Map.new(fn {source, weight} -> {source, clamp(scale * weight, lower, upper)} end)
    end
  end

  defp bisect_scale(_weights, _lower, _upper, low, high, 0), do: (low + high) / 2

  defp bisect_scale(weights, lower, upper, low, high, steps) do
    middle = (low + high) / 2
    total = weights |> Enum.map(&clamp(middle * &1, lower, upper)) |> Enum.sum()

    if total < 1,
      do: bisect_scale(weights, lower, upper, middle, high, steps - 1),
      else: bisect_scale(weights, lower, upper, low, middle, steps - 1)
  end

  defp clamp(value, lower, upper), do: value |> max(lower) |> min(upper)

  @doc """
  The weighted mean e-value of one phenomenon's sources, given
  `[{source, e}]` and raw weights for `source_weights/2`. Returns `1.0` (no
  evidence) when there are no sources.
  """
  @spec phenomenon_e([{term(), number()}], %{optional(term()) => number()}) :: float()
  def phenomenon_e([], _raw_weights), do: 1.0

  def phenomenon_e(source_values, raw_weights) do
    weights = source_weights(raw_weights, Enum.map(source_values, &elem(&1, 0)))
    count_per_source = Enum.frequencies_by(source_values, &elem(&1, 0))

    # Several values from one source share that source's weight.
    source_values
    |> Enum.map(fn {source, e} -> weights[source] / count_per_source[source] * e end)
    |> Enum.sum()
  end

  @doc """
  The combined log-evidence `Σ clamp(ln e_φ, -cap, cap)` over a
  `%{phenomenon => e}` map. Option `:cap_nats` defaults to `ln(20)`.
  """
  @spec log_evidence(%{optional(atom()) => number()}, keyword()) :: float()
  def log_evidence(phenomenon_e_values, opts \\ []) do
    cap = Keyword.get(opts, :cap_nats, default_cap_nats())

    phenomenon_e_values
    |> Map.values()
    |> Enum.map(&capped_nats(&1, cap))
    |> Enum.sum()
    |> Kernel.+(0.0)
  end

  defp capped_nats(e, cap) when e <= 0, do: -cap
  defp capped_nats(e, cap), do: e |> :math.log() |> clamp(-cap, cap)

  defp default_cap_nats, do: :math.log(Calibration.cap())

  @doc """
  Scores one entity's window from its evidence records (anything with
  `:phenomenon`, `:source` and `:e`, such as `Symptoms.Evidence.Record`).

  `raw_weights` is `%{phenomenon => %{source => raw weight}}`. Returns the
  combined `log_evidence` and one `t:phenomenon_score/0` per phenomenon,
  sorted by phenomenon. Options are passed to `log_evidence/2`.
  """
  @spec score([map()], %{optional(atom()) => map()}, keyword()) :: %{
          log_evidence: float(),
          phenomena: [phenomenon_score()]
        }
  def score(records, raw_weights \\ %{}, opts \\ []) do
    cap = Keyword.get(opts, :cap_nats, default_cap_nats())

    phenomena =
      records
      |> Enum.group_by(& &1.phenomenon, &{&1.source, &1.e})
      |> Enum.sort()
      |> Enum.map(fn {phenomenon, source_values} ->
        e = phenomenon_e(source_values, Map.get(raw_weights, phenomenon, %{}))

        %{
          phenomenon: phenomenon,
          e: e,
          nats: capped_nats(e, cap),
          sources: source_values |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
        }
      end)

    %{log_evidence: phenomena |> Enum.map(& &1.nats) |> Enum.sum() |> Kernel.+(0.0), phenomena: phenomena}
  end

  @doc "One CUSUM step: `max(0, previous + x - drift)`."
  @spec cusum_step(number(), number(), number()) :: float()
  def cusum_step(previous, x, drift), do: max(0.0, previous + x - drift)

  @doc "The CUSUM path over a sequence of combined log-evidence values, starting at 0."
  @spec cusum([number()], number()) :: [float()]
  def cusum(xs, drift) do
    xs
    |> Enum.scan(0.0, &cusum_step(&2, &1, drift))
    |> Enum.map(&(&1 + 0.0))
  end
end
