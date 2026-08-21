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
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claim
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.RunnerSessions

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

  Reconstructed from `runner_sessions`, one row per Pod the account
  held. Each session becomes a positive resource event when its claim
  is taken and a negative one when the claim is released; running
  totals over that sweep are the concurrent usage, and bucketing
  happens afterwards so even a short-lived peak stays visible.

  The session is what holds the slot, which is why the reconstruction
  reads it rather than the job. GitHub hands a queued job to any
  label-eligible runner, so the Pod that claimed job A frequently
  executes job B; charting `A.claimed_at → A.completed_at` measures a
  window the account was not reserving, and overstates the peak past a
  limit that admission makes it impossible to exceed. It also keeps the
  chart on the Postgres records admission itself reads, rather than on
  a ClickHouse replica that can diverge from them.
  """
  def usage_over_time(account_id, %DateTime{} = start_dt, %DateTime{} = end_dt, bucket)
      when is_integer(account_id) and bucket in [:hour, :day] do
    dates = bucket_range(start_dt, end_dt, bucket)

    usage =
      account_id
      |> claim_intervals(start_dt, end_dt)
      |> cumulative_usage(start_dt, end_dt)

    %{
      dates: dates,
      linux: peak_usage(Map.get(usage, :linux, []), dates, bucket),
      macos: peak_usage(Map.get(usage, :macos, []), dates, bucket)
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

  # One row per runner session that held a slot inside the window, with
  # the moment its claim was released already resolved in SQL.
  #
  # A claim is released by whichever event frees the Pod first: the
  # completed webhook of the job the runner actually executed, or the
  # Pod stopping. `job_ended_at` records the first directly and is the
  # sharpest signal; `runner_job_completions` is the same evidence
  # `Claims.release_completed/1` releases on, and covers sessions that
  # predate the column. `ended_at` bounds both, since a stopped Pod
  # cannot still be holding the slot, and `started_at` floors the
  # result so no session can produce a backwards interval.
  #
  # Anything still open falls back to the session ceiling, so a session
  # whose close was never reported cannot accrue capacity for the rest
  # of the window.
  #
  # That ceiling also bounds the scan: a session released after
  # `start_dt` cannot have started more than one ceiling before it, so
  # the window fixes both ends of the index range. Without the lower
  # bound the scan reads every session the account has ever had and
  # discards most of them, which grows with history rather than with
  # the window being charted.
  #
  # The completions join carries only sessions predating `job_ended_at`
  # and retires with them; gating it on that column being NULL keeps the
  # probe set to the shrinking population that needs it.
  defp claim_intervals(account_id, start_dt, end_dt) do
    scan_floor = DateTime.add(start_dt, -RunnerSessions.max_session_lifetime_seconds(), :second)

    released =
      from(session in RunnerSession,
        left_join: completion in JobCompletion,
        on:
          is_nil(session.job_ended_at) and
            completion.workflow_job_id ==
              coalesce(session.executed_workflow_job_id, session.workflow_job_id),
        where:
          session.account_id == ^account_id and session.started_at <= ^end_dt and
            session.started_at > ^scan_floor,
        select: %{
          platform: session.platform,
          fleet_name: session.fleet_name,
          vcpus: session.vcpus,
          memory_gb: session.memory_gb,
          started_at: session.started_at,
          released_at:
            fragment(
              "GREATEST(?, LEAST(COALESCE(?, ?, ?, ?), COALESCE(?, ?), ? + make_interval(secs => ?)))",
              session.started_at,
              session.job_ended_at,
              completion.completed_at,
              session.ended_at,
              ^end_dt,
              session.ended_at,
              ^end_dt,
              session.started_at,
              ^RunnerSessions.max_session_lifetime_seconds()
            )
        }
      )

    Repo.all(from(interval in subquery(released), where: interval.released_at > ^start_dt))
  end

  # Running resource totals per platform, one entry per distinct event
  # time. Sessions whose shape resolves to neither platform are dropped
  # rather than bucketed under a guess.
  defp cumulative_usage(intervals, start_dt, end_dt) do
    intervals
    |> Enum.flat_map(&interval_events(&1, start_dt, end_dt))
    |> Enum.group_by(fn {platform, _event_time, _vcpus, _memory_gb} -> platform end)
    |> Map.new(fn {platform, events} -> {platform, running_totals(events)} end)
  end

  defp interval_events(interval, start_dt, end_dt) do
    case session_shape(interval) do
      {:ok, resources} ->
        active_from = later_of(interval.started_at, start_dt)
        active_until = earlier_of(interval.released_at, end_dt)

        [
          {resources.platform, active_from, resources.vcpus, resources.memory_gb},
          {resources.platform, active_until, -resources.vcpus, -resources.memory_gb}
        ]

      {:error, _reason} ->
        []
    end
  end

  # Same resolution order admission uses in `Claims`: the shape frozen on
  # the row when it has one, the fleet's configured shape otherwise, so a
  # session predating the resource columns is charted at what it reserved.
  defp session_shape(%{platform: platform, vcpus: vcpus, memory_gb: memory_gb})
       when platform in @platforms and is_integer(vcpus) and is_integer(memory_gb) and vcpus > 0 and memory_gb > 0 do
    {:ok, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb}}
  end

  defp session_shape(%{fleet_name: fleet_name}) when is_binary(fleet_name) do
    Catalog.resources_for_fleet(fleet_name)
  end

  defp session_shape(_interval), do: {:error, :invalid_resources}

  defp running_totals(events) do
    {totals, _running} =
      events
      |> Enum.group_by(
        fn {_platform, event_time, _vcpus, _memory_gb} -> event_time end,
        fn {_platform, _event_time, vcpus, memory_gb} -> {vcpus, memory_gb} end
      )
      |> Enum.sort_by(fn {event_time, _deltas} -> DateTime.to_unix(event_time, :microsecond) end)
      |> Enum.map_reduce(%{vcpus: 0, memory_gb: 0}, fn {event_time, deltas}, running ->
        running =
          Enum.reduce(deltas, running, fn {vcpus, memory_gb}, acc ->
            %{vcpus: acc.vcpus + vcpus, memory_gb: acc.memory_gb + memory_gb}
          end)

        {Map.put(running, :event_time, event_time), running}
      end)

    totals
  end

  defp later_of(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.after?(left, right), do: left, else: right
  end

  defp earlier_of(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.before?(left, right), do: left, else: right
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
