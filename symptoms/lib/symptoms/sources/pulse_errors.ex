defmodule Symptoms.Sources.PulseErrors do
  @moduledoc """
  Error issues from the Pulse `errors` table (one row per Sentry event,
  `infra/helm/pulse/errors.sql`), per `(service, fingerprint)` issue, every 5
  minutes. The entity is `%{service: service, kind: "error_issue", key: fingerprint}`.

  Streams:

  - `"error.negative_binomial"` (`:request_errors`): the negative binomial
    residual of the window's event count against the issue's own baseline
    (`Statistics.negative_binomial_residual/2`). Baseline (same stream name):
    `%{mean: float, alpha: float, n: integer}` per 5-minute window, from
    `baselines/2`. Expected issues (`:entities`) without events get a record
    with count 0. Impact: affected users per minute, counted as distinct
    `account_handle`s (the table has no user column).
  - `"error.novelty"` (`:novelty`): an issue the catalogue does not know
    (`:known?`). The statistic is its event count.

  Examples are the latest event ID and trace ID, never text.

  The table has no completeness marker (events are sparse, so a quiet minute
  is normal). The window is unknown until `:ingest_delay` seconds (default
  120) after it ends, judged against `:now`, or when the query fails.
  """

  @behaviour Symptoms.Sources.Source

  alias Symptoms.Evidence.Statistics
  alias Symptoms.Sources.Pulse
  alias Symptoms.Sources.Support

  @ingest_delay 120
  @baseline_days 28
  @max_issues 5_000

  @impl true
  def name, do: "error"

  @impl true
  def window_seconds, do: 300

  @impl true
  def collect(window, opts) do
    finish = Support.finish(window)

    with true <- Support.now(opts) >= finish + Keyword.get(opts, :ingest_delay, @ingest_delay),
         {:ok, rows} <- Pulse.query(issues_sql(window.start, finish), Keyword.put(opts, :max_rows, @max_issues)) do
      seen = Map.new(rows, &{Support.entity(opts, &1["service"], "error_issue", &1["fingerprint"]), &1})

      quiet =
        for %{kind: "error_issue"} = entity <- Support.expected_entities(opts),
            not Map.has_key?(seen, entity),
            into: %{},
            do: {entity, %{"events" => 0, "accounts" => 0}}

      {:ok, seen |> Map.merge(quiet) |> Enum.flat_map(&records(&1, window, opts))}
    else
      _ -> {:unknown, Support.expected_entities(opts)}
    end
  end

  @doc "Events, affected accounts and the latest IDs per issue over `[start, finish)`."
  @spec issues_sql(integer(), integer()) :: String.t()
  def issues_sql(start, finish) do
    "SELECT service, fingerprint, count(*) AS events, count(DISTINCT nullif(account_handle, '')) AS accounts, " <>
      "last_value(event_id ORDER BY \"timestamp\") AS latest_event_id, " <>
      "last_value(trace_id ORDER BY \"timestamp\") AS latest_trace_id FROM errors " <>
      "WHERE #{Pulse.between("\"timestamp\"", start, finish)} " <>
      "GROUP BY service, fingerprint ORDER BY service, fingerprint"
  end

  defp records({entity, row}, window, opts) do
    events = row["events"]
    impact = %{unit: "affected_users_per_min", rate: Support.per_minute(row["accounts"], window.seconds)}
    examples = Enum.filter([row["latest_event_id"], row["latest_trace_id"]], &(is_binary(&1) and &1 != ""))

    cond do
      fit = Support.baseline(opts, "error.negative_binomial", entity) ->
        [
          Support.record(window, entity,
            phenomenon: :request_errors,
            source: "error.negative_binomial",
            statistic: Statistics.negative_binomial_residual(events, fit),
            observed: events,
            expected: fit.mean,
            n: events,
            impact: impact,
            examples: examples
          )
        ]

      events > 0 and not Support.known?(opts, entity) ->
        Support.report_discovered(opts, [entity])

        [
          Support.record(window, entity,
            phenomenon: :novelty,
            source: "error.novelty",
            statistic: events * 1.0,
            observed: events,
            n: events,
            impact: impact,
            examples: examples
          )
        ]

      true ->
        []
    end
  end

  @doc """
  Baselines for every issue seen in the trailing #{@baseline_days} days before
  `at`: `%{entity => Statistics.negative_binomial_fit()}` over all
  #{@baseline_days * 288} five-minute windows, windows without events counting
  as zero. Computed from `Σx` and `Σx²` so Pulse returns one row per issue:
  `mean = Σx / N` and `s² = (Σx² - N mean²) / (N - 1)`.
  """
  @spec baselines(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def baselines(at, opts) do
    windows = @baseline_days * 288

    with {:ok, rows} <-
           Pulse.query(baseline_sql(at - @baseline_days * 86_400, at), Keyword.put_new(opts, :max_rows, 100_000)) do
      {:ok, Map.new(rows, &{Support.entity(opts, &1["service"], "error_issue", &1["fingerprint"]), fit(&1, windows)})}
    end
  end

  @doc false
  def fit(%{"events" => sum, "events_sq" => sum_sq}, windows) do
    mean = sum / windows
    variance = (sum_sq - windows * mean * mean) / (windows - 1)
    alpha = if mean > 0, do: max(0.0, (variance - mean) / (mean * mean)), else: 0.0
    %{mean: mean, alpha: alpha, n: windows}
  end

  @doc false
  def baseline_sql(start, finish) do
    "SELECT service, fingerprint, sum(events) AS events, sum(events * events) AS events_sq FROM " <>
      "(SELECT service, fingerprint, date_bin('5 minutes'::INTERVAL, \"timestamp\") AS time_window, count(*) AS events " <>
      "FROM errors WHERE #{Pulse.between("\"timestamp\"", start, finish)} " <>
      "GROUP BY service, fingerprint, time_window) AS windows GROUP BY service, fingerprint ORDER BY service, fingerprint"
  end
end
