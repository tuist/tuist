defmodule Tuist.Runners.Concurrency do
  @moduledoc """
  Platform-specific vCPU and memory concurrency limits for Tuist
  Runners.

  Linux and macOS have independent budgets. A claim is admitted only
  when adding its shape keeps both aggregate vCPU and aggregate memory
  within the account's limits for that platform. `Claims.attempt/5`
  owns the database-backed read-check-insert transaction; this module
  provides the pure capacity predicate and reporting queries.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Job

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
  Purely checks whether `requested` fits within `limit` after `used`.
  """
  def fits?(
        %{vcpus: used_vcpus, memory_gb: used_memory_gb} = used,
        %{vcpus: limit_vcpus, memory_gb: limit_memory_gb} = limit,
        %{vcpus: requested_vcpus, memory_gb: requested_memory_gb} = requested
      ) do
    valid_usage?(used) and valid_capacity?(limit) and valid_capacity?(requested) and
      used_vcpus + requested_vcpus <= limit_vcpus and
      used_memory_gb + requested_memory_gb <= limit_memory_gb
  end

  def fits?(_used, _limit, _requested), do: false

  defp valid_usage?(resources) do
    Enum.all?([resources.vcpus, resources.memory_gb], &(is_integer(&1) and &1 >= 0))
  end

  defp valid_capacity?(resources) do
    Enum.all?([resources.vcpus, resources.memory_gb], &(is_integer(&1) and &1 > 0))
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

    latest_rows = latest_rows_query(account_id, end_dt)
    latest_jobs = latest_jobs_query(latest_rows, start_dt, end_dt)

    normalized_platforms =
      normalized_platforms_query(latest_jobs, %{
        linux_legacy: linux_legacy_prefix,
        linux_pool: linux_pool_prefix,
        macos_legacy: macos_legacy_prefix,
        macos_pool: macos_pool_prefix
      })

    intervals = active_intervals_query(normalized_platforms, start_dt, end_dt, linux_default, macos_default)

    intervals
    |> resource_events_query()
    |> cumulative_usage_query()
    |> ClickHouseRepo.all()
    |> Enum.map(fn event ->
      %{
        event
        | platform: String.to_existing_atom(event.platform),
          event_time: to_datetime(event.event_time)
      }
    end)
  end

  defp latest_rows_query(account_id, end_dt) do
    from(job in Job,
      where: job.account_id == ^account_id and job.enqueued_at <= ^end_dt,
      group_by: job.workflow_job_id,
      select: %{
        latest_state:
          fragment(
            "argMax(tuple(?, ?, ?, ?, ?, ?), ?)",
            job.platform,
            job.fleet_name,
            job.vcpus,
            job.memory_gb,
            job.claimed_at,
            job.completed_at,
            job.updated_at
          )
      }
    )
  end

  defp latest_jobs_query(latest_rows, start_dt, end_dt) do
    from(row in subquery(latest_rows),
      where:
        not is_nil(fragment("tupleElement(?, 5)", row.latest_state)) and
          fragment("tupleElement(?, 5) <= ?", row.latest_state, ^end_dt) and
          (is_nil(fragment("tupleElement(?, 6)", row.latest_state)) or
             fragment("tupleElement(?, 6) > ?", row.latest_state, ^start_dt)),
      select: %{
        stored_platform: fragment("tupleElement(?, 1)", row.latest_state),
        fleet_name: fragment("tupleElement(?, 2)", row.latest_state),
        stored_vcpus: fragment("tupleElement(?, 3)", row.latest_state),
        stored_memory_gb: fragment("tupleElement(?, 4)", row.latest_state),
        claimed_at: fragment("tupleElement(?, 5)", row.latest_state),
        completed_at: fragment("tupleElement(?, 6)", row.latest_state)
      }
    )
  end

  defp normalized_platforms_query(latest_jobs, prefixes) do
    from(job in subquery(latest_jobs),
      select: %{
        platform:
          fragment(
            """
            multiIf(
              ? = 'linux', 'linux',
              ? = 'macos', 'macos',
              startsWith(?, ?), 'linux',
              startsWith(?, ?), 'linux',
              startsWith(?, ?), 'macos',
              startsWith(?, ?), 'macos',
              ''
            )
            """,
            job.stored_platform,
            job.stored_platform,
            job.fleet_name,
            ^prefixes.linux_legacy,
            job.fleet_name,
            ^prefixes.linux_pool,
            job.fleet_name,
            ^prefixes.macos_legacy,
            job.fleet_name,
            ^prefixes.macos_pool
          ),
        stored_vcpus: job.stored_vcpus,
        stored_memory_gb: job.stored_memory_gb,
        claimed_at: job.claimed_at,
        completed_at: job.completed_at
      }
    )
  end

  defp active_intervals_query(normalized_platforms, start_dt, end_dt, linux_default, macos_default) do
    from(job in subquery(normalized_platforms),
      where: job.platform != "",
      select: %{
        platform: job.platform,
        active_from: fragment("greatest(?, ?)", job.claimed_at, ^start_dt),
        active_until: fragment("least(ifNull(?, ?), ?)", job.completed_at, ^end_dt, ^end_dt),
        vcpus:
          fragment(
            "if(? > 0, toInt64(?), if(? = 'linux', ?, ?))",
            job.stored_vcpus,
            job.stored_vcpus,
            job.platform,
            ^linux_default.vcpus,
            ^macos_default.vcpus
          ),
        memory_gb:
          fragment(
            "if(? > 0, toInt64(?), if(? = 'linux', ?, ?))",
            job.stored_memory_gb,
            job.stored_memory_gb,
            job.platform,
            ^linux_default.memory_gb,
            ^macos_default.memory_gb
          )
      }
    )
  end

  defp resource_events_query(intervals) do
    expanded_events =
      from(interval in subquery(intervals),
        select: %{
          platform: interval.platform,
          event:
            fragment(
              "arrayJoin([tuple(?, ?, ?), tuple(?, -?, -?)])",
              interval.active_from,
              interval.vcpus,
              interval.memory_gb,
              interval.active_until,
              interval.vcpus,
              interval.memory_gb
            )
        }
      )

    from(event in subquery(expanded_events),
      group_by: [event.platform, fragment("tupleElement(?, 1)", event.event)],
      select: %{
        platform: event.platform,
        event_time: fragment("tupleElement(?, 1)", event.event),
        vcpus_delta: sum(fragment("tupleElement(?, 2)", event.event)),
        memory_gb_delta: sum(fragment("tupleElement(?, 3)", event.event))
      }
    )
  end

  defp cumulative_usage_query(events) do
    from(event in subquery(events),
      windows: [
        running: [
          partition_by: event.platform,
          order_by: event.event_time,
          frame: fragment("ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW")
        ]
      ],
      order_by: [event.platform, event.event_time],
      select: %{
        platform: event.platform,
        event_time: event.event_time,
        vcpus: fragment("toInt64(?)", over(sum(event.vcpus_delta), :running)),
        memory_gb: fragment("toInt64(?)", over(sum(event.memory_gb_delta), :running))
      }
    )
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

  @doc """
  Returns the configured resource limits for `platform`.
  """
  def limits_for(%Account{} = account, :linux) do
    %{
      vcpus: account.runner_linux_vcpus_limit,
      memory_gb: account.runner_linux_memory_gb_limit
    }
  end

  def limits_for(%Account{} = account, :macos) do
    %{
      vcpus: account.runner_macos_vcpus_limit,
      memory_gb: account.runner_macos_memory_gb_limit
    }
  end

  defp zero_usage do
    %{
      linux: %{vcpus: 0, memory_gb: 0},
      macos: %{vcpus: 0, memory_gb: 0}
    }
  end
end
