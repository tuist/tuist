defmodule Atlas.Nudges.Analytics do
  @moduledoc """
  Nudge-owned read layer over daily analytics buckets and per-billing-period
  Air status. All rollups are computed from non-overlapping daily buckets
  so summing N rows never double counts.

  Every read returns a `%Reading{}` (not a bare ratio) so signals can tell
  a real change apart from insufficient data. `stage/1` is `:ok`,
  `:insufficient_history`, `:insufficient_sample`, `:stale`, or `:failed`
  and drives per-signal suppression.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Analytics.AirStatus
  alias Atlas.Nudges.Analytics.MetricBucket
  alias Atlas.Repo

  # Signals compare 7-day windows against 28-day baselines. A bucket younger
  # than this is considered "still measuring today"; anything older suggests
  # the refresh has fallen behind.
  @default_staleness_hours 48

  defmodule Reading do
    @moduledoc "One computed rolling read of a metric plus the guard stage that describes it."
    defstruct [
      :numerator,
      :denominator,
      :ratio,
      :window_days,
      :bucket_count,
      :latest_bucket_date,
      :computed_at,
      :stage
    ]
  end

  @doc """
  Cache effectiveness (binary-cache hit ratio) for `account` over the last
  `window` completed UTC days. `min_denominator` sets the sample-size gate
  under which the reading is `:insufficient_sample`.
  """
  def cache_effectiveness(account, opts \\ []) do
    rollup(account, :cache, opts)
  end

  @doc """
  Selective-testing effectiveness (targets skipped over targets with a
  selective-testing hash) for `account` over the last `window` completed
  UTC days. Same guards as `cache_effectiveness/2`.
  """
  def selective_testing_effectiveness(account, opts \\ []) do
    rollup(account, :selective_testing, opts)
  end

  @doc "Distinct Air (`runner_minutes`) thresholds delivered in the current billing period."
  def air_status(%Account{id: account_id}) do
    Repo.one(
      from a in AirStatus,
        where: a.account_id == ^account_id and a.metric == "runner_minutes",
        order_by: [desc: a.period_start],
        limit: 1
    )
  end

  # ---- internal ----

  defp rollup(%Account{id: account_id}, metric, opts) do
    window = Keyword.get(opts, :window, 7)
    min_history = Keyword.get(opts, :min_history, window)
    min_denominator = Keyword.get(opts, :min_denominator, min_denominator_for(metric))
    staleness_hours = Keyword.get(opts, :staleness_hours, @default_staleness_hours)

    buckets = fetch_buckets(account_id, window)

    latest = List.first(buckets)

    cond do
      buckets == [] ->
        insufficient(window, 0, latest, :insufficient_history)

      last_bucket_failed?(latest) ->
        %Reading{
          numerator: 0,
          denominator: 0,
          ratio: nil,
          window_days: window,
          bucket_count: length(buckets),
          latest_bucket_date: latest.bucket_date,
          computed_at: latest.computed_at,
          stage: :failed
        }

      length(buckets) < min_history ->
        insufficient(window, length(buckets), latest, :insufficient_history)

      stale?(latest, staleness_hours) ->
        insufficient(window, length(buckets), latest, :stale)

      true ->
        {num, denom} = sum_numerator_denominator(buckets, metric)

        stage = if denom >= min_denominator, do: :ok, else: :insufficient_sample

        %Reading{
          numerator: num,
          denominator: denom,
          ratio: safe_ratio(num, denom),
          window_days: window,
          bucket_count: length(buckets),
          latest_bucket_date: latest.bucket_date,
          computed_at: latest.computed_at,
          stage: stage
        }
    end
  end

  defp fetch_buckets(account_id, window) do
    cutoff = Date.utc_today() |> Date.add(-window)

    MetricBucket
    |> where([b], b.account_id == ^account_id and b.bucket_date >= ^cutoff)
    |> order_by([b], desc: b.bucket_date)
    |> Repo.all()
  end

  defp sum_numerator_denominator(buckets, :cache) do
    Enum.reduce(buckets, {0, 0}, fn b, {n, d} ->
      {n + b.daily_cache_hits, d + b.daily_cache_lookups}
    end)
  end

  defp sum_numerator_denominator(buckets, :selective_testing) do
    Enum.reduce(buckets, {0, 0}, fn b, {n, d} ->
      {n + b.daily_selective_hits, d + b.daily_selective_targets}
    end)
  end

  defp min_denominator_for(:cache), do: 200
  defp min_denominator_for(:selective_testing), do: 100

  defp insufficient(window, count, latest, stage) do
    %Reading{
      numerator: 0,
      denominator: 0,
      ratio: nil,
      window_days: window,
      bucket_count: count,
      latest_bucket_date: latest && latest.bucket_date,
      computed_at: latest && latest.computed_at,
      stage: stage
    }
  end

  defp last_bucket_failed?(nil), do: false
  defp last_bucket_failed?(%MetricBucket{refresh_status: "failed"}), do: true
  defp last_bucket_failed?(_bucket), do: false

  defp stale?(nil, _hours), do: true

  defp stale?(%MetricBucket{computed_at: computed_at}, hours) when is_struct(computed_at, DateTime) do
    DateTime.diff(DateTime.utc_now(), computed_at, :hour) > hours
  end

  defp stale?(_bucket, _hours), do: false

  defp safe_ratio(_num, 0), do: nil
  defp safe_ratio(num, denom), do: num / denom
end
