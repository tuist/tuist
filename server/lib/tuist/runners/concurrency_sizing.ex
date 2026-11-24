defmodule Tuist.Runners.ConcurrencySizing do
  @moduledoc """
  Growth-only runner concurrency sizing for enabled Pro and Enterprise accounts.

  Recurring sizing uses the second-highest daily peak in fourteen completed UTC
  days, with 25% or one observed machine of headroom. The queue path only asks
  for room for one recent, valid job blocked by current claims. Neither path
  consumes the asynchronous ClickHouse replica or bypasses normal admission.

  An account/platform grows at most once per 24h, by at most 50%, and no more
  than doubles in a rolling week, counted from its latest plan or operator
  grant. Existing grants, including contractual
  minima, are never reduced, even when above the automatic safety ceilings.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.ConcurrencyHistory
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.WorkflowJob

  @ceilings %{linux: %{vcpus: 256, memory_gb: 1024}, macos: %{vcpus: 128, memory_gb: 384}}
  @quanta %{linux: %{vcpus: 4, memory_gb: 8}, macos: %{vcpus: 8, memory_gb: 24}}
  @hourly_budget 5

  @doc """
  Evaluates active accounts. A daily sweep and queue sweep share a persisted
  apply budget, so retries and overlapping replicas cannot multiply growth.
  """
  def sweep(mode, now \\ DateTime.utc_now()) when mode in [:daily, :queue] do
    ids = active_account_ids(mode, now)

    Account
    |> where([a], a.id in ^ids)
    |> order_by([a], a.id)
    |> Repo.all()
    |> Enum.each(fn account ->
      if eligible?(account) do
        for platform <- [:linux, :macos] do
          grow(account, platform, mode, now)
        end
      end
    end)

    :ok
  end

  @doc """
  Sizes one account/platform, returning `{:ok, :unchanged | resources}`.
  All eligibility, limits, recent changes and queue pressure are rechecked
  under the same platform lock used by admission and manual writes.
  """
  def grow(%Account{} = account, platform, mode, now \\ DateTime.utc_now())
      when platform in [:linux, :macos] and mode in [:daily, :queue] do
    # The analytical scan happens outside admission's lock. Its result is
    # demand evidence, not an old limit to overwrite a newer grant with.
    demand = if mode == :daily, do: recurring_demand(account.id, platform, now)

    result = Repo.transaction(fn -> grow_locked(account, platform, mode, demand, now) end)

    case result do
      {:ok, %{} = resources} ->
        Tuist.PubSub.broadcast(
          %{account_id: account.id},
          Concurrency.topic(account.id),
          :runner_concurrency_limits_changed
        )

        {:ok, resources}

      other ->
        other
    end
  end

  defp grow_locked(account, platform, mode, demand, now) do
    # Both cron modes and all replicas share this very short apply lock.
    %{rows: [[locked?]]} = Repo.query!("SELECT pg_try_advisory_xact_lock(hashtext('runner_concurrency_growth'))")

    if locked? and eligible?(Repo.get!(Account, account.id)) do
      limit =
        ConcurrencyLimit
        |> where([l], l.account_id == ^account.id and l.platform == ^platform)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      grow_limit(limit, mode, demand, now)
    else
      :unchanged
    end
  end

  defp grow_limit(limit, mode, demand, now) do
    # The sweep's clock predates this lock. Include changes committed
    # since it started, especially a manual edit we just waited behind.
    history = ConcurrencyHistory.between(limit.account_id, DateTime.add(now, -7, :day), DateTime.utc_now())
    platform_history = Enum.filter(history, &(&1.platform == limit.platform))
    target = if mode == :daily, do: demand, else: queued_demand(limit.account_id, limit.platform, limit, now)

    with %{} <- target,
         true <- may_grow?(platform_history, now),
         true <- budget_available?(now),
         resources = bounded_target(limit.platform, limit, target, since_latest_grant(platform_history)),
         true <- resources.vcpus > limit.vcpus or resources.memory_gb > limit.memory_gb do
      apply_growth(limit, resources, mode, now)
      resources
    else
      _ -> :unchanged
    end
  end

  defp eligible?(account) do
    Billing.effective_plan(account) in [:pro, :enterprise] and
      Environment.runners_available?() and
      Tuist.FeatureFlags.runner_concurrency_growth_enabled?(account)
  end

  defp active_account_ids(:queue, now) do
    WorkflowJob
    |> where([j], j.status == "queued" and j.enqueued_at >= ^DateTime.add(now, -3600, :second))
    |> distinct([j], j.account_id)
    |> select([j], j.account_id)
    |> Repo.all()
  end

  defp active_account_ids(:daily, now) do
    RunnerSession
    |> where([s], s.started_at >= ^DateTime.add(now, -15, :day))
    |> distinct([s], s.account_id)
    |> select([s], s.account_id)
    |> Repo.all()
  end

  defp queued_demand(account_id, platform, limit, now) do
    used = Map.fetch!(Concurrency.usage_by_platform(account_id), platform)
    platform_name = Atom.to_string(platform)

    WorkflowJob
    |> where([j], j.account_id == ^account_id and j.platform == ^platform_name and j.status == "queued")
    |> where(
      [j],
      j.enqueued_at >= ^DateTime.add(now, -3600, :second) and j.enqueued_at <= ^DateTime.add(now, -60, :second)
    )
    |> order_by([j], asc: j.enqueued_at, asc: j.workflow_job_id)
    |> Repo.all()
    |> Enum.find_value(fn job ->
      resources = %{vcpus: job.vcpus, memory_gb: job.memory_gb}

      if Catalog.find_shape(platform, job.vcpus, job.memory_gb) &&
           not Concurrency.fits?(used, Concurrency.limit_resources(limit), resources) do
        %{vcpus: used.vcpus + job.vcpus, memory_gb: used.memory_gb + job.memory_gb}
      end
    end)
  end

  defp may_grow?(history, now) do
    since = DateTime.add(now, -1, :day)
    # Manual changes get the same cooldown, so an operator's reduction cannot
    # be immediately undone. The pause flag provides a durable operator hold.
    not Enum.any?(history, &(&1.source in ["automatic", "manual"] and DateTime.after?(&1.recorded_at, since)))
  end

  defp budget_available?(now) do
    since = DateTime.add(now, -3600, :second)

    ConcurrencyHistory
    |> where([h], h.source == "automatic" and h.recorded_at > ^since)
    |> Repo.aggregate(:count)
    |> Kernel.<(@hourly_budget)
  end

  # Plan defaults and operator edits are grants, not growth: the weekly
  # doubling bound counts from the latest one, so automatic growth can always
  # double what was last granted. An upgrade records no `plan` row when an
  # operator had already raised the account above the plan's defaults, so
  # counting only plan rows would hold it at twice its pre-upgrade limit for a
  # week. History is oldest first.
  defp since_latest_grant(history) do
    case history |> Enum.reverse() |> Enum.find_index(&(&1.source in ["plan", "manual"])) do
      nil -> history
      index -> Enum.take(history, -(index + 1))
    end
  end

  defp bounded_target(platform, current, target, history) do
    Map.new([:vcpus, :memory_gb], fn resource ->
      existing = Map.fetch!(current, resource)
      quantum = get_in(@quanta, [platform, resource])
      week_floor = Enum.reduce(history, existing, &min(Map.fetch!(&1, resource), &2))

      ceiling =
        [get_in(@ceilings, [platform, resource]), div(existing * 3, 2), week_floor * 2]
        |> Enum.min()
        |> then(&(div(&1, quantum) * quantum))

      desired = Map.fetch!(target, resource)
      rounded = div(desired + quantum - 1, quantum) * quantum
      {resource, max(existing, min(rounded, ceiling))}
    end)
  end

  defp apply_growth(limit, resources, mode, now) do
    reason = "#{mode}: #{limit.vcpus} vCPU/#{limit.memory_gb} GB -> #{resources.vcpus} vCPU/#{resources.memory_gb} GB"

    Repo.query!(
      "SELECT set_config('tuist.runner_concurrency_source', 'automatic', true), set_config('tuist.runner_concurrency_reason', $1, true)",
      [reason]
    )

    limit |> ConcurrencyLimit.changeset(resources) |> Repo.update!()

    # Scope trigger metadata to this update even if called inside a larger
    # transaction (tests and operator tools can do that).
    Repo.query!(
      "SELECT set_config('tuist.runner_concurrency_source', '', true), set_config('tuist.runner_concurrency_reason', '', true)"
    )

    :telemetry.execute([:tuist, :runners, :concurrency, :grown], %{count: 1}, %{
      account_id: limit.account_id,
      platform: limit.platform,
      mode: mode,
      evaluated_at: now
    })
  end

  # Aggregate at the source: only fourteen daily rows cross the wire. This is
  # an hourly indexed per-account scan, never a dispatch-path query. Like
  # session replication, stop at the earliest recorded release/completion and
  # clamp sessions to six hours. Unlike the display replica, require recorded
  # release/completion evidence; orphaned tails and null shapes aren't demand.
  defp recurring_demand(account_id, platform, now) do
    until = now |> DateTime.to_date() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    since = DateTime.add(until, -14, :day)

    %{rows: rows} =
      Repo.query!(
        """
        WITH intervals AS (
          SELECT greatest(s.started_at, $2) AS starts,
            least(COALESCE(s.job_ended_at, c.completed_at, s.ended_at), s.ended_at,
              s.started_at + interval '6 hours', $3) AS ends,
            s.vcpus, s.memory_gb
          FROM runner_sessions s
          LEFT JOIN runner_job_completions c
            ON s.job_ended_at IS NULL
              AND c.workflow_job_id = COALESCE(s.executed_workflow_job_id, s.workflow_job_id)
          WHERE s.account_id = $1 AND s.platform = $4
            AND s.started_at >= $2 - interval '6 hours' AND s.started_at < $3
            AND s.vcpus > 0 AND s.memory_gb > 0
            AND COALESCE(s.job_ended_at, c.completed_at, s.ended_at) IS NOT NULL
        ), events AS (
          SELECT starts AS ts, vcpus AS cpu, memory_gb AS mem FROM intervals WHERE ends > starts
          UNION ALL
          SELECT ends, -vcpus, -memory_gb FROM intervals WHERE ends > starts
          UNION ALL
          SELECT day, 0, 0 FROM generate_series($2::timestamptz, $3::timestamptz, interval '1 day') day
        ), totals AS (
          SELECT ts, sum(sum(cpu)) OVER (ORDER BY ts) AS cpu,
            sum(sum(mem)) OVER (ORDER BY ts) AS mem
          FROM events GROUP BY ts
        ), daily AS (
          SELECT date_trunc('day', ts AT TIME ZONE 'UTC') AS day,
            max(cpu) AS cpu, max(mem) AS mem FROM totals WHERE ts < $3 GROUP BY 1
        )
        SELECT cpu::bigint, mem::bigint,
          (SELECT max(vcpus) FROM intervals), (SELECT max(memory_gb) FROM intervals)
        FROM daily
        """,
        [account_id, since, until, Atom.to_string(platform)]
      )

    case rows do
      [[_, _, largest_cpu, largest_mem] | _] when is_integer(largest_cpu) and is_integer(largest_mem) ->
        cpu = rows |> Enum.map(&Enum.at(&1, 0)) |> Enum.sort(:desc) |> Enum.at(1, 0)
        mem = rows |> Enum.map(&Enum.at(&1, 1)) |> Enum.sort(:desc) |> Enum.at(1, 0)

        if cpu > 0 and mem > 0,
          do: %{vcpus: max(ceil(cpu * 1.25), cpu + largest_cpu), memory_gb: max(ceil(mem * 1.25), mem + largest_mem)}

      _ ->
        nil
    end
  end
end
