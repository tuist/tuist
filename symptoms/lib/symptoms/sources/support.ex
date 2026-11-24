defmodule Symptoms.Sources.Support do
  @moduledoc false
  # Shared plumbing for the sources: entities, records and the injected
  # options documented in `Symptoms.Sources.Source`.

  alias Symptoms.Evidence.Record

  @spec finish(map()) :: integer()
  def finish(%{start: start, seconds: seconds}), do: start + seconds

  @spec window_start(map()) :: DateTime.t()
  def window_start(%{start: start}), do: DateTime.from_unix!(start)

  @spec entity(keyword(), String.t(), String.t(), String.t()) :: map()
  def entity(opts, service, kind, key),
    do: %{environment: Keyword.get(opts, :environment, "production"), service: service, kind: kind, key: key}

  @doc "Builds a record with `e: 0.0`; an invalid record is a programming error."
  @spec record(map(), map(), keyword()) :: Record.t()
  def record(window, entity, attrs) do
    attrs =
      Map.merge(
        %{entity: entity, window_start: window_start(window), window_seconds: window.seconds, e: 0.0},
        Map.new(attrs)
      )

    case Record.new(attrs) do
      {:ok, record} -> record
      {:error, reason} -> raise ArgumentError, "invalid evidence record #{inspect(reason)}: #{inspect(attrs)}"
    end
  end

  @spec baseline(keyword(), String.t(), map()) :: term()
  def baseline(opts, stream, entity) do
    case Keyword.get(opts, :baseline) do
      fun when is_function(fun, 2) -> fun.(stream, entity)
      _ -> nil
    end
  end

  @spec known?(keyword(), map()) :: boolean()
  def known?(opts, entity) do
    case Keyword.get(opts, :known?) do
      fun when is_function(fun, 1) -> fun.(entity) == true
      _ -> false
    end
  end

  @spec expected_entities(keyword()) :: [map()]
  def expected_entities(opts), do: Keyword.get(opts, :entities, [])

  @doc "Reports a stream's entities without input when the rest of the window is known."
  @spec report_unknown(keyword(), String.t(), [map()]) :: :ok
  def report_unknown(_opts, _stream, []), do: :ok

  def report_unknown(opts, stream, entities) do
    case Keyword.get(opts, :unknown) do
      fun when is_function(fun, 2) -> fun.(stream, entities)
      _ -> :ok
    end

    :ok
  end

  @doc "Reports entities seen without a baseline, for the catalogue."
  @spec report_discovered(keyword(), [map()]) :: :ok
  def report_discovered(_opts, []), do: :ok

  def report_discovered(opts, entities) do
    case Keyword.get(opts, :discovered) do
      fun when is_function(fun, 1) -> fun.(entities)
      _ -> :ok
    end

    :ok
  end

  @spec now(keyword()) :: integer()
  def now(opts), do: Keyword.get_lazy(opts, :now, fn -> System.os_time(:second) end)

  @spec per_minute(number(), pos_integer()) :: float()
  def per_minute(count, seconds), do: count * 60 / seconds

  @doc """
  `Statistics.fit_beta_binomial/1` from sums over the windows, so Pulse can
  return one row per entity: `errors` (Σx), `total` (Σn), `pairs`
  (Σ n(n-1)), `errors_sq` (Σx²), `errors_total` (Σxn) and `total_sq` (Σn²),
  using `Σ (x - n p)² = Σx² - 2p Σxn + p² Σn²`.
  """
  @spec beta_binomial_from_sums(map()) :: %{p: float(), rho: float()}
  def beta_binomial_from_sums(%{"errors" => errors, "total" => total} = sums) do
    p = if errors > 0 and errors < total, do: errors / total, else: (errors + 0.5) / (total + 1)
    squares = sums["errors_sq"] - 2 * p * sums["errors_total"] + p * p * sums["total_sq"]

    rho =
      if sums["pairs"] == 0,
        do: 0.0,
        else: ((squares / (p * (1 - p)) - total) / sums["pairs"]) |> max(0.0) |> min(1.0)

    %{p: p, rho: rho}
  end
end
