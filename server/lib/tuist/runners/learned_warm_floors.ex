defmodule Tuist.Runners.LearnedWarmFloors do
  @moduledoc """
  Warm floors learned from each pool's own jobs, for the runners-controller's
  autoscaler (`learned_warm_floor` in `Tuist.Runners.scaling_signals_for_fleet/1`).

  A pool's jobs arrive in bursts: a workflow run fans out into several jobs
  enqueued within seconds of each other. Only a runner that is already warm
  claims a job in under 10 s, so the floor is the burst size: the 90th
  percentile, over the pool's jobs of the last 14 days, of how many of the
  pool's jobs were enqueued in the 30 seconds up to and including each one.
  With that many runners idle, 90% of jobs find a warm runner when they
  arrive.

  The floor applies only while the pool has had a job in the last 24 hours,
  so a pool nobody uses holds nothing, and a pool used every working day
  stays warm through its quiet hours.

  The controller caps it per pool (`maxLearnedWarmPoolFloor`), which is what
  bounds the cost of a pool whose bursts are larger than a floor should hold.

  One query computes every pool. Each replica caches the result for ten
  minutes, so the autoscaler's polls never reach ClickHouse.
  """

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.KeyValueStore

  require Logger

  @history_days 14
  @burst_window_seconds 30
  @burst_quantile 0.9
  @active_within_hours 24
  @cache_ttl to_timeout(minute: 10)

  @doc """
  The learned warm floor for `fleet_name`, or 0 for a pool with no job in
  the last day.
  """
  def for_fleet(fleet_name) when is_binary(fleet_name) do
    Map.get(all(), fleet_name, 0)
  end

  @doc """
  Learned warm floors for every pool with a job in the last day, keyed by
  fleet name.
  """
  def all do
    if Environment.test?() do
      compute()
    else
      KeyValueStore.get_or_update([:runners, :learned_warm_floors], [ttl: @cache_ttl], &compute/0)
    end
  end

  defp compute do
    query = """
    WITH jobs AS (
      SELECT
        argMax(fleet_name, updated_at) AS fleet,
        argMax(enqueued_at, updated_at) AS enqueued
      FROM runner_jobs
      WHERE enqueued_at >= now() - toIntervalDay({history_days:UInt32})
      GROUP BY workflow_job_id
    ),
    bursts AS (
      SELECT
        fleet,
        enqueued,
        count() OVER (
          PARTITION BY fleet
          ORDER BY toUnixTimestamp(enqueued)
          RANGE BETWEEN {burst_window_seconds:UInt32} PRECEDING AND CURRENT ROW
        ) AS burst
      FROM jobs
    )
    SELECT fleet, toInt32(quantileExact({burst_quantile:Float64})(burst))
    FROM bursts
    GROUP BY fleet
    HAVING max(enqueued) >= now() - toIntervalHour({active_within_hours:UInt32})
    """

    params = %{
      history_days: @history_days,
      burst_window_seconds: @burst_window_seconds,
      burst_quantile: @burst_quantile,
      active_within_hours: @active_within_hours
    }

    case ClickHouseRepo.query(query, params) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [fleet, floor] -> {fleet, floor} end)

      {:error, reason} ->
        Logger.warning("runners: failed to compute learned warm floors", reason: inspect(reason))
        %{}
    end
  end
end
