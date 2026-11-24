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

  Skipped jobs are left out: GitHub records them with the run's other jobs
  but never asks for a runner, so counting them sized a fan-out with
  conditional jobs to twice the runners it used (a customer's 30-job
  bursts on 2026-11-13 ran 15).

  The floor applies only while the pool has had a job in the last 24 hours,
  so a pool nobody uses holds nothing, and a pool used every working day
  stays warm through its quiet hours.

  The controller caps it per pool (`maxLearnedWarmPoolFloor`), which is what
  bounds the cost of a pool whose bursts are larger than a floor should hold.
  `Tuist.Runners.scaling_signals_for_fleet/1` also caps it at the jobs the
  accounts that ran on the pool in those 14 days can still claim
  (`account_ids/1`): a warm runner no account can claim only holds a seat
  another pool's burst needs.

  The same query counts the pool's jobs of those 14 days that arrived with
  another of its jobs in the 30 seconds before them (`cold_jobs/1`): the jobs
  one warm runner does not cover, which boot cold unless the floor above it
  is funded. When the floors sum past a full rack's seats, the controller
  funds the pools with the most of them first, so the seats go where they
  save the most cold boots. It also counts the hours of those 14 days in
  which the pool had a job (`hours_with_jobs/1`), which breaks ties.

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
    all() |> Map.get(fleet_name, %{floor: 0}) |> Map.fetch!(:floor)
  end

  @doc """
  How many hours of the last 14 days had at least one of `fleet_name`'s
  jobs, or 0 for a pool with no job in the last day.
  """
  def hours_with_jobs(fleet_name) when is_binary(fleet_name) do
    all() |> Map.get(fleet_name, %{hours_with_jobs: 0}) |> Map.fetch!(:hours_with_jobs)
  end

  @doc """
  How many of `fleet_name`'s jobs of the last 14 days arrived with another of
  its jobs in the 30 seconds before them, or 0 for a pool with no job in the
  last day.
  """
  def cold_jobs(fleet_name) when is_binary(fleet_name) do
    all() |> Map.get(fleet_name, %{cold_jobs: 0}) |> Map.fetch!(:cold_jobs)
  end

  @doc """
  The accounts with a job on `fleet_name` in the last 14 days, or none for a
  pool with no job in the last day.
  """
  def account_ids(fleet_name) when is_binary(fleet_name) do
    all() |> Map.get(fleet_name, %{account_ids: []}) |> Map.fetch!(:account_ids)
  end

  @doc """
  The learned warm floor, hours with jobs, cold jobs and accounts of every pool with a job in
  the last day, keyed by fleet name.
  """
  def all do
    if Environment.test?() do
      compute()
    else
      # The key names the value's shape: replicas of the previous release
      # share the store during a rollout and cache bare floors.
      KeyValueStore.get_or_update([:runners, :learned_warm_floors, :v3], [ttl: @cache_ttl], &compute/0)
    end
  end

  defp compute do
    query = """
    WITH jobs AS (
      SELECT
        argMax(fleet_name, updated_at) AS fleet,
        argMax(account_id, updated_at) AS account,
        argMax(enqueued_at, updated_at) AS enqueued,
        argMax(conclusion, updated_at) AS final_conclusion
      FROM runner_jobs
      WHERE enqueued_at >= now() - toIntervalDay({history_days:UInt32})
      GROUP BY workflow_job_id
      HAVING final_conclusion != 'skipped'
    ),
    bursts AS (
      SELECT
        fleet,
        account,
        enqueued,
        count() OVER (
          PARTITION BY fleet
          ORDER BY toUnixTimestamp(enqueued)
          RANGE BETWEEN {burst_window_seconds:UInt32} PRECEDING AND CURRENT ROW
        ) AS burst
      FROM jobs
    )
    SELECT
      fleet,
      toInt32(quantileExact({burst_quantile:Float64})(burst)),
      toInt32(uniqExact(toStartOfHour(enqueued))),
      groupUniqArray(account),
      toInt32(countIf(burst > 1))
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
        Map.new(rows, fn [fleet, floor, hours, account_ids, cold_jobs] ->
          {fleet, %{floor: floor, hours_with_jobs: hours, account_ids: account_ids, cold_jobs: cold_jobs}}
        end)

      {:error, reason} ->
        Logger.warning("runners: failed to compute learned warm floors", reason: inspect(reason))
        %{}
    end
  end
end
