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

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claim
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.Job

  @platforms [:linux, :macos]
  @default_limits %{
    linux: %{vcpus: 32, memory_gb: 64},
    macos: %{vcpus: 12, memory_gb: 28}
  }
  @limit_form_fields [
    :runner_linux_vcpus_limit,
    :runner_linux_memory_gb_limit,
    :runner_macos_vcpus_limit,
    :runner_macos_memory_gb_limit
  ]
  @limit_form_types Map.new(@limit_form_fields, &{&1, :integer})

  @doc """
  Returns platform summaries with current claimed resources and limits.
  """
  def summaries(%Account{} = account) do
    usage = usage_by_platform(account.id)
    limits = limits_by_platform(account.id)

    Enum.map(@platforms, fn platform ->
      platform_usage = Map.fetch!(usage, platform)
      platform_limits = limits |> Map.fetch!(platform) |> limit_resources()

      %{
        platform: platform,
        used_vcpus: platform_usage.vcpus,
        used_memory_gb: platform_usage.memory_gb,
        limit_vcpus: platform_limits.vcpus,
        limit_memory_gb: platform_limits.memory_gb
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

  @doc """
  How many more jobs of shape `resources` the account could claim right
  now before hitting its platform concurrency limit.

  This is the *forward-looking* companion to `fits?/3`: `fits?/3` answers
  "does one more fit" at claim time, this answers "how many more fit" for
  callers that must size ahead of the claim. Both read the same usage and
  limit, so a job counted here is a job `fits?/3` would admit.

  The autoscaler is the caller that matters. Sizing a pool on raw queue
  depth provisions Pods for jobs dispatch will refuse, and those Pods
  then sit idle holding hosts that pools with claimable work cannot get.
  Capping each account's contribution at its headroom keeps the demand
  signal to what can actually be served.

  Returns 0 for an unknown account, a missing limit row, or a malformed
  shape: this runs on the autoscaler's poll path, where raising would
  fail the whole fleet's signal over one bad account.
  """
  def headroom_jobs(account_id, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb})
      when is_integer(account_id) and platform in @platforms and is_integer(vcpus) and is_integer(memory_gb) and vcpus > 0 and
             memory_gb > 0 do
    case limit_for_platform(account_id, platform) do
      {:ok, limit} ->
        used = Map.get(usage_by_platform(account_id), platform, %{vcpus: 0, memory_gb: 0})

        [div(limit.vcpus - used.vcpus, vcpus), div(limit.memory_gb - used.memory_gb, memory_gb)]
        |> Enum.min()
        |> max(0)

      :error ->
        0
    end
  end

  def headroom_jobs(_account_id, _resources), do: 0

  defp limit_for_platform(account_id, platform) do
    case Repo.get_by(ConcurrencyLimit, account_id: account_id, platform: platform) do
      nil -> :error
      limit -> {:ok, limit_resources(limit)}
    end
  end

  defp valid_usage?(resources) do
    Enum.all?([resources.vcpus, resources.memory_gb], &(is_integer(&1) and &1 >= 0))
  end

  defp valid_capacity?(resources) do
    Enum.all?([resources.vcpus, resources.memory_gb], &(is_integer(&1) and &1 > 0))
  end

  @doc """
  Creates the default Linux and macOS limits for a new account.
  """
  def create_default_limits(%Account{id: account_id}) do
    Enum.reduce_while(@platforms, {:ok, []}, fn platform, {:ok, limits} ->
      attrs =
        @default_limits
        |> Map.fetch!(platform)
        |> Map.merge(%{account_id: account_id, platform: platform})

      case %ConcurrencyLimit{}
           |> ConcurrencyLimit.changeset(attrs)
           |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :platform]) do
        {:ok, limit} -> {:cont, {:ok, [limit | limits]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  @doc """
  Builds a changeset for the ops concurrency-limits form.
  """
  def change_limits(%Account{} = account, attrs \\ %{}) do
    limits = limits_by_platform(account.id)
    linux = limits |> Map.fetch!(:linux) |> limit_resources()
    macos = limits |> Map.fetch!(:macos) |> limit_resources()

    data = %{
      runner_linux_vcpus_limit: linux.vcpus,
      runner_linux_memory_gb_limit: linux.memory_gb,
      runner_macos_vcpus_limit: macos.vcpus,
      runner_macos_memory_gb_limit: macos.memory_gb
    }

    {data, @limit_form_types}
    |> Changeset.cast(attrs, @limit_form_fields)
    |> Changeset.validate_required(@limit_form_fields)
    |> Changeset.validate_number(:runner_linux_vcpus_limit, greater_than: 0)
    |> Changeset.validate_number(:runner_linux_memory_gb_limit, greater_than: 0)
    |> Changeset.validate_number(:runner_macos_vcpus_limit, greater_than: 0)
    |> Changeset.validate_number(:runner_macos_memory_gb_limit, greater_than: 0)
  end

  @doc """
  Persists custom concurrency limits for an account.
  """
  def update_limits(%Account{} = account, attrs) when is_map(attrs) do
    changeset = change_limits(account, attrs)

    case Changeset.apply_action(changeset, :update) do
      {:ok, values} ->
        Repo.transaction(fn ->
          limits =
            ConcurrencyLimit
            |> where([limit], limit.account_id == ^account.id)
            |> order_by([limit], limit.platform)
            |> lock("FOR UPDATE")
            |> Repo.all()

          if length(limits) != length(@platforms) do
            Repo.rollback(:runner_concurrency_limits_missing)
          end

          Enum.each(limits, fn limit ->
            attrs = form_values_for_platform(values, limit.platform)

            limit
            |> ConcurrencyLimit.changeset(attrs)
            |> Repo.update!()
          end)

          account
        end)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp form_values_for_platform(values, :linux) do
    %{
      vcpus: values.runner_linux_vcpus_limit,
      memory_gb: values.runner_linux_memory_gb_limit
    }
  end

  defp form_values_for_platform(values, :macos) do
    %{
      vcpus: values.runner_macos_vcpus_limit,
      memory_gb: values.runner_macos_memory_gb_limit
    }
  end

  defp usage_events(account_id, start_dt, end_dt) do
    linux_default = Catalog.default_shape(:linux) || %{vcpus: 1, memory_gb: 1}
    macos_default = Catalog.default_shape(:macos) || %{vcpus: 1, memory_gb: 1}
    [linux_legacy_prefix, linux_pool_prefix] = Catalog.fleet_name_prefixes(:linux)
    [macos_legacy_prefix, macos_pool_prefix] = Catalog.fleet_name_prefixes(:macos)

    latest_rows = latest_rows_query(account_id, end_dt)
    latest_jobs = latest_jobs_query(latest_rows, start_dt, end_dt)
    linux_fleet_resources = Catalog.linux_fleet_resources()

    normalized_platforms =
      normalized_platforms_query(latest_jobs, %{
        linux_legacy: linux_legacy_prefix,
        linux_pool: linux_pool_prefix,
        macos_legacy: macos_legacy_prefix,
        macos_pool: macos_pool_prefix
      })

    intervals =
      active_intervals_query(
        normalized_platforms,
        start_dt,
        end_dt,
        linux_default,
        macos_default,
        linux_fleet_resources
      )

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
        fleet_name: job.fleet_name,
        claimed_at: job.claimed_at,
        completed_at: job.completed_at
      }
    )
  end

  defp active_intervals_query(normalized_platforms, start_dt, end_dt, linux_default, macos_default, linux_fleet_resources) do
    linux_fleet_names = Enum.map(linux_fleet_resources, & &1.fleet_name)
    linux_fleet_vcpus = Enum.map(linux_fleet_resources, & &1.vcpus)
    linux_fleet_memory_gb = Enum.map(linux_fleet_resources, & &1.memory_gb)

    from(job in subquery(normalized_platforms),
      where: job.platform != "",
      select: %{
        platform: job.platform,
        active_from: fragment("greatest(?, ?)", job.claimed_at, ^start_dt),
        active_until: fragment("least(ifNull(?, ?), ?)", job.completed_at, ^end_dt, ^end_dt),
        vcpus:
          fragment(
            """
            multiIf(
              ? > 0, toInt64(?),
              ? = 'linux', toInt64(transform(?, ?, ?, ?)),
              toInt64(?)
            )
            """,
            job.stored_vcpus,
            job.stored_vcpus,
            job.platform,
            job.fleet_name,
            ^linux_fleet_names,
            ^linux_fleet_vcpus,
            ^linux_default.vcpus,
            ^macos_default.vcpus
          ),
        memory_gb:
          fragment(
            """
            multiIf(
              ? > 0, toInt64(?),
              ? = 'linux', toInt64(transform(?, ?, ?, ?)),
              toInt64(?)
            )
            """,
            job.stored_memory_gb,
            job.stored_memory_gb,
            job.platform,
            job.fleet_name,
            ^linux_fleet_names,
            ^linux_fleet_memory_gb,
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
  def limits_for(%Account{id: account_id}, platform), do: limits_for(account_id, platform)

  def limits_for(account_id, platform) when is_integer(account_id) and platform in @platforms do
    ConcurrencyLimit
    |> Repo.get_by!(account_id: account_id, platform: platform)
    |> limit_resources()
  end

  def limit_resources(%ConcurrencyLimit{} = limit) do
    %{vcpus: limit.vcpus, memory_gb: limit.memory_gb}
  end

  defp limits_by_platform(account_id) do
    ConcurrencyLimit
    |> where([limit], limit.account_id == ^account_id)
    |> Repo.all()
    |> Map.new(&{&1.platform, &1})
  end

  defp zero_usage do
    %{
      linux: %{vcpus: 0, memory_gb: 0},
      macos: %{vcpus: 0, memory_gb: 0}
    }
  end
end
