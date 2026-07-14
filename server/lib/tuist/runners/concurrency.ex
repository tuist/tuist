defmodule Tuist.Runners.Concurrency do
  @moduledoc """
  Platform-specific vCPU and memory concurrency limits for Tuist
  Runners.

  Linux and macOS have independent budgets. A claim is admitted only
  when adding its shape keeps both aggregate vCPU and aggregate memory
  within the account's limits for that platform. `Claims.attempt/5`
  invokes `check_available/2` while holding the account advisory lock,
  making the read-check-insert sequence atomic across server replicas.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claim

  @platforms [:linux, :macos]

  @doc """
  Returns platform summaries with current claimed resources and limits.
  """
  def summaries(%Account{} = account) do
    usage = usage_by_platform(account.id)

    Enum.map(@platforms, fn platform ->
      platform_usage = Map.fetch!(usage, platform)
      limits = limits_for(account, platform)

      %{
        platform: platform,
        used_vcpus: platform_usage.vcpus,
        used_memory_gb: platform_usage.memory_gb,
        limit_vcpus: limits.vcpus,
        limit_memory_gb: limits.memory_gb
      }
    end)
  end

  @doc """
  Returns aggregate active-claim resources for each platform.
  """
  def usage_by_platform(account_id) when is_integer(account_id) do
    usage =
      Claim
      |> where([claim], claim.account_id == ^account_id)
      |> group_by([claim], claim.platform)
      |> select([claim], {
        claim.platform,
        %{vcpus: sum(claim.vcpus), memory_gb: sum(claim.memory_gb)}
      })
      |> Repo.all()
      |> Map.new()

    Map.merge(zero_usage(), usage)
  end

  @doc """
  Returns the peak concurrent vCPU and memory usage per time bucket.

  The ClickHouse query turns every claimed job into a positive event
  and every completion into a negative event, then computes the exact
  running resource totals. Bucketing happens after that event sweep so
  even a short-lived peak remains visible in the chart.
  """
  def usage_over_time(account_id, %DateTime{} = start_dt, %DateTime{} = end_dt, bucket)
      when is_integer(account_id) and bucket in [:hour, :day] do
    dates = bucket_range(start_dt, end_dt, bucket)

    events =
      account_id
      |> usage_events(start_dt, end_dt)
      |> Enum.group_by(& &1.platform)

    %{
      dates: dates,
      linux: peak_usage(Map.get(events, :linux, []), dates, bucket),
      macos: peak_usage(Map.get(events, :macos, []), dates, bucket)
    }
  end

  @doc """
  Checks whether `requested` fits the account's remaining capacity.

  This function must run inside the transaction and after the account
  advisory lock acquired by `Claims.attempt/5`.
  """
  def check_available(account_id, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb} = requested) do
    with :ok <- validate_account_id(account_id),
         :ok <- validate_platform(platform),
         :ok <- validate_positive_integer(vcpus),
         :ok <- validate_positive_integer(memory_gb) do
      check_account_capacity(account_id, requested)
    end
  end

  def check_available(_account_id, _requested), do: {:error, :invalid_resources}

  defp check_account_capacity(account_id, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb} = requested) do
    case Repo.get(Account, account_id) do
      nil ->
        {:error, :unknown_account}

      account ->
        used = account_id |> usage_by_platform() |> Map.fetch!(platform)
        limit = limits_for(account, platform)

        if used.vcpus + vcpus <= limit.vcpus and used.memory_gb + memory_gb <= limit.memory_gb do
          :ok
        else
          {:error,
           {:concurrency_limit_reached,
            %{
              platform: platform,
              requested: requested,
              used: used,
              limit: limit
            }}}
        end
    end
  end

  @doc """
  Builds a changeset for the ops concurrency-limits form.
  """
  def change_limits(%Account{} = account, attrs \\ %{}) do
    Account.runner_concurrency_limits_changeset(account, attrs)
  end

  @doc """
  Persists custom concurrency limits for an account.
  """
  def update_limits(%Account{} = account, attrs) when is_map(attrs) do
    account
    |> change_limits(attrs)
    |> Repo.update()
  end

  defp usage_events(account_id, start_dt, end_dt) do
    linux_default = Catalog.default_shape(:linux) || %{vcpus: 1, memory_gb: 1}
    macos_default = Catalog.default_shape(:macos) || %{vcpus: 1, memory_gb: 1}
    [linux_legacy_prefix, linux_pool_prefix] = Catalog.fleet_name_prefixes(:linux)
    [macos_legacy_prefix, macos_pool_prefix] = Catalog.fleet_name_prefixes(:macos)

    query = """
    WITH latest_rows AS (
      SELECT
        workflow_job_id,
        argMax(
          tuple(platform, fleet_name, vcpus, memory_gb, claimed_at, completed_at),
          updated_at
        ) AS latest_state
      FROM runner_jobs
      WHERE account_id = {account_id:Int64}
        AND enqueued_at <= {end_dt:DateTime64(6)}
      GROUP BY workflow_job_id
    ), latest_jobs AS (
      SELECT
        workflow_job_id,
        tupleElement(latest_state, 1) AS stored_platform,
        tupleElement(latest_state, 2) AS fleet_name,
        tupleElement(latest_state, 3) AS stored_vcpus,
        tupleElement(latest_state, 4) AS stored_memory_gb,
        tupleElement(latest_state, 5) AS claimed_at,
        tupleElement(latest_state, 6) AS completed_at
      FROM latest_rows
      WHERE claimed_at IS NOT NULL
        AND claimed_at <= {end_dt:DateTime64(6)}
        AND (completed_at IS NULL OR completed_at > {start_dt:DateTime64(6)})
    ), normalized_platforms AS (
      SELECT
        multiIf(
          stored_platform = 'linux', 'linux',
          stored_platform = 'macos', 'macos',
          startsWith(fleet_name, {linux_legacy_prefix:String}), 'linux',
          startsWith(fleet_name, {linux_pool_prefix:String}), 'linux',
          startsWith(fleet_name, {macos_legacy_prefix:String}), 'macos',
          startsWith(fleet_name, {macos_pool_prefix:String}), 'macos',
          ''
        ) AS platform,
        fleet_name,
        stored_vcpus,
        stored_memory_gb,
        claimed_at,
        completed_at
      FROM latest_jobs
    ), intervals AS (
      SELECT
        platform,
        greatest(claimed_at, {start_dt:DateTime64(6)}) AS active_from,
        least(ifNull(completed_at, {end_dt:DateTime64(6)}), {end_dt:DateTime64(6)}) AS active_until,
        if(
          stored_vcpus > 0,
          toInt64(stored_vcpus),
          if(platform = 'linux', {linux_vcpus:Int64}, {macos_vcpus:Int64})
        ) AS vcpus,
        if(
          stored_memory_gb > 0,
          toInt64(stored_memory_gb),
          if(platform = 'linux', {linux_memory_gb:Int64}, {macos_memory_gb:Int64})
        ) AS memory_gb
      FROM normalized_platforms
      WHERE platform != ''
    ), events AS (
      SELECT
        platform,
        tupleElement(event, 1) AS event_time,
        sum(tupleElement(event, 2)) AS vcpus_delta,
        sum(tupleElement(event, 3)) AS memory_gb_delta
      FROM intervals
      ARRAY JOIN [
        tuple(active_from, vcpus, memory_gb),
        tuple(active_until, -vcpus, -memory_gb)
      ] AS event
      GROUP BY platform, event_time
    )
    SELECT
      platform,
      event_time,
      toInt64(sum(vcpus_delta) OVER (
        PARTITION BY platform
        ORDER BY event_time
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )) AS vcpus,
      toInt64(sum(memory_gb_delta) OVER (
        PARTITION BY platform
        ORDER BY event_time
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )) AS memory_gb
    FROM events
    ORDER BY platform, event_time
    """

    params = %{
      account_id: account_id,
      start_dt: start_dt,
      end_dt: end_dt,
      linux_legacy_prefix: linux_legacy_prefix,
      linux_pool_prefix: linux_pool_prefix,
      macos_legacy_prefix: macos_legacy_prefix,
      macos_pool_prefix: macos_pool_prefix,
      linux_vcpus: linux_default.vcpus,
      linux_memory_gb: linux_default.memory_gb,
      macos_vcpus: macos_default.vcpus,
      macos_memory_gb: macos_default.memory_gb
    }

    {:ok, %{rows: rows}} = ClickHouseRepo.query(query, params)

    Enum.map(rows, fn [platform, event_time, vcpus, memory_gb] ->
      %{
        platform: String.to_existing_atom(platform),
        event_time: to_datetime(event_time),
        vcpus: vcpus,
        memory_gb: memory_gb
      }
    end)
  end

  defp peak_usage(events, dates, bucket) do
    events_by_bucket = Enum.group_by(events, &bucket_key(&1.event_time, bucket))

    {values, _current} =
      Enum.map_reduce(dates, %{vcpus: 0, memory_gb: 0}, fn date, current ->
        bucket_events = Map.get(events_by_bucket, date, [])

        starting_usage =
          case bucket_events do
            [%{event_time: event_time} = first | _] ->
              if DateTime.compare(event_time, bucket_start(date, bucket)) == :eq,
                do: resource_usage(first),
                else: current

            [] ->
              current
          end

        peak =
          Enum.reduce(bucket_events, starting_usage, fn event, peak ->
            usage = resource_usage(event)

            %{
              vcpus: max(peak.vcpus, usage.vcpus),
              memory_gb: max(peak.memory_gb, usage.memory_gb)
            }
          end)

        next_current =
          case List.last(bucket_events) do
            nil -> starting_usage
            event -> resource_usage(event)
          end

        {peak, next_current}
      end)

    %{
      vcpus: Enum.map(values, & &1.vcpus),
      memory_gb: Enum.map(values, & &1.memory_gb)
    }
  end

  defp resource_usage(event), do: Map.take(event, [:vcpus, :memory_gb])

  defp bucket_key(%DateTime{} = datetime, :hour), do: floor_to_hour(datetime)
  defp bucket_key(%DateTime{} = datetime, :day), do: DateTime.to_date(datetime)

  defp bucket_start(%DateTime{} = datetime, :hour), do: datetime
  defp bucket_start(%Date{} = date, :day), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp bucket_range(%DateTime{} = start_dt, %DateTime{} = end_dt, :day) do
    start_dt |> DateTime.to_date() |> Date.range(DateTime.to_date(end_dt)) |> Enum.to_list()
  end

  defp bucket_range(%DateTime{} = start_dt, %DateTime{} = end_dt, :hour) do
    floor_start = floor_to_hour(start_dt)
    floor_end = floor_to_hour(end_dt)

    floor_start
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, floor_end) != :gt))
  end

  defp floor_to_hour(%DateTime{} = datetime) do
    %{datetime | minute: 0, second: 0, microsecond: {0, 0}}
  end

  defp to_datetime(%DateTime{} = datetime), do: datetime
  defp to_datetime(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")

  defp limits_for(account, :linux) do
    %{
      vcpus: account.runner_linux_vcpus_limit,
      memory_gb: account.runner_linux_memory_gb_limit
    }
  end

  defp limits_for(account, :macos) do
    %{
      vcpus: account.runner_macos_vcpus_limit,
      memory_gb: account.runner_macos_memory_gb_limit
    }
  end

  defp validate_account_id(account_id) when is_integer(account_id), do: :ok
  defp validate_account_id(_account_id), do: {:error, :invalid_resources}

  defp validate_platform(platform) when platform in @platforms, do: :ok
  defp validate_platform(_platform), do: {:error, :invalid_resources}

  defp validate_positive_integer(value) when is_integer(value) and value > 0, do: :ok
  defp validate_positive_integer(_value), do: {:error, :invalid_resources}

  defp zero_usage do
    %{
      linux: %{vcpus: 0, memory_gb: 0},
      macos: %{vcpus: 0, memory_gb: 0}
    }
  end
end
