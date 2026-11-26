defmodule Tuist.RemoteExecution.TaskSizes do
  @moduledoc """
  Automatic task sizing: what each remote action used in its last runs picks
  the memory and CPU guarantee of its next one.

  The executor measures the action's command in its own guest cgroup (CPU
  time, wall time and the peak of the memory the guest cannot reclaim) and
  the gateway sends it with the action's record, keyed by the action's size
  key: SHA-256 of its working directory, sorted output paths and non-Tuist
  platform properties, which survives source edits and differs between
  sibling actions of a target. `record/2` keeps one row per project and key,
  for every account. A reading decays by a fifth a run (`max(observed, 0.8 ×
  previous)`), so one low run does not undo a high one; an OOM kill raises
  the next runs to the next size up for 7 days. Rows unused for 14 days are
  deleted (`purge/0`).

  `choose/3` applies them to accounts with the `remote_execution_task_sizing`
  flag, whose VMs burst to `Settings.burst_vcpus/0` vCPUs:

  - **Memory** is a hard floor: the smallest size whose usable memory (the
    size less about 0.7 GiB the guest keeps) holds 1.3 × the peak, raised to
    the OOM floor. A size the action asks for with `tuist-memory-gb` is a
    floor too; one that asks for none starts at the account's default
    (`Settings.default_memory_gb/1`, 2 GB), so a measurement can run it
    smaller than an unflagged account's 4 GB. `tuist-task-sizing: off` runs
    exactly the size asked for, or that default. A size the account's limits
    do not hold is lowered to the largest that fits.
  - **CPU** is a guarantee, not a size: the cores the action used, rounded up
    to half a vCPU, between half a vCPU and the burst vCPUs and at most half
    the account's vCPU limit. It weighs the VM's cgroup while the action runs,
    so on a busy host actions that kept their cores busy keep them, and on an
    idle one every action bursts. The scheduler lowers it to what the
    account's limit leaves rather than make the action wait.

  Reads go through a 60 s node-local cache, so the scheduler never waits on
  the database. The lookups are single-row reads, so concurrent misses of a
  key are not coalesced (`locking: false`).
  """
  import Ecto.Query

  alias Tuist.FeatureFlags
  alias Tuist.KeyValueStore
  alias Tuist.Projects.Project
  alias Tuist.RemoteExecution.Settings
  alias Tuist.RemoteExecution.TaskSize
  alias Tuist.Repo

  @key ~r/\A[0-9a-f]{64}\z/
  @guest_overhead_bytes 716_800 * 1024
  @margin 1.3
  @oom_floor_days 7
  @retention_days 14
  @cache_ttl_ms 60_000
  @max_sized_keys 2_000
  @max_label_bytes 1_024

  @doc """
  The memory and CPU guarantee an action of `project` runs with: `{memory_gb,
  cpu_guarantee_milli}`, the guarantee nil to keep the VM's own. `asked_gb`
  is the size the action asked for, and `params` the gateway's submission
  (`size_key`, `task_sizing`).
  """
  def choose(%Project{account: account} = project, asked_gb, params) do
    key = params["size_key"]

    if FeatureFlags.remote_execution_task_sizing_enabled?(account) do
      # The gateway marks an action without `tuist-memory-gb` (an older one
      # does not, and its size stays a floor): it starts at the account's
      # default, below which only its measurements take it.
      explicit = params["memory_explicit"] != false
      limits = limits(account)
      asked_gb = if explicit, do: asked_gb, else: Settings.default_memory_gb(limits)

      if is_binary(key) and Regex.match?(@key, key) and params["task_sizing"] != false do
        case cached(project.id, key) do
          %TaskSize{} = size ->
            {memory_gb, reason} = memory(size, asked_gb, explicit, limits)
            decided(reason)
            {memory_gb, guarantee(size.cores, account.remote_execution_vcpus_limit)}

          nil ->
            decided(:default)
            {asked_gb, nil}
        end
      else
        {asked_gb, nil}
      end
    else
      {asked_gb, nil}
    end
  end

  defp limits(account),
    do: %Settings{
      vcpus: account.remote_execution_vcpus_limit,
      memory_gb: account.remote_execution_memory_gb_limit,
      burst: true
    }

  defp memory(size, asked_gb, explicit, limits) do
    measured = smallest_holding(size.anon_peak_bytes)
    floor = if oom_floor?(size), do: size.oom_floor_gb, else: 0

    wanted = Enum.max([measured, floor, asked_gb])

    reason =
      cond do
        wanted == asked_gb -> if(explicit, do: :explicit, else: :default)
        wanted == floor -> :oom_floor
        true -> :measured_memory
      end

    fitting = for gb <- Settings.memory_sizes_gb(), gb >= asked_gb, gb <= wanted, Settings.fits?(limits, gb), do: gb

    case fitting do
      [] -> {asked_gb, reason}
      sizes -> {Enum.max(sizes), reason}
    end
  end

  defp smallest_holding(peak_bytes) do
    needed = peak_bytes * @margin

    Enum.find(Settings.memory_sizes_gb(), List.last(Settings.memory_sizes_gb()), fn gb ->
      gb * 1024 * 1024 * 1024 - @guest_overhead_bytes >= needed
    end)
  end

  defp oom_floor?(%TaskSize{oom_floor_gb: gb, oom_floor_until: until}),
    do: is_integer(gb) and not is_nil(until) and DateTime.after?(until, DateTime.utc_now())

  @doc "The guarantee, in millicores, for an action that used `cores` on average."
  def guarantee(cores, account_vcpus) do
    cap = (account_vcpus * 1000) |> div(2) |> div(500) |> Kernel.*(500) |> max(500)

    (ceil(cores * 2) * 500)
    |> max(500)
    |> min(Settings.burst_vcpus() * 1000)
    |> min(cap)
  end

  @doc """
  The project's size keys `choose/3` runs above a default VM or with more
  than its guarantee, which the gateway does not run on a leased default VM.
  Empty unless the account has the flag.
  """
  def sized_keys(%Project{account: account} = project) do
    if FeatureFlags.remote_execution_task_sizing_enabled?(account) do
      KeyValueStore.get_or_update(
        [:remote_execution, :sized_keys, project.id],
        [ttl: @cache_ttl_ms, locking: false],
        fn ->
          default = Settings.default_memory_gb(limits(account))
          usable = default * 1024 * 1024 * 1024 - @guest_overhead_bytes
          default_cores = Settings.shape(default).vcpus

          Repo.all(
            from(t in TaskSize,
              where: t.project_id == ^project.id,
              where:
                t.anon_peak_bytes * @margin > ^usable or t.cores > ^default_cores or
                  (t.oom_floor_gb > ^default and t.oom_floor_until > ^DateTime.utc_now()),
              order_by: [desc: t.updated_at],
              limit: @max_sized_keys,
              select: t.key
            )
          )
        end
      )
    else
      []
    end
  end

  defp cached(project_id, key) do
    KeyValueStore.get_or_update(
      [:remote_execution, :task_size, project_id, key],
      [ttl: @cache_ttl_ms, locking: false],
      fn ->
        Repo.get_by(TaskSize, project_id: project_id, key: key)
      end
    )
  end

  @doc """
  Stores the usage of the gateway's action records that carry one. Best
  effort like the records: a lost one costs one stale measurement.
  """
  def record(%Project{} = project, records) when is_list(records) do
    now = DateTime.utc_now(:second)

    rows =
      records
      |> Enum.flat_map(&List.wrap(row(project, &1, now)))
      # One row per key: a batch cannot update a row twice.
      |> Map.new(&{&1.key, &1})
      |> Map.values()

    if rows != [] do
      Repo.insert_all(TaskSize, rows, on_conflict: upsert(), conflict_target: [:project_id, :key])
    end

    :ok
  end

  defp row(project, %{"size_key" => key, "usage" => %{} = usage} = record, now) when is_binary(key) do
    with true <- Regex.match?(@key, key),
         [cpu_ms, wall_ms, peak] <- counts(usage, ["cpu_ms", "wall_ms", "anon_peak_bytes"]) do
      vcpus = positive(usage["vcpus"]) || Settings.burst_vcpus()
      # Sub-second commands say little about the cores they could use.
      cores = if wall_ms >= 1000, do: min(cpu_ms / wall_ms, vcpus * 1.0), else: 0.0
      ran_in = positive(usage["memory_gb"]) || positive(record["memory_gb"]) || Settings.default_memory_gb()
      oom_floor = if positive(usage["oom_kills"]), do: next_size(ran_in)

      %{
        project_id: project.id,
        key: key,
        target_label: label(record["target"]),
        mnemonic: label(record["mnemonic"]),
        anon_peak_bytes: min(peak, 1_099_511_627_776),
        cores: cores,
        p90_cores: min(number(usage["p90_cores"]), vcpus * 1.0),
        wall_ms: wall_ms,
        oom_floor_gb: oom_floor,
        oom_floor_until: if(oom_floor, do: DateTime.add(now, @oom_floor_days, :day)),
        runs: 1,
        updated_at: now
      }
    else
      _ -> nil
    end
  end

  defp row(_project, _record, _now), do: nil

  defp counts(usage, names) do
    values = Enum.map(names, &usage[&1])
    if Enum.all?(values, &(is_integer(&1) and &1 >= 0)), do: values
  end

  defp next_size(gb) do
    sizes = Settings.memory_sizes_gb()
    Enum.find(sizes, List.last(sizes), &(&1 > gb))
  end

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp number(value) when is_number(value) and value >= 0, do: value * 1.0
  defp number(_value), do: 0.0

  defp label(value) when is_binary(value) and value != "" and byte_size(value) <= @max_label_bytes,
    do: if(String.valid?(value), do: value)

  defp label(_value), do: nil

  # Each reading decays the stored one by a fifth (0.8 below).
  defp upsert do
    from(t in TaskSize,
      update: [
        set: [
          target_label: fragment("COALESCE(EXCLUDED.target_label, ?)", t.target_label),
          mnemonic: fragment("COALESCE(EXCLUDED.mnemonic, ?)", t.mnemonic),
          anon_peak_bytes: fragment("GREATEST(EXCLUDED.anon_peak_bytes, (? * 0.8)::bigint)", t.anon_peak_bytes),
          cores: fragment("GREATEST(EXCLUDED.cores, ? * 0.8)", t.cores),
          p90_cores: fragment("EXCLUDED.p90_cores"),
          wall_ms: fragment("EXCLUDED.wall_ms"),
          # A new OOM raises a floor still in force; an expired one is replaced.
          oom_floor_gb:
            fragment(
              "CASE WHEN EXCLUDED.oom_floor_gb IS NULL THEN ? WHEN ? > now() THEN GREATEST(EXCLUDED.oom_floor_gb, ?) ELSE EXCLUDED.oom_floor_gb END",
              t.oom_floor_gb,
              t.oom_floor_until,
              t.oom_floor_gb
            ),
          oom_floor_until: fragment("COALESCE(EXCLUDED.oom_floor_until, ?)", t.oom_floor_until),
          updated_at: fragment("EXCLUDED.updated_at")
        ],
        inc: [runs: 1]
      ]
    )
  end

  @doc "Deletes measurements no action used for 14 days."
  def purge do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days, :day)
    Repo.delete_all(from(t in TaskSize, where: t.updated_at < ^cutoff))
    :ok
  end

  # Telemetry carries no account or project: the reasons are a fixed set.
  defp decided(reason), do: :telemetry.execute([:tuist, :remote_execution, :task_sizing], %{count: 1}, %{reason: reason})
end
