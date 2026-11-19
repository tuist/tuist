defmodule Tuist.Runners.MacosSandboxWarmPools do
  @moduledoc """
  Scaling signals for the pools of pre-booted macOS sandbox VMs.

  A warm pool runs no CI job, so the runner signals of its fleet are always
  zero, and the controller ranked it below every CI pool with a learned warm
  floor when a rack was short of seats: an idle CI runner kept its slot and
  the next sandbox create cold-booted. Its usage is the macOS sandbox creates
  of its shape instead, which this module reports in the same fields as a CI
  pool's jobs:

    * `hours_with_jobs` counts the hours of the last 14 days with a create
      of the shape, or 0 when there was none in the last day, so the floors
      of idle pools are funded by use.
    * `cold_jobs` counts the creates of the shape in those 14 days, or 0
      when there was none in the last day: each one boots cold without a
      warm VM, which is what the controller ranks warm floors by.
    * `p95_concurrent_last_hour` is 1 after a create of the shape in the last
      hour, which marks the pool in use, so its floor is funded with those
      of the CI pools running jobs. It holds no VM past the pool's
      `maxReplicas`, and like any floor it yields to queued CI jobs.

  Every create counts, including one refused for capacity: it asked for a VM.

  One query covers every shape. Each replica caches it for a minute.
  """
  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Sandboxes.Sandbox

  @history_days 14
  @active_within_hours 24
  @in_use_within_minutes 60
  @cache_ttl to_timeout(minute: 1)

  # CONTRACT: the pool names and shapes `infra/helm/tuist/templates/macos-sandboxes.yaml`
  # renders. Its 8 GiB pool has no suffix, the others end in `-<GiB>gb`, and
  # every pool's VMs have 8 vCPUs.
  @pool_name ~r/runner-pool-macos-sandbox-warm(?:-(\d+)gb)?$/
  @vcpus 8

  @doc """
  The macOS sandbox shape `{vcpus, memory_mb}` a warm pool named `fleet_name`
  keeps booted, or `nil` for any other pool.
  """
  def shape(fleet_name) when is_binary(fleet_name) do
    case Regex.run(@pool_name, fleet_name) do
      [_match] -> {@vcpus, 8192}
      [_match, gb] -> {@vcpus, String.to_integer(gb) * 1024}
      nil -> nil
    end
  end

  @doc """
  The usage signals of the warm pool keeping `shape` booted.
  """
  def signals({_vcpus, _memory_mb} = shape) do
    case Map.get(usage(), shape) do
      nil ->
        %{hours_with_jobs: 0, cold_jobs: 0, p95_concurrent_last_hour: 0}

      %{hours: hours, creates: creates, last_created_at: last_created_at} ->
        now = DateTime.utc_now()
        active? = within?(last_created_at, now, @active_within_hours * 60)

        %{
          hours_with_jobs: if(active?, do: hours, else: 0),
          cold_jobs: if(active?, do: creates, else: 0),
          p95_concurrent_last_hour: if(within?(last_created_at, now, @in_use_within_minutes), do: 1, else: 0)
        }
    end
  end

  defp within?(at, now, minutes), do: DateTime.diff(now, at, :minute) < minutes

  defp usage do
    if Environment.test?() do
      compute()
    else
      KeyValueStore.get_or_update([:runners, :macos_sandbox_warm_usage], [ttl: @cache_ttl], &compute/0)
    end
  end

  defp compute do
    since = DateTime.add(DateTime.utc_now(), -@history_days, :day)

    from(s in Sandbox,
      where: s.platform == :darwin and s.inserted_at >= ^since,
      group_by: [s.vcpus, s.memory_mb],
      select: {
        {s.vcpus, s.memory_mb},
        %{
          hours: fragment("count(DISTINCT date_trunc('hour', ?))::integer", s.inserted_at),
          creates: fragment("count(*)::integer"),
          last_created_at: max(s.inserted_at)
        }
      }
    )
    |> Repo.all()
    |> Map.new()
  end
end
