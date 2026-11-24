defmodule Symptoms.Sources.Probes do
  @moduledoc """
  Grafana synthetic monitoring results per journey, from the Prometheus
  metric `probe_success` (`job` is the check, `probe` the location,
  `instance` the target), read through `Symptoms.Sources.Prometheus` every
  minute. Each run is one raw sample, so the source reads
  `probe_success[<lookback>]` (default 15 minutes, `:lookback`).

  The entity is `%{service: "probes", kind: "journey", key: journey}`. A check
  belongs to the first journey in `:journeys` (`{exact | Regex, journey}`)
  matching its `job`, then its `instance`; the default list maps to
  `signup`, `registry_resolve`, `test_upload`, `cache` and `api`. An
  unmatched check is its own journey.

  Stream `"probe.journey"` (`:availability`), one record per journey:

  - a failure confirmed from 2 or more locations in their latest run, or by
    2 consecutive failing runs at one location, gets `confirmed_statistic/0`
    (`1.0e6`). No null history reaches it, but a conformal p-value cannot fall
    below `1 / (n + 1)`, so the pipeline must map it straight to the cap
    (README: "reaches the cap at once");
  - otherwise the share of the journey's `(check, location)` pairs whose
    latest run failed, so a pass gives 0 and lowers evidence for that
    journey only.

  A journey in `:entities` without valid samples in the lookback is unknown;
  empty series (including all-NaN replies) never produce healthy evidence.
  """

  @behaviour Symptoms.Sources.Source

  alias Symptoms.Sources.Prometheus
  alias Symptoms.Sources.Support

  @confirmed 1.0e6
  @default_lookback 900
  @default_journeys [
    {~r/sign-?up|register/i, "signup"},
    {~r/registry/i, "registry_resolve"},
    {~r/upload|test-?result|xcresult/i, "test_upload"},
    {~r/cache|kura/i, "cache"},
    {~r/api/i, "api"}
  ]

  @impl true
  def name, do: "probe"

  @impl true
  def window_seconds, do: 60

  @doc "The statistic of a confirmed failure; the pipeline maps it to the e-value cap."
  @spec confirmed_statistic() :: float()
  def confirmed_statistic, do: @confirmed

  @impl true
  def collect(window, opts) do
    lookback = Keyword.get(opts, :lookback, @default_lookback)

    case Prometheus.query("probe_success[#{lookback}s]", Support.finish(window), opts) do
      {:ok, series} ->
        journeys =
          series
          |> Enum.reject(&(&1.values == []))
          |> Enum.group_by(&journey(&1.metric, opts))
          |> Map.delete(nil)

        records = Enum.map(journeys, fn {journey, group} -> record(journey, group, window, opts) end)
        seen = MapSet.new(records, & &1.entity)

        Support.report_unknown(
          opts,
          "probe.journey",
          Enum.filter(Support.expected_entities(opts), &(&1.kind == "journey" and not MapSet.member?(seen, &1)))
        )

        {:ok, records}

      {:error, _reason} ->
        {:unknown, Support.expected_entities(opts)}
    end
  end

  defp record(journey, series, window, opts) do
    runs =
      for %{metric: metric, values: [_ | _] = values} <- series do
        latest = values |> Enum.sort(:desc) |> Enum.take(2) |> Enum.map(&(elem(&1, 1) < 1.0))
        %{check: metric["job"], location: metric["probe"], failed: hd(latest), consecutive: latest == [true, true]}
      end

    failed = Enum.filter(runs, & &1.failed)
    pairs = length(runs)

    statistic = if confirmed?(runs), do: @confirmed, else: length(failed) / pairs

    Support.record(window, Support.entity(opts, "probes", "journey", journey),
      phenomenon: :availability,
      source: "probe.journey",
      statistic: statistic,
      observed: length(failed),
      n: pairs,
      impact: %{unit: "failing_probe_locations", rate: length(failed) * 1.0},
      examples: failed |> Enum.map(&"#{&1.check}@#{&1.location}") |> Enum.uniq() |> Enum.take(3)
    )
  end

  @doc """
  Whether runs (`%{check, location, failed, consecutive}`) confirm a failure:
  one check failing at 2+ locations in their latest run, or any location
  failing twice in a row.
  """
  @spec confirmed?([map()]) :: boolean()
  def confirmed?(runs) do
    Enum.any?(runs, & &1.consecutive) or
      runs
      |> Enum.filter(& &1.failed)
      |> Enum.group_by(& &1.check, & &1.location)
      |> Enum.any?(fn {_check, locations} -> length(Enum.uniq(locations)) >= 2 end)
  end

  @doc "The journey of a `probe_success` series, from its labels."
  @spec journey(map(), keyword()) :: String.t() | nil
  def journey(metric, opts) do
    journeys = Keyword.get(opts, :journeys, @default_journeys)

    Enum.find_value([metric["job"], metric["instance"]], fn label ->
      is_binary(label) && Enum.find_value(journeys, &match(&1, label))
    end) || metric["job"]
  end

  defp match({%Regex{} = pattern, journey}, label), do: if(Regex.match?(pattern, label), do: journey)
  defp match({exact, journey}, label), do: if(exact == label, do: journey)
end
