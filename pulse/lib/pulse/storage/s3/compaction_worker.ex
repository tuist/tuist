defmodule Pulse.Storage.S3.CompactionWorker do
  @moduledoc """
  Opt-in background maintenance (compaction and cleanup) of each enabled signal
  on its rendezvous owner. Log lines name the signal they maintain. Durable
  manifest discovery includes tenants never observed by this node. Membership
  disagreement can overlap work; conditional publication keeps those races safe.

  Enable only after every writer has been upgraded: `:compaction_enabled` defaults
  to false. Configure `:compaction_interval_ms` (60_000), `:compaction_options`,
  and `:compaction_cleanup_options` to tune limits. Scheduling has up to 10% jitter.
  Each tenant is isolated from errors and exceptions in the rest of the pass.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.Runtime.GenServer
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3.CompactionDiscovery
  alias Pulse.Storage.S3.CompactionOwnership
  alias Pulse.Storage.S3.CompactionSupervision
  alias Pulse.Storage.S3.CompactionTasks
  alias Pulse.Storage.S3.LogCompactor
  alias Pulse.Storage.S3.LogRollups
  alias Pulse.Storage.S3.LogTiers
  alias Pulse.Storage.S3.ManifestBackup
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Storage.S3.MetricTiers
  alias Pulse.Storage.S3.TraceCompactor

  require Logger

  def start_link(config), do: GenServer.start_link(__MODULE__, config, name: Map.get(config, :worker_name, __MODULE__))

  # A lane (see `CompactionSupervision`) runs its operations under its own
  # task supervisor.
  defp tasks(config), do: Map.get(config, :compaction_tasks, CompactionTasks)

  @doc false
  def children(config) do
    if Map.get(config, :compaction_enabled, false) or CompactionOwnership.trace_maintenance_enabled?(config) or
         CompactionOwnership.log_maintenance_enabled?(config),
       do: [{CompactionSupervision, config}],
       else: []
  end

  @impl true
  def init(config) do
    if Task.Supervisor.children(tasks(config)) == [], do: :ok = CompactionOwnership.join(config)
    schedule(config)
    {:ok, config}
  end

  @impl true
  def handle_info(:compact, config) do
    # Timed-out work may still be inside a native call. Do not rejoin or admit
    # more work until the operation actually leaves the dedicated supervisor.
    config =
      if Task.Supervisor.children(tasks(config)) == [] do
        :ok = CompactionOwnership.join_once(config)
        run_pass(config)
      else
        Logger.warning("compaction remains withdrawn while an earlier task is still running")
        config
      end

    schedule(config)
    {:noreply, config}
  end

  @impl true
  def handle_info(_message, config), do: {:noreply, config}

  defp run_pass(config) do
    case run_operation(fn -> CompactionDiscovery.tenants(config) end, {nil, "*"}, "discovery", config) do
      {:ok, tenants} -> Enum.reduce_while(tenants, config, &maintain_tenant/2)
      _error -> config
    end
  end

  defp maintain_tenant(tenant, config), do: maintain_signals(CompactionOwnership.signals(config), tenant, config)
  defp maintain_signals([], _tenant, config), do: {:cont, config}

  defp maintain_signals([signal | rest], tenant, config) do
    case maintain_signal(tenant, signal, config) do
      {:cont, updated} -> maintain_signals(rest, tenant, updated)
      {:halt, updated} -> {:halt, updated}
    end
  end

  defp maintain_signal(tenant, signal, config) do
    if ready?(tenant, signal, config) and CompactionOwnership.local_owner?(tenant, signal, config),
      do: maintain_owned_tenant(tenant, signal, config),
      else: {:cont, config}
  end

  defp backoff_key(tenant, "metrics"), do: tenant
  defp backoff_key(tenant, "traces"), do: {tenant, "traces"}
  defp backoff_key(tenant, "logs"), do: {tenant, "logs"}

  defp maintain_owned_tenant(tenant, signal, config) do
    backoff = Map.get(config, :compaction_backoff, %{})
    key = backoff_key(tenant, signal)

    case compact_tenant(tenant, signal, config) do
      {{:error, :timeout}, config} ->
        deadline = System.monotonic_time(:millisecond) + Map.get(config, :compaction_retry_ms, 300_000)
        {:halt, Map.put(config, :compaction_backoff, Map.put(backoff, key, deadline))}

      {_result, config} ->
        {:cont, Map.put(config, :compaction_backoff, Map.delete(backoff, key))}
    end
  end

  defp ready?(tenant, signal, config) do
    deadline = config |> Map.get(:compaction_backoff, %{}) |> Map.get(backoff_key(tenant, signal), 0)
    deadline == 0 or deadline <= System.monotonic_time(:millisecond)
  end

  defp maintenance("metrics"), do: {MetricsCompactor, :compaction_options, :compaction_cleanup_options}
  defp maintenance("traces"), do: {TraceCompactor, :trace_compaction_options, :trace_compaction_cleanup_options}
  defp maintenance("logs"), do: {LogCompactor, :log_compaction_options, :log_compaction_cleanup_options}

  defp compact_tenant(tenant, signal, config) do
    {module, option_key, cleanup_key} = maintenance(signal)
    opts = Map.get(config, option_key, [])
    cleanup_opts = Map.get(config, cleanup_key, [])
    result = merge_while_progressing(module, tenant, config, opts, Map.get(config, :compaction_max_merges, 32))
    {result, config} = finalize_hours(result, tenant, signal, config)
    {hold, config} = back_up(result, tenant, signal, config, Keyword.get(opts, :grace_ms, 3_600_000))
    cleanup_opts = if hold, do: Keyword.put(cleanup_opts, :now_ms, hold), else: cleanup_opts
    {cleanup_if_owner(result, tenant, signal, config, module, cleanup_opts), config}
  end

  # Rewrite settled metric hours into metric-grouped segments and rollups,
  # oldest first, up to `:metric_finalize_max_hours` per pass. An hour that
  # fails is skipped for an hour so it cannot block the others.
  defp finalize_hours({:error, :timeout} = result, _tenant, _signal, config), do: {result, config}

  defp finalize_hours(result, tenant, "metrics", config) do
    # Metrics maintenance only runs with metrics compaction enabled (CompactionOwnership.signals/1).
    if Map.get(config, :metric_finalize_enabled, true) do
      consolidated = consolidate_next(tenant, config, Map.get(config, :metric_consolidate_max_batches, 8))

      if consolidated == :timeout,
        do: {{:error, :timeout}, config},
        else: finalize_next(result, tenant, config, Map.get(config, :metric_finalize_max_hours, 6))
    else
      {result, config}
    end
  end

  defp finalize_hours(result, tenant, "logs", config) do
    {result, config} =
      if Map.get(config, :log_finalize_enabled, true),
        do: group_logs(result, tenant, config),
        else: {result, config}

    if Map.get(config, :log_rollup_enabled, true) and result != {:error, :timeout},
      do: {result, roll_logs(tenant, config, Map.get(config, :log_rollup_max_builds, 8))},
      else: {result, config}
  end

  defp finalize_hours(result, _tenant, _signal, config), do: {result, config}

  # Group settled log segments by stream (`LogTiers`): busy unfinished hours
  # batch by batch, then settled hours, oldest first, up to
  # `:log_finalize_max_hours` per pass. An hour that fails is skipped for an
  # hour so it cannot block the others.
  defp group_logs(result, tenant, config) do
    opts = Map.get(config, :log_finalize_options, [])

    case consolidate_logs(tenant, config, opts, Map.get(config, :log_consolidate_max_batches, 8)) do
      :timeout -> {{:error, :timeout}, config}
      :ok -> finalize_logs(result, tenant, config, opts, Map.get(config, :log_finalize_max_hours, 6))
    end
  end

  defp consolidate_logs(_tenant, _config, _opts, 0), do: :ok

  defp consolidate_logs(tenant, config, opts, remaining) do
    case run_operation(
           fn -> LogTiers.consolidate(tenant, config, opts) end,
           {"logs", tenant},
           "log_consolidate",
           config
         ) do
      {:ok, %{hour: hour}} when is_integer(hour) ->
        if CompactionOwnership.local_owner?(tenant, "logs", config),
          do: consolidate_logs(tenant, config, opts, remaining - 1),
          else: :ok

      {:error, :timeout} ->
        :timeout

      _ ->
        :ok
    end
  end

  defp finalize_logs(result, _tenant, config, _opts, 0), do: {result, config}

  defp finalize_logs(result, tenant, config, opts, remaining) do
    now = System.monotonic_time(:millisecond)
    skips = config |> Map.get(:log_finalize_skip, %{}) |> Map.get(tenant, %{})
    skips = Map.reject(skips, fn {_hour, until} -> until <= now end)
    hour_opts = Keyword.put(opts, :skip_hours, MapSet.new(Map.keys(skips)))
    put_skips = &Map.put(config, :log_finalize_skip, Map.put(Map.get(config, :log_finalize_skip, %{}), tenant, &1))

    case run_operation(fn -> LogTiers.finalize(tenant, config, hour_opts) end, {"logs", tenant}, "log_finalize", config) do
      {:ok, %{hour: hour}} when is_integer(hour) ->
        if CompactionOwnership.local_owner?(tenant, "logs", config),
          do: finalize_logs(result, tenant, put_skips.(skips), opts, remaining - 1),
          else: {result, put_skips.(skips)}

      {:error, {hour, _reason}} when is_integer(hour) ->
        finalize_logs(result, tenant, put_skips.(Map.put(skips, hour, now + 3_600_000)), opts, remaining - 1)

      {:error, :timeout} = timeout ->
        {timeout, put_skips.(skips)}

      _ ->
        {result, put_skips.(skips)}
    end
  end

  # Per-minute log rollups for settled minutes (`LogRollups`), several per
  # pass so a busy tenant keeps up; a failing minute is skipped for an hour.
  defp roll_logs(_tenant, config, 0), do: config

  defp roll_logs(tenant, config, remaining) do
    now = System.monotonic_time(:millisecond)

    skips =
      config |> Map.get(:log_rollup_skip, %{}) |> Map.get(tenant, %{}) |> Map.reject(fn {_, until} -> until <= now end)

    opts = Keyword.put(Map.get(config, :log_rollup_options, []), :skip, MapSet.new(Map.keys(skips)))
    put = &Map.put(config, :log_rollup_skip, Map.put(Map.get(config, :log_rollup_skip, %{}), tenant, &1))

    case run_operation(fn -> LogRollups.roll(tenant, config, opts) end, {"logs", tenant}, "log_rollup", config) do
      {:ok, %{from: from}} when is_integer(from) ->
        if CompactionOwnership.local_owner?(tenant, "logs", config),
          do: roll_logs(tenant, put.(skips), remaining - 1),
          else: put.(skips)

      {:error, {minute, _reason}} when is_integer(minute) ->
        roll_logs(tenant, put.(Map.put(skips, minute, now + 3_600_000)), remaining - 1)

      _ ->
        put.(skips)
    end
  end

  # Group settled raw segments of unfinished hours by metric name, batch by
  # batch, so selectors over the current hour read only their metrics' rows.
  defp consolidate_next(_tenant, _config, 0), do: :ok

  defp consolidate_next(tenant, config, remaining) do
    opts = Map.get(config, :metric_finalize_options, [])

    case run_operation(
           fn -> MetricTiers.consolidate(tenant, config, opts) end,
           {"metrics", tenant},
           "consolidate",
           config
         ) do
      {:ok, %{hour: hour}} when is_integer(hour) ->
        if CompactionOwnership.local_owner?(tenant, "metrics", config),
          do: consolidate_next(tenant, config, remaining - 1),
          else: :ok

      {:error, :timeout} ->
        :timeout

      _ ->
        :ok
    end
  end

  defp finalize_next(result, _tenant, config, 0), do: {result, config}

  defp finalize_next(result, tenant, config, remaining) do
    now = System.monotonic_time(:millisecond)
    skips = config |> Map.get(:metric_finalize_skip, %{}) |> Map.get(tenant, %{})
    skips = Map.reject(skips, fn {_hour, until} -> until <= now end)
    opts = Keyword.put(Map.get(config, :metric_finalize_options, []), :skip_hours, MapSet.new(Map.keys(skips)))

    put_skips =
      &Map.put(config, :metric_finalize_skip, Map.put(Map.get(config, :metric_finalize_skip, %{}), tenant, &1))

    case run_operation(fn -> MetricTiers.finalize(tenant, config, opts) end, {"metrics", tenant}, "finalize", config) do
      {:ok, %{hour: nil}} ->
        {result, put_skips.(skips)}

      {:ok, %{hour: _}} ->
        if CompactionOwnership.local_owner?(tenant, "metrics", config),
          do: finalize_next(result, tenant, put_skips.(skips), remaining - 1),
          else: {result, put_skips.(skips)}

      {:error, {hour, _reason}} when is_integer(hour) ->
        finalize_next(result, tenant, put_skips.(Map.put(skips, hour, now + 3_600_000)), remaining - 1)

      {:error, :timeout} = timeout ->
        {timeout, put_skips.(skips)}

      _error ->
        {result, put_skips.(skips)}
    end
  end

  # Back up the manifest every `:manifest_backup_interval_ms` and return the
  # clock cleanup may use, so the newest backup stays restorable. nil when
  # backups are off or the prefix is retention-managed.
  defp back_up({:error, :timeout} = _result, _tenant, _signal, config, _grace), do: {0, config}

  defp back_up(_result, tenant, signal, config, grace) do
    if Map.get(config, :manifest_backup_enabled, true) do
      backups = Map.get(config, :manifest_backups, %{})
      last = backups |> Map.get_lazy({tenant, signal}, fn -> latest_backup(tenant, signal, config) end)
      last = if backup_due?(last, config), do: run_backup(tenant, signal, config, last), else: last
      config = Map.put(config, :manifest_backups, Map.put(backups, {tenant, signal}, last))
      {if(last != :retention_managed, do: ManifestBackup.hold_ms(last, grace, config)), config}
    else
      {nil, config}
    end
  end

  defp latest_backup(tenant, signal, config) do
    case ManifestBackup.latest(tenant, signal, config) do
      {:ok, taken} -> taken
      _ -> nil
    end
  end

  defp backup_due?(:retention_managed, _config), do: false
  defp backup_due?(nil, _config), do: true

  defp backup_due?(last, config),
    do: System.system_time(:millisecond) - last >= Map.get(config, :manifest_backup_interval_ms, 900_000)

  defp run_backup(tenant, signal, config, last) do
    keep = Map.get(config, :manifest_backup_keep, 48)

    case run_operation(
           fn -> ManifestBackup.backup(tenant, signal, config, keep: keep) end,
           {signal, tenant},
           "backup",
           config
         ) do
      {:ok, %{taken_ms: taken}} -> taken
      {:ok, :retention_managed} -> :retention_managed
      _error -> last
    end
  end

  # One merge combines at most 32 segments, while frequent pushers (a log
  # shipper flushing every second) create more than that per interval. Keep
  # merging while each merge makes progress, within a per-pass budget, so
  # compaction can catch up instead of falling further behind.
  defp merge_while_progressing(module, tenant, config, opts, remaining) do
    result =
      run_operation(
        fn -> merge_operation(module, tenant, config, opts) end,
        {signal_of(module), tenant},
        "merge",
        config
      )

    case result do
      {:ok, %{merged: merged}} when merged > 0 and remaining > 1 ->
        if CompactionOwnership.local_owner?(tenant, signal_of(module), config),
          do: merge_while_progressing(module, tenant, config, opts, remaining - 1),
          else: result

      _ ->
        result
    end
  end

  defp signal_of(MetricsCompactor), do: "metrics"
  defp signal_of(TraceCompactor), do: "traces"
  defp signal_of(LogCompactor), do: "logs"

  defp merge_operation(TraceCompactor, tenant, config, opts), do: TraceCompactor.maintain(tenant, config, opts)
  defp merge_operation(module, tenant, config, opts), do: module.compact(tenant, config, opts)

  defp cleanup_if_owner({:error, :timeout} = result, _tenant, _signal, _config, _module, _opts), do: result

  defp cleanup_if_owner(result, tenant, signal, config, module, opts),
    do: cleanup_while_full(result, tenant, signal, config, module, opts, 4)

  # Each merge retires up to 32 sources, so one pass's merges can make more
  # deletions due than one cleanup batch removes. Repeat full batches a few
  # times per pass so cleanup keeps pace with compaction.
  defp cleanup_while_full(result, tenant, signal, config, module, opts, remaining) do
    # Recheck after the merge: ownership may have moved while storage was busy.
    if CompactionOwnership.local_owner?(tenant, signal, config) do
      cleaned = run_operation(fn -> module.cleanup(tenant, config, opts) end, {signal, tenant}, "cleanup", config)

      if remaining > 1 and full_batch?(cleaned, opts),
        do: cleanup_while_full(cleaned, tenant, signal, config, module, opts, remaining - 1),
        else: cleaned
    else
      result
    end
  end

  defp full_batch?({:ok, deleted}, opts) when is_integer(deleted), do: deleted >= Keyword.get(opts, :max_deletions, 128)
  defp full_batch?(_result, _opts), do: false

  # `subject` is `{signal, tenant}`; discovery spans every signal and tenant.
  defp run_operation(operation, subject, name, config) do
    Pulse.SelfMetrics.track(:compaction, metric_dimension(name), fn ->
      do_run_operation(operation, subject, name, config)
    end)
  end

  defp metric_dimension("merge"), do: :worker_merge
  defp metric_dimension("cleanup"), do: :worker_cleanup
  defp metric_dimension("discovery"), do: :worker_discovery
  defp metric_dimension("finalize"), do: :worker_finalize
  defp metric_dimension("consolidate"), do: :worker_consolidate
  defp metric_dimension("log_rollup"), do: :worker_log_rollup
  defp metric_dimension("log_finalize"), do: :worker_log_finalize
  defp metric_dimension("log_consolidate"), do: :worker_log_consolidate
  defp metric_dimension("backup"), do: :worker_backup

  defp do_run_operation(operation, subject, name, config) do
    task =
      Task.Supervisor.async_nolink(tasks(config), fn ->
        Process.set_label({:pulse, :maintenance})
        execute_operation(operation, subject, name)
      end)

    case Task.yield(task, operation_timeout(config, name)) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        report_failure(subject, name, reason)

      nil ->
        # Keep the task supervised until it finishes. Killing a process inside
        # a dirty native call can signal termination before native work ends,
        # hiding it from admission checks. Late publication remains conditional.
        Process.demonitor(task.ref, [:flush])
        CompactionOwnership.leave(config)
        :telemetry.execute([:pulse, :compaction, :timeout], %{}, %{operation: name})
        report_failure(subject, name, :timeout)
    end
  end

  defp operation_timeout(config, "discovery"), do: Map.get(config, :compaction_discovery_timeout_ms, 60_000)
  # A production hour (tens of millions of rows) finalizes in several
  # partitions within one call.
  defp operation_timeout(config, "finalize"), do: Map.get(config, :metric_finalize_timeout_ms, 900_000)
  defp operation_timeout(config, "consolidate"), do: Map.get(config, :metric_consolidate_timeout_ms, 120_000)
  defp operation_timeout(config, "log_rollup"), do: Map.get(config, :log_rollup_timeout_ms, 120_000)
  # A production hour of logs (millions of lines) is rewritten in one call.
  defp operation_timeout(config, "log_finalize"), do: Map.get(config, :log_finalize_timeout_ms, 900_000)
  defp operation_timeout(config, "log_consolidate"), do: Map.get(config, :log_consolidate_timeout_ms, 120_000)
  defp operation_timeout(config, "backup"), do: Map.get(config, :manifest_backup_timeout_ms, 120_000)
  defp operation_timeout(config, _operation), do: Map.get(config, :compaction_timeout_ms, 30_000)

  defp report_failure(subject, name, reason) do
    Logger.warning("#{label(subject, name)} failed #{tenant(subject)}: #{inspect(reason)}")
    {:error, reason}
  end

  defp execute_operation(operation, subject, name) do
    result = operation.()
    report_result(result, subject, name)
    result
  rescue
    exception ->
      Logger.warning("#{label(subject, name)} raised #{tenant(subject)}: #{Exception.message(exception)}")
      {:error, :operation_raised}
  catch
    kind, reason ->
      Logger.warning("#{label(subject, name)} exited #{tenant(subject)}: #{inspect({kind, reason})}")
      {:error, :operation_exited}
  end

  defp report_result({:error, :not_found}, subject, name) do
    Logger.debug("#{label(subject, name)} missing object #{tenant(subject)}")
  end

  defp report_result({:ok, _}, _subject, _name), do: :ok

  defp report_result({:error, reason}, subject, name) do
    Logger.warning("#{label(subject, name)} failed #{tenant(subject)}: #{inspect(reason)}")
  end

  defp label({nil, _tenant}, name), do: "compaction #{name}"
  defp label({signal, _tenant}, name), do: "#{signal} compaction #{name}"
  defp tenant({_signal, tenant}), do: "tenant=#{tenant}"

  defp schedule(config) do
    interval = Map.get(config, :compaction_interval_ms, 60_000)
    jitter = :rand.uniform(max(div(interval, 10), 1)) - 1
    Process.send_after(self(), :compact, interval + jitter)
  end
end
