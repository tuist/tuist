defmodule Tuist.Sandboxes.Capacity do
  @moduledoc """
  Memory and disk admission for sandboxes.

  Every guest on a node runs inside the daemon's cgroup, whose limit the
  node reports as `capacity.memory_bytes`. A sandbox that is creating,
  resuming or running is charged its guest memory plus a fixed VMM
  overhead; the daemon keeps a reserve of its own; a node whose sum
  would overflow is not used. Paused sandboxes cost no memory. A node
  that reports no capacity (an older daemon) is not budgeted.

  Idle running sandboxes, those with no residency, are reclaimable: when
  nothing fits, the longest idle ones on the best candidate node are
  paused until the newcomer fits. A sandbox with a resident worker is
  never paused for room.

  Disk is reserved at the ceiling rather than at use. Everything a
  sandbox writes to the node is a fixed-size file (its rootfs clone, its
  sparse workspace image of `workspace_gb`, its memory image) plus a
  little snapshot state and a capped log, so its ceiling is known when it
  is placed. A new sandbox only goes to a node whose disk budget can hold
  its ceiling on top of the ceilings of every sandbox placed there
  (creating, running or resuming) and of every errored one whose jail the
  node still reports, so sandboxes growing into their images later can
  never overrun the budget together. A paused guest cannot grow, so a
  paused sandbox reserves what the node measures its jail holding, plus
  the largest growth one paused sandbox could make back to its ceiling,
  and a resume takes its full ceiling back under the node's lock. A
  resume the budget cannot take fails like one without memory, and the
  disk-pressure sweep archives the least recently paused Orb to restore
  the reserve (`reserved_disk_bytes/1`). A pause also writes a full memory image
  beside the previous one, so the filesystem must have that much free
  plus headroom at placement and at resume.

  Reservations are serialized per node with a transaction-scoped
  advisory lock. The reservation is the row itself: `node_name` set on a
  creating sandbox, or the `resuming` state on a paused one, both of
  which the reserved sums count.

  A node whose daemon reports a memory ceiling above its floor has an
  elastic carve-out: the daemon's Pod starts at the floor, normally just
  the daemon's own memory so runners keep the node until a sandbox needs
  it, and when nothing fits even after pausing idle sandboxes the Pod's
  memory is grown in place, in whole GiB, up to the ceiling. The kubelet
  applies a growth that fits the node at once and defers one that does
  not; a deferred growth is given back and the next node tried, and only
  the last one stays asked for, so the runners controller retires idle
  warm runners there. The scheduler counts the requested size either
  way, so runner Pods cannot take room a growth is waiting for. The size
  the server asked for is a `Tuist.Sandboxes.SandboxNode` row, and
  placements budget against the smaller of it and the limit the node
  reports, so a growth is used only once the daemon reports it and a
  shrink stops placements before the kubelet applies it. Grown carve-outs
  shrink back toward what their running sandboxes hold a while after
  their last growth (`shrink_carve_outs/0`), which hands the memory back
  to the runner pools.

  CPU is not admitted: guests burst into the node's idle cores. The
  daemon's CPU request follows what its sandboxes are guaranteed
  (`sync_cpu/1`), so those cores stay out of exclusive-CPU runners.
  """

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client, as: KubernetesClient
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshotCopy
  alias Tuist.Sandboxes.MacosCapacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxNode
  alias Tuist.Sandboxes.Workers.ReclaimCapacityWorker

  require Logger

  @mib 1024 * 1024
  @gib 1024 * @mib
  # The daemon, the jailers and the Firecracker processes share the cgroup
  # with the guests.
  @daemon_reserve_bytes 512 * @mib
  # Per guest, outside its memory: the VMM process, vsock and tap buffers.
  @vm_overhead_bytes 64 * @mib
  # Room the filesystem must keep beyond the next memory image.
  @disk_headroom_bytes 1024 * @mib
  # Per sandbox beyond its three images: the vmstate file, the capped
  # console log and metadata.
  @sandbox_disk_overhead_bytes 64 * @mib
  @charged_states [:creating, :resuming, :running]
  @placed_states [:creating, :resuming, :running, :paused]
  @advisory_lock_namespace 7_302
  # Elastic carve-outs move in whole GiB.
  @carve_out_step_bytes @gib
  # How long a carve-out keeps a growth, and the room of an agent sandbox
  # that paused, before a shrink gives them back; CI pressure shrinks at
  # once. Each growth the kubelet defers makes the runners-controller retire
  # an idle warm runner, and a shrink lets a new one take the room, so
  # giving memory back between an Orb's pause and its next turn, or as a
  # remote execution worker's warm floor moves between workers, retired a
  # warm runner per cycle (production, November 2026).
  @shrink_hold_seconds 300
  # `Tuist.RemoteExecution.Scheduler`'s `@warm_hold_ms`.
  @execution_hold_seconds 60
  @allocation_ttl_seconds 15
  # How long a placement or resume waits for a growth to be reported, and
  # how long the poller's admission check does before it leaves a work item
  # queued: it must still acknowledge within the queue's five seconds.
  @grow_wait_ms 15_000
  @admission_grow_wait_ms 2_500
  # How long a resume waits out a growth the kubelet deferred while the
  # grant still offers the memory, before its sandbox is moved off.
  @resume_deferral_wait_ms 60_000
  # Below the new limit, so the kubelet's check that usage fits passes.
  @shrink_reclaim_margin_bytes 256 * @mib
  # How long a node's last confirmed CPU request saves a Kubernetes read.
  @cpu_request_cache_ttl to_timeout(minute: 5)

  def charge_bytes(%{memory_mb: memory_mb}) when is_integer(memory_mb), do: memory_mb * @mib + @vm_overhead_bytes

  def pause_bytes(%{memory_mb: memory_mb}) when is_integer(memory_mb), do: memory_mb * @mib

  @doc "Stores a controller observation, ordered across replicas and bound to a daemon Pod."
  def update_allocation(
        %{
          "node" => name,
          "pod" => pod,
          "observed_at" => observed,
          "memory_bytes" => memory,
          "free_bytes" => free,
          "reclaim" => reclaim
        } = params
      )
      when is_integer(memory) and memory >= 0 and is_integer(free) and free >= 0 and is_boolean(reclaim) do
    # Controllers that predate the compute allocator's remote execution
    # pool send no warm target, controllers before CPU grants send no
    # `cpu_free_milli` (their nodes' daemons keep their CPU request), and
    # controllers before reclaimable CPU send no `cpu_reclaimable_milli`.
    warm = Map.get(params, "warm_bytes", 0)
    cpu_free = params["cpu_free_milli"]
    cpu_reclaimable = Map.get(params, "cpu_reclaimable_milli", 0)
    # Controllers before the per-node budget send no `sibling_memory_bytes`.
    sibling = params["sibling_memory_bytes"]

    with true <- count?(warm),
         true <- is_nil(sibling) or count?(sibling),
         true <- valid_name?(name),
         true <- valid_name?(pod),
         true <- is_nil(cpu_free) or count?(cpu_free),
         true <- count?(cpu_reclaimable),
         {:ok, timestamp} <- allocation_timestamp(observed) do
      store_allocation(name, pod, timestamp, %{
        allocation_memory_bytes: memory,
        allocation_free_bytes: free,
        allocation_cpu_free_milli: cpu_free,
        allocation_cpu_reclaimable_milli: cpu_reclaimable,
        allocation_reclaim: reclaim,
        allocation_warm_bytes: warm,
        allocation_sibling_memory_bytes: sibling
      })
    else
      _ -> {:error, :invalid_allocation}
    end
  end

  def update_allocation(_params), do: {:error, :invalid_allocation}

  defp count?(value), do: is_integer(value) and value >= 0

  defp valid_name?(name) when is_binary(name),
    do: byte_size(name) in 1..253 and Regex.match?(~r/^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$/, name)

  defp valid_name?(_name), do: false

  defp allocation_timestamp(observed) when is_binary(observed) do
    with {:ok, timestamp, 0} <- DateTime.from_iso8601(observed),
         true <- fresh_allocation?(timestamp) do
      {:ok, timestamp}
    else
      _ -> {:error, :invalid_allocation}
    end
  end

  defp allocation_timestamp(_observed), do: {:error, :invalid_allocation}

  defp fresh_allocation?(timestamp) do
    age = DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)
    age >= -1000 and age < @allocation_ttl_seconds * 1000
  end

  defp store_allocation(name, pod, timestamp, grant) do
    fn ->
      lock(name)
      row = Repo.get(SandboxNode, name)
      ensure_newer_allocation!(row, timestamp)

      (row || %SandboxNode{name: name})
      |> SandboxNode.changeset(
        Map.merge(grant, %{
          pod_name: pod,
          memory_limit_bytes: allocation_memory_limit(row, pod),
          allocation_observed_at: timestamp
        })
      )
      |> Repo.insert_or_update!()

      # Enqueue in this transaction: a server restart after acknowledgement
      # cannot lose the reclaim. Repeated grants also retry failed pauses.
      enqueue_reclaim(name)
    end
    |> Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_newer_allocation!(%SandboxNode{allocation_observed_at: %DateTime{} = previous}, timestamp) do
    if DateTime.compare(timestamp, previous) != :gt, do: Repo.rollback(:stale_allocation)
  end

  defp ensure_newer_allocation!(_row, _timestamp), do: :ok

  defp allocation_memory_limit(%SandboxNode{pod_name: pod, memory_limit_bytes: limit}, pod), do: limit
  defp allocation_memory_limit(_row, _pod), do: @gib

  # A pause keeps a growth's hold: the growth may be another placement's
  # that has not reserved its memory yet, and shrinking under it refuses
  # that placement. CI pressure still shrinks at once.
  def enqueue_reclaim(node_name) do
    %{node: node_name} |> ReclaimCapacityWorker.new() |> Oban.insert!()
  end

  @doc """
  Whether the runners-controller's latest allocation for the node asks for
  a reclaim: a CI host reservation (or an unhealthy node) is taking it. An
  expired grant alone, such as a stopped controller, is not.
  """
  def ci_reclaim?(name) when is_binary(name) do
    match?(%SandboxNode{allocation_reclaim: true}, Repo.get(SandboxNode, name))
  end

  def shared_node?(name) when is_binary(name), do: Repo.get(SandboxNode, name) != nil
  def shared_node?(_name), do: false

  def reconcile_allocation(node_name) do
    timed(node_name, :reclaim, fn -> do_reconcile_allocation(node_name) end)
  end

  defp do_reconcile_allocation(node_name) do
    case Nodes.lookup(node_name) do
      {:ok, _pid, info} ->
        node = Map.put(info, :name, node_name)
        # A failure is retried by the next grant, a few seconds later.
        sync_cpu(node)

        if elastic?(node) do
          pressure = not allocation_allows?(node, 0)
          if pressure, do: Enum.each(reclaimable(node_name), &reclaim_one(node, &1))
          # CI is taking the node, so a paused sandbox would wait for it to
          # resume; move them, the ones just paused included, to storage.
          if ci_reclaim?(node_name), do: Archives.move_off_node(node_name)

          reconcile_result(keep_warm(node, pressure) || shrink(node, pressure))
        else
          :ok
        end

      {:error, :not_connected} ->
        :ok
    end
  end

  # :superseded means another growth or shrink rewrote the size asked for
  # while this one reclaimed; that writer resizes the Pod itself.
  defp reconcile_result({:error, :superseded}), do: :ok
  defp reconcile_result({:error, reason}), do: {:error, reason}
  defp reconcile_result(_resized_or_unchanged), do: :ok

  # A remote execution worker's share of the compute allocator's floor
  # (`allocation_warm_bytes`): its carve-out grows to it ahead of any
  # action, without waiting for the kubelet; a deferred growth keeps new
  # runner Pods off the room and makes the runners-controller retire idle
  # warm runners for it. Nil when nothing is missing, so the caller shrinks.
  defp keep_warm(node, pressure) do
    with false <- pressure,
         true <- execution_daemon?(node),
         warm when warm > 0 <- node.name |> then(&Repo.get(SandboxNode, &1)) |> warm_bytes(node),
         true <- warm > max(asked_limit(node) || 0, reported_limit(node) || 0),
         {:ok, limit} <- ask_for_growth(node, warm - reserved_bytes(node.name) - @daemon_reserve_bytes),
         :ok <- resize(node, limit) do
      Logger.info("sandboxes: grew an execution carve-out to its warm floor", node: node.name, memory_bytes: limit)
      {:ok, limit}
    else
      {:error, reason} -> {:error, reason}
      _nothing_missing -> nil
    end
  end

  # The warm target of a fresh grant for the node's current Pod, in whole
  # GiB and within the ceiling; 0 when the grant is stale, revoked or for
  # another Pod, so a stopped controller leaves only the chart's floor.
  defp warm_bytes(
         %SandboxNode{
           pod_name: pod,
           allocation_reclaim: false,
           allocation_observed_at: %DateTime{} = at,
           allocation_warm_bytes: warm
         },
         %{elastic: %{pod_name: pod, memory_ceiling_bytes: ceiling}}
       )
       when is_integer(warm) do
    if fresh_allocation?(at), do: warm |> round_up_to_step() |> min(ceiling), else: 0
  end

  defp warm_bytes(_row, _node), do: 0

  # A grant authorizes new work, never a speculative memory reservation.
  # Non-elastic nodes remain usable for standalone development daemons.
  # An execution daemon may grow past the memory the grant offers: its
  # actions serve CI jobs that already hold runners, so they go ahead of
  # queued CI up to the carve-out's ceiling. A revoked, expired or missing
  # grant (a host reservation, an unhealthy node, a stopped controller)
  # still refuses.
  defp allocation_allows?(node, needed) do
    if elastic?(node) do
      outcome =
        case allocation_outcome(Repo.get(SandboxNode, node.name), node, needed) do
          :allocation_limit -> if execution_daemon?(node), do: :ahead_of_ci, else: :allocation_limit
          outcome -> outcome
        end

      :telemetry.execute([:tuist, :sandboxes, :capacity], %{duration: 0}, %{
        node: node.name,
        operation: :admission,
        outcome: outcome
      })

      outcome in [:allowed, :ahead_of_ci]
    else
      true
    end
  end

  defp allocation_outcome(
         %SandboxNode{
           pod_name: pod,
           allocation_reclaim: false,
           allocation_observed_at: %DateTime{} = at,
           allocation_memory_bytes: bytes
         } = row,
         node,
         needed
       )
       when is_integer(bytes) do
    cond do
      pod != node.elastic.pod_name -> :replaced_pod
      not fresh_allocation?(at) -> :expired
      bytes - sibling_growth(node.name, row) < needed -> :allocation_limit
      true -> :allowed
    end
  end

  defp allocation_outcome(%SandboxNode{allocation_reclaim: true}, _node, _needed), do: :ci_reclaim
  defp allocation_outcome(_row, _node, _needed), do: :missing_grant

  # The agent daemon and the remote execution worker on a host share its
  # memory, but each grant counts the other carve-out at its size when the
  # controller looked. What the other has been asked to grow by since then
  # comes off this grant, so both cannot grow into the same free bytes
  # before the next observation. Both run under the host's lock.
  defp sibling_growth(name, %SandboxNode{allocation_sibling_memory_bytes: counted}) when is_integer(counted) do
    case Repo.get(SandboxNode, sibling_name(name)) do
      %SandboxNode{memory_limit_bytes: asked} when is_integer(asked) -> max(asked - counted, 0)
      _ -> 0
    end
  end

  defp sibling_growth(_name, _row), do: 0

  defp sibling_name(name) do
    suffix = Nodes.execution_daemon_suffix()
    if String.ends_with?(name, suffix), do: String.replace_suffix(name, suffix, ""), else: name <> suffix
  end

  # A host's two daemons connect under their own names but share its memory,
  # so they take one lock.
  defp host_name(name), do: String.replace_suffix(name, Nodes.execution_daemon_suffix(), "")

  @doc "Checks a new turn on an already-running VM under the node admission lock."
  def admit_turn(%Sandbox{platform: :darwin} = sandbox, apply), do: MacosCapacity.admit_turn(sandbox, apply)

  def admit_turn(%Sandbox{node_name: name}, apply) when is_binary(name) do
    case Nodes.lookup(name) do
      {:ok, _pid, info} ->
        node = Map.put(info, :name, name)

        fn ->
          lock(name)

          if allocation_allows?(node, reserved_bytes(name) + @daemon_reserve_bytes),
            do: apply.(),
            else: Repo.rollback(:no_capacity)
        end
        |> Repo.transaction()
        |> case do
          {:ok, result} -> result
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_connected} ->
        if shared_node?(name), do: {:error, :no_capacity}, else: apply.()
    end
  end

  def admit_turn(_sandbox, apply), do: apply.()

  def memory_budget_bytes(node) do
    case memory_limit_bytes(node) do
      nil -> :unbounded
      limit -> max(limit - @daemon_reserve_bytes, 0)
    end
  end

  @doc """
  The memory limit placements on the node budget against: what the node
  reports, capped on an elastic node by what the server last asked its Pod
  for. `nil` for a node that reports no limit.
  """
  def memory_limit_bytes(node) do
    with reported when is_integer(reported) <- reported_limit(node) do
      case asked_limit(node) do
        asked when is_integer(asked) -> min(reported, asked)
        nil -> reported
      end
    end
  end

  @doc """
  Whether the node's carve-out can be resized: its daemon names its Pod and
  reports a ceiling above its floor.
  """
  def elastic?(%{elastic: %{pod_name: pod_name, memory_floor_bytes: floor, memory_ceiling_bytes: ceiling}})
      when is_binary(pod_name) and pod_name != "" and is_integer(floor) and is_integer(ceiling) and ceiling > floor,
      do: true

  def elastic?(_node), do: false

  defp reported_limit(%{capacity: %{memory_bytes: total}}) when is_integer(total) and total > 0, do: total
  defp reported_limit(_node), do: nil

  # What the server last asked this node's current Pod for. A row naming
  # another Pod predates a restart, which starts the Pod at the floor again.
  # A row a grant created before the daemon connected starts at 1 GiB; the
  # Pod never holds less than its floor.
  defp asked_limit(%{name: name, elastic: %{pod_name: pod_name, memory_floor_bytes: floor}} = node)
       when is_binary(name) do
    if elastic?(node) do
      case Repo.get(SandboxNode, name) do
        %SandboxNode{pod_name: ^pod_name, memory_limit_bytes: limit} -> max(limit, floor)
        _other -> nil
      end
    end
  end

  defp asked_limit(_node), do: nil

  @doc """
  Bytes charged to the node by sandboxes that hold or are about to hold
  guest memory.
  """
  def reserved_bytes(node_name) when is_binary(node_name) do
    {count, memory_mb} =
      Repo.one(
        from s in Sandbox,
          where:
            s.node_name == ^node_name and
              (s.state in ^@charged_states or (s.purpose == :remote_execution and s.state == :error)),
          select: {count(s.id), coalesce(sum(s.memory_mb), 0)}
      )

    memory_mb * @mib + count * @vm_overhead_bytes
  end

  def free_bytes(%{name: node_name} = node) do
    case memory_budget_bytes(node) do
      :unbounded -> :unbounded
      budget -> budget - reserved_bytes(node_name)
    end
  end

  @doc """
  Running sandboxes with no resident worker on the node, longest idle
  first: what a pause can free without cutting a turn short.
  """
  def reclaimable(node_name) when is_binary(node_name) do
    Repo.all(
      from s in Sandbox,
        where: s.node_name == ^node_name and s.purpose == :agent,
        where: s.state == :running and is_nil(s.residency_work_id),
        order_by: [asc_nulls_first: s.last_active_at, asc: s.inserted_at]
    )
  end

  def reclaimable_bytes(node_name) do
    node_name |> reclaimable() |> Enum.map(&charge_bytes/1) |> Enum.sum()
  end

  @doc """
  The most disk a sandbox can ever take on its node: its rootfs clone,
  workspace image and memory image, plus a little for snapshot state and
  logs. The rootfs size comes from the node's report of the template.
  """
  def disk_ceiling_bytes(%{workspace_gb: workspace_gb, memory_mb: memory_mb} = sandbox, node) do
    (workspace_gb || 0) * @gib + (memory_mb || 0) * @mib + rootfs_bytes(node, Map.get(sandbox, :template)) +
      @sandbox_disk_overhead_bytes
  end

  defp rootfs_bytes(node, template) do
    sizes =
      for %{name: name} = info <- Map.get(node, :templates, []),
          is_integer(Map.get(info, :rootfs_bytes)),
          do: {name, info.rootfs_bytes}

    case for({^template, size} <- sizes, do: size) do
      [] -> sizes |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
      matching -> Enum.max(matching)
    end
  end

  def disk_budget_bytes(%{disk: %{budget_bytes: budget}}) when is_integer(budget) and budget > 0, do: budget
  def disk_budget_bytes(_node), do: :unbounded

  @doc """
  Disk reserved on the node: the ceilings of the sandboxes placed there
  (creating, running or resuming) and of the errored ones whose jail it
  still reports, and for each paused one the bytes the node reports its
  jail holding, plus the largest growth one of them could make back to its
  ceiling, so the node can always resume one paused sandbox. A paused
  guest writes nothing, so its use only changes once it resumes, which
  reserves its ceiling again (`admit/1`). A paused sandbox the node has
  not measured, or reports in another state, counts at its ceiling. Rows
  rather than the report decide the state, because the report lags by up
  to its interval: a create in flight is not in it yet, and a sandbox
  deleted a moment ago still is.
  """
  def reserved_disk_bytes(node), do: reserved_disk_bytes(node, nil)

  # With `resuming`, that paused sandbox counts at its ceiling and the
  # growth kept for one resume is not: the resume is what it was kept for.
  defp reserved_disk_bytes(%{name: node_name} = node, resuming) do
    reported_ids =
      for %{id: id} <- Map.get(node, :sandboxes, []), {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid

    paused_use = node |> paused_disk_use() |> Map.delete(resuming)
    reserved_error = dynamic([s], s.purpose == :remote_execution or s.id in ^reported_ids)
    reserved = dynamic([s], s.state in ^@placed_states or (s.state == :error and ^reserved_error))

    {held, growths} =
      from(s in Sandbox,
        where: s.node_name == ^node_name,
        where: ^reserved,
        select: %{id: s.id, state: s.state, workspace_gb: s.workspace_gb, memory_mb: s.memory_mb, template: s.template}
      )
      |> Repo.all()
      |> Enum.map(&held_disk_bytes(&1, disk_ceiling_bytes(&1, node), paused_use))
      |> Enum.unzip()

    growth = if resuming, do: 0, else: Enum.max(growths, fn -> 0 end)
    Enum.sum(held) + growth + reserved_disk_snapshot_bytes(node)
  end

  # The bytes the node measured each paused sandbox's jail holding.
  defp paused_disk_use(node) do
    for %{id: id, state: "paused", disk_bytes: bytes} <- Map.get(node, :sandboxes, []), is_integer(bytes), into: %{} do
      {id, bytes}
    end
  end

  # What a sandbox holds against the budget and how far it can still grow.
  defp held_disk_bytes(%{state: :paused, id: id}, ceiling, paused_use) when is_map_key(paused_use, id) do
    used = min(paused_use[id], ceiling)
    {used, ceiling - used}
  end

  defp held_disk_bytes(_sandbox, ceiling, _paused_use), do: {ceiling, 0}

  @doc """
  The most disk a disk snapshot can take: full copies of its rootfs and
  workspace once the sandboxes they were cloned from or into diverge.
  """
  def disk_snapshot_ceiling_bytes(%{workspace_gb: workspace_gb, template: template}, node) do
    (workspace_gb || 0) * @gib + rootfs_bytes(node, template) + @sandbox_disk_overhead_bytes
  end

  # An archived snapshot whose node copy is gone has no `node_name` and
  # reserves nothing. Copies on other nodes reserve the same ceiling there.
  defp reserved_disk_snapshot_bytes(%{name: node_name} = node) do
    copies =
      from(c in DiskSnapshotCopy,
        join: s in assoc(c, :disk_snapshot),
        where: c.node_name == ^node_name,
        select: %{workspace_gb: s.workspace_gb, template: s.template}
      )

    from(s in DiskSnapshot,
      where: s.node_name == ^node_name,
      select: %{workspace_gb: s.workspace_gb, template: s.template}
    )
    |> union_all(^copies)
    |> Repo.all()
    |> Enum.map(&disk_snapshot_ceiling_bytes(&1, node))
    |> Enum.sum()
  end

  # Whether the node's disk budget can take a paused sandbox's ceiling
  # back for its resume, on top of what everything else there holds. One
  # the node has not measured already reserves its ceiling.
  defp resume_disk_room?(node, %Sandbox{id: id}) do
    case disk_budget_bytes(node) do
      :unbounded -> true
      budget -> not is_map_key(paused_disk_use(node), id) or reserved_disk_bytes(node, id) <= budget
    end
  end

  @doc """
  Whether the node's disk budget can take a new sandbox's ceiling.
  """
  def disk_room?(node, sandbox) do
    case disk_budget_bytes(node) do
      :unbounded -> true
      budget -> reserved_disk_bytes(node) + disk_ceiling_bytes(sandbox, node) <= budget
    end
  end

  @doc """
  Runs `apply` under the node's lock when its disk budget and free space
  can take a new disk snapshot's ceiling, so a concurrent placement never
  counts on the same bytes. Answers `{:error, :no_capacity}` otherwise.
  `budget_percent:` admits only within that share of the budget.
  `releases:` names a sandbox placed on the node and deleted right after
  the save, whose reservation the snapshot takes over: a snapshot clones
  its source's disks, and its ceiling is within the source's.
  """
  def reserve_disk_snapshot(%{name: node_name} = node, snapshot, apply, opts \\ []) when is_function(apply, 0) do
    ceiling = disk_snapshot_ceiling_bytes(snapshot, node)
    percent = Keyword.get(opts, :budget_percent, 100)
    released = released_disk_bytes(opts[:releases], node)

    Repo.transaction(fn ->
      lock(node_name)

      fits_budget =
        case disk_budget_bytes(node) do
          :unbounded -> true
          budget -> (reserved_disk_bytes(node) - released + ceiling) * 100 <= budget * percent
        end

      fits_filesystem =
        case node do
          %{disk: %{available_bytes: available}} when is_integer(available) -> available >= ceiling + @disk_headroom_bytes
          _node -> true
        end

      if fits_budget and fits_filesystem do
        case apply.() do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        Repo.rollback(:no_capacity)
      end
    end)
  end

  defp released_disk_bytes(nil, _node), do: 0

  defp released_disk_bytes(sandbox, node),
    do: sandbox |> held_disk_bytes(disk_ceiling_bytes(sandbox, node), paused_disk_use(node)) |> elem(0)

  @doc """
  Whether the filesystem has room for the sandbox's next pause, which
  writes a full memory image beside the previous one.
  """
  def disk_space?(%{disk: %{available_bytes: available}}, sandbox) when is_integer(available) do
    available >= pause_bytes(sandbox) + @disk_headroom_bytes
  end

  def disk_space?(_node, _sandbox), do: true

  def ready_nodes(template) when is_binary(template) do
    Enum.filter(
      Nodes.connected_nodes(),
      &(Map.get(&1, :platform, "linux") != "darwin" and Map.get(&1, :execution_slots, 0) == 0 and
          template_ready?(&1, template))
    )
  end

  @doc """
  Reserves a VM on an execution daemon with the image ready: a dedicated
  host's fixed reservation, or a shared runner host's elastic carve-out.
  Every execution daemon serves every account; account limits are charged
  by `Tuist.RemoteExecution.VMs`.

  Memory a daemon's Pod already holds is committed to remote execution, so
  placing into it needs no runners-controller grant. Actions run on behalf
  of CI jobs that hold their runners while they wait, so a CI burst that
  revokes grants must not starve them: a shared host's floor always takes
  VMs. When nothing fits, a shared host's carve-out grows toward its
  ceiling ahead of queued CI (see `allocation_allows?/2`): a growth the
  kubelet defers stays asked for, which keeps new runner Pods off the room
  that running jobs free.
  """
  def place_execution(%Sandbox{} = sandbox, image_tag) do
    candidates =
      Enum.filter(Nodes.connected_nodes(), fn node ->
        execution_node?(node, image_tag, sandbox)
      end)

    charge = charge_bytes(sandbox)

    reserve = fn node ->
      reserve(node, charge, fn -> set_node(sandbox, node.name) end, fn -> execution_fits?(node, sandbox) end, false)
    end

    case Enum.find(rank(candidates), &(reserve.(&1) == :ok)) do
      %{name: node_name} ->
        {:ok, node_name}

      nil ->
        with {:ok, grown} <-
               candidates
               |> Enum.filter(&execution_fits?(&1, sandbox))
               |> grow_somewhere(charge, wait_ms(:grow_wait_ms), :reported),
             :ok <- reserve.(grown) do
          {:ok, grown.name}
        else
          _no_room ->
            log_no_execution_room(sandbox, image_tag, candidates)
            {:error, :no_capacity}
        end
    end
  end

  # Measurement branch only: why a remote execution VM found no node.
  defp log_no_execution_room(sandbox, image_tag, candidates) do
    nodes =
      Enum.map(Nodes.connected_nodes(), fn node ->
        used =
          Repo.all(
            from s in Sandbox,
              where: s.node_name == ^node.name and s.state != :deleted,
              group_by: s.state,
              select: {s.state, coalesce(sum(s.vcpus), 0)}
          )

        cap = min(get_in(node, [:capacity, :cpus]) || 0, Map.get(node, :execution_slots, 0) * 2)
        mib = fn bytes -> if is_integer(bytes), do: div(bytes, 1024 * 1024), else: bytes end
        elastic = Map.get(node, :elastic) || %{}

        "#{node.name} candidate=#{Enum.any?(candidates, &(&1.name == node.name))} cap=#{cap} used=#{inspect(used)}" <>
          " mem_reported_mib=#{mib.(reported_limit(node))} mem_asked_mib=#{mib.(asked_limit(node))}" <>
          " mem_budget_mib=#{mib.(memory_budget_bytes(node))} mem_reserved_mib=#{mib.(reserved_bytes(node.name))}" <>
          " charge_mib=#{mib.(charge_bytes(sandbox))} floor_mib=#{mib.(elastic[:memory_floor_bytes])}" <>
          " ceiling_mib=#{mib.(elastic[:memory_ceiling_bytes])} disk_space=#{disk_space?(node, sandbox)} disk_room=#{disk_room?(node, sandbox)}"
      end)

    Logger.info("re placement no room vcpus=#{sandbox.vcpus} tag=#{image_tag} nodes=[#{Enum.join(nodes, "; ")}]")
  end

  @doc """
  The execution image of the deployment: the `bazel` template tag the most
  connected execution daemons vote for, the greater tag on a tie, or nil
  when none votes. A daemon votes for the tag it was configured with once
  that tag is ready. It keeps older tags ready so it can take work during a
  rollout, so before its tag is ready, or when it does not report one, it
  votes for every tag it has ready. Workers roll out on delete, so while an
  operator replaces them the majority wins.
  """
  def execution_image_tag do
    Nodes.connected_nodes()
    |> Enum.filter(&(execution_daemon?(&1) and Map.get(&1, :execution_deadlines, false)))
    |> Enum.flat_map(&execution_image_votes/1)
    |> Enum.frequencies()
    |> Enum.max_by(fn {tag, count} -> {count, tag} end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp execution_image_votes(node) do
    ready =
      for %{name: "bazel", ready: true, tag: tag} <- Map.get(node, :templates, []), is_binary(tag), uniq: true, do: tag

    configured = Map.get(node, :default_template_tag)

    if Map.get(node, :default_template) == "bazel" and configured in ready, do: [configured], else: ready
  end

  defp execution_fits?(node, sandbox) do
    cpus =
      Repo.one(
        from s in Sandbox,
          where: s.node_name == ^node.name and s.state != :deleted,
          select: coalesce(sum(s.vcpus), 0)
      )

    cpus + sandbox.vcpus <= min(node.capacity.cpus, node.execution_slots * 2) and disk_space?(node, sandbox) and
      disk_room?(node, sandbox)
  end

  defp execution_node?(node, image_tag, sandbox) do
    Map.get(node, :execution_deadlines, false) and
      execution_capacity?(node, sandbox) and
      Enum.any?(Map.get(node, :templates, []), &(&1.name == "bazel" and &1.tag == image_tag and &1.ready))
  end

  defp execution_daemon?(node), do: Map.get(node, :execution_slots, 0) > 0

  defp execution_capacity?(%{execution_slots: slots, capacity: %{cpus: cpus, memory_bytes: memory}}, sandbox)
       when is_integer(slots) and slots > 0 and is_integer(cpus) and is_integer(memory) and memory > 0,
       do: cpus >= sandbox.vcpus

  defp execution_capacity?(_node, _sandbox), do: false

  defp template_ready?(node, template) do
    node
    |> Map.get(:templates, [])
    |> Enum.any?(fn candidate -> candidate.name == template and candidate.ready end)
  end

  @doc """
  Picks and reserves the node a new sandbox boots on: the connected node
  with the template ready, disk for the sandbox and room for it that runs
  the most sandboxes already, so they burst into each other's idle cores
  and leave other nodes whole for runners.
  When no node has room, idle sandboxes are paused on the node that can
  free the most. When no node has disk, the oldest paused Orb on them is
  archived (`Tuist.Sandboxes.Archives.make_node_room/1`), so a retry finds
  room once the upload completes. Returns `{:error, :no_node}` when no
  connected node has the template and `{:error, :no_capacity}` when none
  has room.
  """
  def place(%Sandbox{platform: :darwin} = sandbox), do: MacosCapacity.place(sandbox)
  def place(%Sandbox{} = sandbox), do: place(sandbox, fn _node -> true end)

  @doc """
  `place/1` among the nodes `node_filter` accepts, such as the nodes that
  can reach the store holding the archive a sandbox is restored from, or
  the macOS hosts that have not refused the create yet.
  """
  def place(%Sandbox{platform: :darwin} = sandbox, node_filter), do: MacosCapacity.place(sandbox, node_filter)
  def place(%Sandbox{} = sandbox, node_filter), do: place(sandbox, node_filter, [])

  @doc """
  `place/2` that tries the nodes in `prefer:` first, ahead of the ranking by
  the sandboxes nodes run, such as the nodes holding the session repository's checkout.
  A preferred node only wins when it can take the sandbox like any other
  would; a full one is passed over, never waited for.

  The nodes in `avoid:` take the sandbox only when no other can, even by
  pausing idle sandboxes or growing a carve-out, such as the node an
  archived sandbox was moved off.
  """
  def place(%Sandbox{node_name: nil, template: template} = sandbox, node_filter, opts) do
    ready =
      fn ->
        case ready_nodes(template) do
          [] -> {:retry, []}
          nodes -> nodes
        end
      end
      |> Nodes.await(Nodes.presence_wait_ms())
      |> Enum.filter(node_filter)

    candidates = Enum.filter(ready, &(disk_space?(&1, sandbox) and disk_room?(&1, sandbox) and cpu_room?(&1, sandbox)))

    cond do
      ready == [] ->
        {:error, :no_node}

      candidates == [] ->
        ready |> Enum.map(& &1.name) |> Archives.make_node_room()
        {:error, :no_capacity}

      true ->
        place_avoiding(candidates, sandbox, Keyword.get(opts, :prefer, []), Keyword.get(opts, :avoid, []))
    end
  end

  defp place_avoiding(candidates, sandbox, prefer, avoid) do
    {others, avoided} = Enum.split_with(candidates, &(&1.name not in avoid))

    case others != [] && place_on(others, sandbox, prefer) do
      {:ok, node_name} -> {:ok, node_name}
      _no_room when avoided != [] -> place_on(avoided, sandbox)
      no_room -> no_room
    end
  end

  @doc """
  `place/1` restricted to the nodes that hold a copy of the disk snapshot a
  sandbox is cloned from. Answers `{:error, :no_node}` when none of them is
  connected with the template ready, so the caller can fall back to
  `place/1`.
  """
  def place_on_node(%Sandbox{node_name: nil, template: template} = sandbox, node_names) when is_list(node_names) do
    case Enum.filter(ready_nodes(template), &(&1.name in node_names)) do
      [] ->
        {:error, :no_node}

      nodes ->
        case Enum.filter(nodes, &(disk_space?(&1, sandbox) and disk_room?(&1, sandbox) and cpu_room?(&1, sandbox))) do
          [] -> {:error, :no_capacity}
          candidates -> place_on(candidates, sandbox)
        end
    end
  end

  @doc """
  Why each of `node_names` cannot take the sandbox, read right after a
  placement on them was refused, for its log: `:not_ready`, `:disk_budget`,
  `:disk_space`, the grant's outcome when the runners controller does not
  allow the memory (`:ci_reclaim`, `:allocation_limit`, `:expired`,
  `:missing_grant`, `:replaced_pod`), `:cpu` when it cannot hold the sandbox's CPU guarantee (`cpu_room?/2`), `:ceiling` when the carve-out cannot
  grow that far, `:growth_failed` when the grant allowed a growth that did
  not land (the kubelet deferred it), and `:room` when the node has room
  by now.
  """
  def refusal_reasons(%Sandbox{template: template} = sandbox, node_names) when is_list(node_names) do
    ready = Map.new(ready_nodes(template), &{&1.name, &1})
    charge = charge_bytes(sandbox)

    Map.new(node_names, fn node_name ->
      reason =
        case Map.fetch(ready, node_name) do
          :error -> :not_ready
          {:ok, node} -> node_refusal(node, sandbox, charge)
        end

      {node_name, reason}
    end)
  end

  defp node_refusal(node, sandbox, charge) do
    reserved = reserved_bytes(node.name)

    grant =
      if elastic?(node),
        do: allocation_outcome(Repo.get(SandboxNode, node.name), node, reserved + charge + @daemon_reserve_bytes),
        else: :allowed

    cond do
      (placement = placement_refusal(node, sandbox)) != nil -> placement
      grant != :allowed -> grant
      memory_fits?(node, reserved, charge) -> :room
      not elastic?(node) -> :no_memory
      node.elastic.memory_ceiling_bytes - @daemon_reserve_bytes - reserved < charge -> :ceiling
      true -> :growth_failed
    end
  end

  defp placement_refusal(node, sandbox) do
    cond do
      not disk_room?(node, sandbox) -> :disk_budget
      not disk_space?(node, sandbox) -> :disk_space
      not cpu_room?(node, sandbox) -> :cpu
      true -> nil
    end
  end

  # Preferred nodes go first: their room, then a growth of their carve-out
  # (waiting no longer than an admission does, since a preferred node saves
  # seconds), and only then another node's room. Pausing idle sandboxes still
  # goes where it frees the most, and the last growth tries preferred nodes
  # first again.
  defp place_on(candidates, sandbox, prefer \\ []) do
    charge = charge_bytes(sandbox)
    ranked = pack(candidates)
    {preferred, others} = Enum.split_with(ranked, &(&1.name in prefer))

    reserve = fn node ->
      reserve(node, charge, fn -> set_node(sandbox, node.name) end, fn ->
        disk_room?(node, sandbox) and cpu_room?(node, sandbox)
      end)
    end

    result =
      with nil <- reserve_first(preferred, reserve),
           nil <- grow_preferred(preferred, charge, reserve),
           nil <- reserve_first(others, reserve) do
        case place_by_reclaiming(ranked, charge, reserve) do
          {:ok, node_name} -> {:ok, node_name, :reclaimed}
          {:error, :no_capacity} -> place_by_growing(ranked, charge, reserve, prefer)
        end
      end

    if prefer != [] do
      Logger.info("sandboxes: placed a sandbox with checkout nodes",
        sandbox_id: sandbox.id,
        node:
          case result do
            {:ok, node_name, _path} -> node_name
            _ -> nil
          end,
        checkout_nodes: Enum.join(prefer, " "),
        placement_path:
          case result do
            {:ok, _node_name, path} -> path
            _ -> :none
          end
      )
    end

    with {:ok, node_name, _path} <- result, do: {:ok, node_name}
  end

  defp reserve_first(nodes, reserve) do
    case Enum.find(nodes, &(reserve.(&1) == :ok)) do
      %{name: node_name} -> {:ok, node_name, :room}
      nil -> nil
    end
  end

  defp grow_preferred([], _charge, _reserve), do: nil

  defp grow_preferred(preferred, charge, reserve) do
    with {:ok, grown} <- grow_somewhere(preferred, charge, wait_ms(:admission_grow_wait_ms), :reported),
         :ok <- reserve.(grown) do
      {:ok, grown.name, :grown}
    else
      _no_room -> nil
    end
  end

  defp place_by_reclaiming(ranked, charge, reserve) do
    with {:ok, node} <- most_reclaimable(ranked, charge),
         :ok <- reclaim(node, charge),
         :ok <- reserve.(node) do
      {:ok, node.name}
    else
      _no_room -> {:error, :no_capacity}
    end
  end

  defp place_by_growing(ranked, charge, reserve, prefer) do
    with {:ok, grown} <- grow_somewhere(ranked, charge, wait_ms(:grow_wait_ms), :reported, prefer),
         :ok <- reserve.(grown) do
      {:ok, grown.name, :grown}
    else
      _no_room -> {:error, :no_capacity}
    end
  end

  @doc """
  Reserves memory on the sandbox's own node for a resume and marks the
  row `resuming`. A node that is not connected is not budgeted here; the
  resume command reports it. Pauses idle sandboxes on the node when the
  paused one does not fit as is, and grows an elastic node's carve-out
  when that is not enough.
  """
  def admit(%Sandbox{platform: :darwin} = sandbox), do: MacosCapacity.admit(sandbox)

  def admit(%Sandbox{state: :paused, node_name: node_name} = sandbox) when is_binary(node_name) do
    with :ok <- Concurrency.check(sandbox.account_id, sandbox) do
      do_admit(sandbox)
    end
  end

  defp do_admit(%Sandbox{node_name: node_name} = sandbox) do
    charge = charge_bytes(sandbox)

    case Nodes.await_lookup(node_name) do
      {:ok, _pid, info} ->
        node = Map.put(info, :name, node_name)

        reserve = fn node ->
          reserve(node, charge, fn -> mark_resuming(sandbox) end, fn -> resume_disk_room?(node, sandbox) end)
        end

        with true <- disk_space?(node, sandbox),
             true <- resume_disk_room?(node, sandbox),
             :no_capacity <- reserve.(node),
             {:error, :no_capacity} <- reclaim_and_reserve(node, charge, reserve),
             {:ok, grown} <- grow_for_resume(node, charge),
             :ok <- reserve.(grown) do
          {:ok, Repo.reload!(sandbox)}
        else
          :ok -> {:ok, Repo.reload!(sandbox)}
          {:error, reason} when reason in [:sandbox_concurrency_limit, :sandbox_account_busy] -> {:error, reason}
          _no_room -> {:error, :no_capacity}
        end

      {:error, :not_connected} ->
        Repo.transaction(fn -> mark_resuming(sandbox) end)
    end
  end

  # A paused sandbox resumes only on its own node, and a refusal archives it:
  # a restore from the archive takes tens of seconds where a resume takes a
  # fraction of one. So a growth the kubelet defers is waited out while the
  # grant still offers its memory, which it does only while idle runners on
  # the node can be retired for it (the runners controller retires them on
  # the deferral, and a Kata teardown takes up to 40 s). A revoked, expired or
  # shrunk grant ends the wait at once: nothing on the node is freeing room.
  defp grow_for_resume(node, charge) do
    case grow(node, charge, wait_ms(:grow_wait_ms)) do
      {:deferred, limit} -> await_deferred_growth(node, limit, wait_ms(:resume_deferral_wait_ms))
      result -> result
    end
  end

  defp await_deferred_growth(node, limit, wait_ms) do
    Nodes.await(
      fn ->
        if allocation_outcome(Repo.get(SandboxNode, node.name), node, limit) == :allowed do
          case await_growth(node, limit, 0, :reported) do
            {:ok, _grown} = grown -> grown
            not_yet -> {:retry, not_yet}
          end
        else
          {:deferred, limit}
        end
      end,
      wait_ms
    )
  end

  @doc """
  Whether a work item for the session could be placed right now, without
  reserving anything: the poller leaves an item queued when its sandbox
  would not fit anywhere, so the queue rather than a forced stop holds it
  until a pause frees memory. When only a growth of an elastic node's
  carve-out would fit it, the growth is asked for here and the item is
  admissible if the kubelet applies it within a couple of seconds on one
  of the nodes tried, those in `prefer:` first; a growth the kubelet defers
  on the last one stays asked for, and the item, left queued, fits once
  that node has room. Sessions whose sandbox already holds memory and
  environments with no connected node at all are admissible; the latter
  fail on dispatch as before.

  Returns `:ok`, or `{:error, reason}` saying why not for the logs: the
  account's quota, `{node, reason}` for the node of the session's sandbox,
  or `:no_room` for a new one. macOS gives per-host reasons
  (`Tuist.Sandboxes.MacosCapacity.admission/2`).
  """
  def admission(agent_environment, session_id, opts \\ [])

  def admission(%AgentEnvironment{platform: :darwin} = environment, session_id, _opts),
    do: MacosCapacity.admission(environment, session_id)

  def admission(%AgentEnvironment{} = agent_environment, session_id, opts) when is_binary(session_id) do
    case Sandboxes.get_sandbox_for_session(agent_environment.id, session_id) do
      %Sandbox{state: state, node_name: name} when state in @charged_states ->
        charged_admission(name)

      %Sandbox{state: :paused, node_name: node_name} = sandbox when is_binary(node_name) ->
        with :ok <- quota(sandbox.account_id, sandbox) do
          if resumable?(sandbox), do: :ok, else: {:error, {node_name, :no_room}}
        end

      _new ->
        with :ok <- quota(agent_environment.account_id, agent_environment) do
          if placeable?(agent_environment, Keyword.get(opts, :prefer, [])), do: :ok, else: {:error, :no_room}
        end
    end
  end

  @doc "Whether `admission/2` lets the session's work item through."
  def admissible?(agent_environment, session_id, opts \\ []), do: admission(agent_environment, session_id, opts) == :ok

  @doc "The account's CPU and memory quota check for a work item's sandbox."
  def quota(account_id, requested), do: Concurrency.check(account_id, requested)

  defp charged_admission(name) do
    case Nodes.lookup(name) do
      {:ok, _pid, info} ->
        if allocation_allows?(Map.put(info, :name, name), reserved_bytes(name) + @daemon_reserve_bytes),
          do: :ok,
          else: {:error, {name, :not_allocated}}

      _ ->
        if shared_node?(name), do: {:error, {name, :not_connected}}, else: :ok
    end
  end

  defp resumable?(%Sandbox{node_name: node_name} = sandbox) do
    case Nodes.lookup(node_name) do
      {:ok, _pid, info} ->
        node = Map.put(info, :name, node_name)
        resume_disk_room?(node, sandbox) and (memory_room?(node, sandbox) or grown_in_time?(node, sandbox))

      {:error, :not_connected} ->
        true
    end
  end

  defp placeable?(agent_environment, prefer) do
    case ready_nodes(agent_environment.template) do
      [] ->
        true

      nodes ->
        with_disk = Enum.filter(nodes, &disk_room?(&1, agent_environment))
        if with_disk == [], do: nodes |> Enum.map(& &1.name) |> Archives.make_node_room()
        Enum.any?(with_disk, &memory_room?(&1, agent_environment)) or grown_in_time?(with_disk, agent_environment, prefer)
    end
  end

  # The admission check only needs to know the kubelet applied the growth;
  # the placement that follows waits for the daemon to report it.
  defp grown_in_time?(nodes, sized, prefer) when is_list(nodes) do
    with_space = Enum.filter(nodes, &disk_space?(&1, sized))
    result = grow_somewhere(with_space, charge_bytes(sized), wait_ms(:admission_grow_wait_ms), :applied, prefer)
    match?({:ok, _node}, result)
  end

  defp grown_in_time?(node, sized) do
    disk_space?(node, sized) and
      match?({:ok, _node}, grow(node, charge_bytes(sized), wait_ms(:admission_grow_wait_ms), :applied))
  end

  # Tries the elastic nodes that could hold the charge, those in `prefer`
  # first and then the most observed free memory first, and moves on from
  # one whose growth the kubelet defers (the node has no memory no Pod
  # requests), releasing that growth. The
  # last node's deferred growth stays asked for, so the runners controller
  # frees room there and the next attempt fits.
  defp grow_somewhere(nodes, charge, wait_ms, until, prefer \\ []) do
    deadline = System.monotonic_time(:millisecond) + wait_ms
    {preferred, others} = nodes |> growable(charge) |> Enum.split_with(&(&1.name in prefer))
    try_growing(preferred ++ others, charge, deadline, until)
  end

  defp try_growing([], _charge, _deadline, _until), do: {:error, :no_capacity}

  defp try_growing([node | rest], charge, deadline, until) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case grow(node, charge, remaining, until) do
      {:deferred, limit} when rest != [] ->
        release_growth(node, limit)
        try_growing(rest, charge, deadline, until)

      result ->
        result
    end
  end

  @doc """
  Grows an elastic node's carve-out so `charge` more bytes fit on top of
  what its sandboxes hold, rounded up to whole GiB and capped at the
  node's ceiling, and waits up to `wait_ms` for it to land: until the
  daemon reports the new limit (`until: :reported`, what a placement
  budgets against) or until the kubelet has applied it (`:applied`).
  Returns `{:ok, node}` with the node's latest report, `{:deferred, limit}`
  when the kubelet deferred it for lack of room on the node,
  `{:pending, limit}` when it has not landed in time, or `{:error, reason}`
  when the ceiling cannot hold it or the resize failed. A deferred or
  pending growth stays asked for.
  """
  def grow(%{name: _node_name} = node, charge, wait_ms, until \\ :reported)
      when is_integer(charge) and is_integer(wait_ms) and until in [:reported, :applied] do
    timed(node.name, :grow, fn -> do_grow(node, charge, wait_ms, until) end)
  end

  defp do_grow(node, charge, wait_ms, until) do
    if elastic?(node) do
      with {:ok, limit} <- ask_for_growth(node, charge),
           :ok <- resize(node, limit) do
        await_growth(node, limit, wait_ms, until)
      end
    else
      {:error, :no_capacity}
    end
  end

  defp timed(node_name, operation, fun) do
    started = System.monotonic_time()
    result = fun.()

    outcome =
      case result do
        {:error, reason} when is_atom(reason) -> reason
        {status, _} -> status
        status when is_atom(status) -> status
      end

    :telemetry.execute([:tuist, :sandboxes, :capacity], %{duration: System.monotonic_time() - started}, %{
      node: node_name,
      operation: operation,
      outcome: outcome
    })

    result
  end

  # Gives a deferred growth back: the size asked for returns to what the
  # Pod holds, so the scheduler stops counting the growth against the node.
  defp release_growth(%{name: node_name, elastic: %{pod_name: pod_name}} = node, limit) do
    fn ->
      lock(node_name)

      held =
        max(
          reported_limit(node) || node.elastic.memory_floor_bytes,
          round_up_to_step(reserved_bytes(node_name) + @daemon_reserve_bytes)
        )

      case Repo.get(SandboxNode, node_name) do
        %SandboxNode{pod_name: ^pod_name, memory_limit_bytes: ^limit} = row when held < limit ->
          row |> SandboxNode.changeset(%{memory_limit_bytes: held}) |> Repo.update!()
          held

        _changed_since ->
          Repo.rollback(:unchanged)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, held} ->
        Logger.info("sandboxes: released a deferred carve-out growth", node: node_name, memory_bytes: held)
        resize(node, held)

      {:error, :unchanged} ->
        :ok
    end
  end

  defp ask_for_growth(%{name: node_name, elastic: elastic} = node, charge) do
    fn ->
      lock(node_name)
      needed = reserved_bytes(node_name) + charge + @daemon_reserve_bytes

      if needed > elastic.memory_ceiling_bytes or not allocation_allows?(node, round_up_to_step(needed)),
        do: Repo.rollback(:no_capacity)

      current = max(asked_limit(node) || 0, reported_limit(node) || 0)
      limit = needed |> round_up_to_step() |> min(elastic.memory_ceiling_bytes) |> max(current)

      %SandboxNode{}
      |> SandboxNode.changeset(%{
        name: node_name,
        pod_name: elastic.pod_name,
        memory_limit_bytes: limit,
        grown_at: DateTime.utc_now(:second)
      })
      |> Repo.insert!(
        on_conflict: {:replace, [:pod_name, :memory_limit_bytes, :grown_at, :updated_at]},
        conflict_target: :name
      )

      limit
    end
    |> Repo.transaction()
    |> case do
      {:ok, limit} -> {:ok, limit}
      {:error, :no_capacity} -> {:error, :no_capacity}
    end
  end

  # The daemon reports a new limit within a second or two; the Pod's status
  # says sooner whether the kubelet applied the resize or deferred it.
  defp await_growth(%{name: node_name, elastic: %{pod_name: pod_name}} = node, limit, wait_ms, until) do
    Nodes.await(
      fn ->
        latest =
          case Nodes.lookup(node_name) do
            {:ok, _pid, info} -> Map.put(info, :name, node_name)
            {:error, :not_connected} -> node
          end

        if (reported_limit(latest) || 0) >= limit do
          {:ok, latest}
        else
          case resize_status(pod_name, limit) do
            :applied when until == :applied -> {:ok, latest}
            :deferred -> {:deferred, limit}
            _waiting -> {:retry, {:pending, limit}}
          end
        end
      end,
      wait_ms
    )
  end

  defp resize_status(pod_name, limit) do
    case KubernetesClient.get_pod(Environment.sandboxes_namespace(), pod_name) do
      {:ok, %{"status" => status} = pod} when is_map(status) ->
        cond do
          applied_memory(status, KubernetesClient.sandbox_vm_container(pod)) >= limit -> :applied
          resize_deferred?(status) -> :deferred
          true -> :waiting
        end

      _unknown ->
        :waiting
    end
  end

  defp applied_memory(status, container) do
    status
    |> Map.get("containerStatuses", [])
    |> Enum.find(%{}, &(&1["name"] == container))
    |> get_in(["resources", "limits", "memory"])
    |> memory_quantity()
  end

  defp resize_deferred?(status) do
    status
    |> Map.get("conditions", [])
    |> Enum.any?(
      &(&1["type"] == "PodResizePending" and &1["status"] == "True" and &1["reason"] in ["Deferred", "Infeasible"])
    )
  end

  @quantity_multipliers %{
    "" => 1,
    "k" => 1000,
    "M" => 1000 ** 2,
    "G" => 1000 ** 3,
    "T" => 1000 ** 4,
    "Ki" => 1024,
    "Mi" => 1024 ** 2,
    "Gi" => 1024 ** 3,
    "Ti" => 1024 ** 4
  }

  defp memory_quantity(quantity) when is_binary(quantity) do
    case Regex.run(~r/^(\d+)(Ki|Mi|Gi|Ti|k|M|G|T)?$/, quantity) do
      [_all, digits] -> String.to_integer(digits)
      [_all, digits, suffix] -> String.to_integer(digits) * Map.fetch!(@quantity_multipliers, suffix)
      nil -> 0
    end
  end

  defp memory_quantity(_quantity), do: 0

  defp resize(%{name: node_name} = node, limit) do
    # Serialize the API write as well as the desired-state update. A delayed
    # shrink must never overwrite a newer growth (or vice versa).
    fn ->
      lock(node_name)

      apply_resize(node, Repo.get(SandboxNode, node_name), limit)
    end
    |> Repo.transaction()
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_resize(
         %{name: node_name, elastic: %{pod_name: pod_name}} = node,
         %SandboxNode{pod_name: pod_name, memory_limit_bytes: limit},
         limit
       ) do
    if limit > (reported_limit(node) || 0) and not allocation_allows?(node, limit),
      do: Repo.rollback(:no_capacity)

    case resize_pod(node_name, pod_name, limit) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp apply_resize(_node, _row, _limit), do: Repo.rollback(:superseded)

  defp resize_pod(node_name, pod_name, limit) do
    case KubernetesClient.resize_sandbox_daemon_memory(Environment.sandboxes_namespace(), pod_name, limit) do
      {:ok, _pod} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: resizing a node's carve-out failed",
          node: node_name,
          pod: pod_name,
          memory_bytes: limit,
          reason: inspect(reason)
        )

        {:error, :resize_failed}
    end
  end

  @doc """
  Shrinks every grown carve-out back toward what its running sandboxes
  hold, never below the floor, after the bounded provisioning interval,
  and retries a shrink the kubelet has not applied yet. Run
  every minute by `Tuist.Sandboxes.Workers.ShrinkCarveOutsWorker`.
  """
  def shrink_carve_outs do
    Nodes.connected_nodes()
    |> Enum.filter(&elastic?/1)
    |> Enum.map(&{&1.name, shrink(&1)})
  end

  @doc """
  Lowers the size asked for first, under the node's lock, so no placement
  counts on the memory being released; then asks the daemon to reclaim
  page cache below the new limit (the kubelet will not lower a limit below
  current usage) and resizes the Pod. A shrink below a growth the kubelet
  deferred cancels it.
  """
  def shrink(%{name: node_name} = node, urgent \\ false) do
    case lower_limit(node, urgent) do
      {:ok, limit} ->
        reclaim_cgroup(node_name, limit)

        with :ok <- resize(node, limit) do
          Logger.info("sandboxes: shrank a node's carve-out", node: node_name, memory_bytes: limit)
          {:ok, limit}
        end

      :unchanged ->
        :unchanged
    end
  end

  defp lower_limit(%{name: node_name, elastic: elastic} = node, urgent) do
    fn ->
      lock(node_name)

      with %SandboxNode{pod_name: pod_name} = row <- Repo.get(SandboxNode, node_name),
           true <- pod_name == elastic.pod_name,
           row = at_least_floor(row, elastic.memory_floor_bytes),
           false <- (held?(row) or executing?(node)) and not urgent do
        needed = reserved_bytes(node_name) + held_paused_bytes(node_name, urgent) + @daemon_reserve_bytes

        target =
          needed
          |> round_up_to_step()
          |> max(elastic.memory_floor_bytes)
          |> max(warm_bytes(row, node))
          |> min(row.memory_limit_bytes)

        cond do
          target < row.memory_limit_bytes ->
            row |> SandboxNode.changeset(%{memory_limit_bytes: target}) |> Repo.update!()
            target

          (reported_limit(node) || 0) > row.memory_limit_bytes ->
            row.memory_limit_bytes

          true ->
            Repo.rollback(:unchanged)
        end
      else
        _not_shrinkable -> Repo.rollback(:unchanged)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, limit} -> {:ok, limit}
      {:error, :unchanged} -> :unchanged
    end
  end

  defp at_least_floor(%SandboxNode{memory_limit_bytes: limit} = row, floor) when limit < floor,
    do: row |> SandboxNode.changeset(%{memory_limit_bytes: floor}) |> Repo.update!()

  defp at_least_floor(row, _floor), do: row

  # Agent sandboxes on the node that paused within the hold: most resume
  # for their session's next turn, so the carve-out keeps their memory and
  # CPU guarantee for them.
  defp recently_paused(node_name) do
    Repo.all(
      from s in Sandbox,
        where: s.node_name == ^node_name and s.purpose == :agent and s.state == :paused,
        where: s.paused_at > ago(@shrink_hold_seconds, "second")
    )
  end

  defp held_paused_bytes(_node_name, true = _urgent), do: 0

  defp held_paused_bytes(node_name, false = _urgent),
    do: node_name |> recently_paused() |> Enum.map(&charge_bytes/1) |> Enum.sum()

  defp held?(%SandboxNode{grown_at: nil}), do: false

  defp held?(%SandboxNode{grown_at: grown_at}) do
    DateTime.diff(DateTime.utc_now(), grown_at, :second) < @shrink_hold_seconds
  end

  # An execution daemon runs one VM per action, so what its VMs hold dips
  # between actions while a build still has more queued. Shrinking to that
  # dip makes the next VMs wait for a growth, and larger VMs wait longest. Its
  # carve-out holds while a VM placed within the time a scheduler holds a
  # build's warm peak is still on it; warm VMs keep that true between actions.
  # CI pressure (`urgent`) still shrinks it at once.
  defp executing?(%{name: node_name} = node) do
    execution_daemon?(node) and
      Repo.exists?(
        from s in Sandbox,
          where:
            s.node_name == ^node_name and s.purpose == :remote_execution and
              s.inserted_at > ago(@execution_hold_seconds, "second")
      )
  end

  defp reclaim_cgroup(node_name, limit) do
    target = max(limit - @shrink_reclaim_margin_bytes, 0)

    case Nodes.call(node_name, "reclaim", %{target_bytes: target}, timeout: 10_000) do
      {:ok, _cgroup} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: could not reclaim a node's page cache before a shrink",
          node: node_name,
          reason: inspect(reason)
        )
    end
  end

  @doc """
  Whether the node's daemon CPU request can be resized: its daemon names its
  Pod and reports a CPU floor, and the CPU ceiling (the server's, else the
  one the daemon reports) is above it.
  """
  def cpu_elastic?(%{elastic: %{pod_name: pod_name, cpu_floor_milli: floor}} = node)
      when is_binary(pod_name) and pod_name != "" and is_integer(floor) and floor > 0 do
    case cpu_ceiling_milli(node) do
      ceiling when is_integer(ceiling) -> ceiling > floor
      nil -> false
    end
  end

  def cpu_elastic?(_node), do: false

  # The server's own ceiling (`Environment.sandbox_cpu_ceiling_milli/0`,
  # from the chart) wins over the one the daemon reports, so raising it rolls
  # only the server: a daemon restart pauses every sandbox on its node.
  defp cpu_ceiling_milli(%{elastic: elastic}) do
    Environment.sandbox_cpu_ceiling_milli() || Map.get(elastic, :cpu_ceiling_milli)
  end

  @doc "Moves every connected node's daemon CPU request to its sandboxes' guarantee (`sync_cpu/1`)."
  def sync_cpus do
    Nodes.connected_nodes()
    |> Enum.filter(&cpu_elastic?/1)
    |> Enum.map(&{&1.name, sync_cpu(&1)})
  end

  @doc """
  Moves the node's daemon CPU request to its floor plus the guaranteed CPU
  (`Sandbox.guaranteed_cpu_milli/1`) of the agent sandboxes it charges, up to its
  ceiling. Guests have no CPU limit; the request keeps that much of the
  node's CPU out of exclusive-CPU runners and weighs the guests against the
  shared pool's other Pods when it is contended.

  A shrink always goes ahead. A growth goes, from the CPU the kubelet has
  allocated the daemon, into CPU the runners-controller's fresh grant
  reports no Pod requests or idle warm runners hold, the way a memory
  growth takes their memory: the kubelet defers the part idle runners hold
  until the controller retires them, and runners with a job are never
  touched. A deferred resize holds up the Pod's memory growths with it, so
  a request the next grant cannot fund (a runner claimed a job first) is
  lowered to what fits. A node without a grant row is not shared with CI
  and grows freely. What does not fit now is retried on the next sync, run
  on every grant (`reconcile_allocation/1`) and every minute; a request is
  only cached once the kubelet has applied it.
  """
  def sync_cpu(%{name: node_name} = node) do
    if cpu_elastic?(node), do: timed(node_name, :cpu, fn -> do_sync_cpu(node) end), else: :unchanged
  end

  defp do_sync_cpu(%{name: node_name, elastic: %{pod_name: pod_name}} = node) do
    fn ->
      lock(node_name)
      desired = desired_cpu_milli(node)
      cache_key = ["sandbox_daemon_cpu", node_name, pod_name]

      if KeyValueStore.get(cache_key) == desired,
        do: :unchanged,
        else: resize_cpu(node, desired, cache_key)
    end
    |> Repo.transaction()
    |> case do
      {:ok, result} ->
        result

      {:error, reason} ->
        Logger.warning("sandboxes: resizing a node's daemon CPU request failed",
          node: node_name,
          pod: pod_name,
          reason: inspect(reason)
        )

        {:error, :resize_failed}
    end
  end

  # Under the node's lock, like a memory resize, so a delayed write cannot
  # overwrite a newer one; the PATCH is fenced at the Pod version it read.
  defp resize_cpu(%{name: node_name, elastic: %{pod_name: pod_name}} = node, desired, cache_key) do
    room = cpu_room(Repo.get(SandboxNode, node_name), node)

    case KubernetesClient.resize_sandbox_daemon_cpu(
           Environment.sandboxes_namespace(),
           pod_name,
           &cpu_target(desired, &1, room)
         ) do
      {:ok, milli, applied?} ->
        if applied?, do: KeyValueStore.put(cache_key, milli, ttl: @cpu_request_cache_ttl)
        {:ok, milli}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # A recently paused sandbox keeps its guarantee, like its memory
  # (`recently_paused/1`), unless CI is reclaiming the node.
  defp desired_cpu_milli(%{name: node_name, elastic: %{cpu_floor_milli: floor}} = node) do
    held = if ci_reclaim?(node_name), do: [], else: recently_paused(node_name)
    min(floor + guaranteed_cpu_milli(node_name, held), cpu_ceiling_milli(node))
  end

  defp guaranteed_cpu_milli(node_name, held) do
    from(s in Sandbox, where: s.node_name == ^node_name and s.purpose == :agent and s.state in ^@charged_states)
    |> Repo.all()
    |> Enum.concat(held)
    |> Enum.map(&Sandbox.guaranteed_cpu_milli/1)
    |> Enum.sum()
  end

  @doc """
  Whether the node can hold the sandbox's guarantee. A Linux sandbox needs,
  on a node whose daemon runs each VM in its own cgroup (hello
  `cpu_guarantees`) and can resize its CPU request, room for its guarantee
  under the daemon's CPU ceiling and, on a node shared with CI, that much
  CPU no other Pod requests or idle warm runners hold in the fresh grant, so
  `sync_cpu/1` can raise the request. A node without both, or whose controller reports no
  free CPU, still takes sandboxes guaranteed only their memory's CPU, as
  before guarantees were held, but not a picked guarantee. macOS sandboxes and
  remote execution VMs are placed on their shape. Run under the node's lock
  when placing, like the disk check.
  """
  def cpu_room?(node, sandbox) do
    cond do
      not Sandbox.burst?(sandbox) ->
        true

      Map.get(node, :cpu_guarantees) == true and cpu_elastic?(node) ->
        guarantee = Sandbox.guaranteed_cpu_milli(sandbox)

        node.elastic.cpu_floor_milli + guaranteed_cpu_milli(node.name, []) + guarantee <= cpu_ceiling_milli(node) and
          case cpu_room(Repo.get(SandboxNode, node.name), node) do
            :unbounded -> true
            :unreported -> not Sandbox.picked_guarantee?(sandbox)
            room -> guarantee <= room
          end

      true ->
        not Sandbox.picked_guarantee?(sandbox)
    end
  end

  defp cpu_target(desired, current, _room) when desired <= current, do: desired
  defp cpu_target(desired, _current, :unbounded), do: desired
  defp cpu_target(_desired, current, :unreported), do: current
  defp cpu_target(desired, current, room), do: min(desired, current + room)

  defp cpu_room(nil, _node), do: :unbounded
  # A controller from before grants reported free CPU.
  defp cpu_room(%SandboxNode{allocation_cpu_free_milli: nil}, _node), do: :unreported

  defp cpu_room(
         %SandboxNode{
           pod_name: pod,
           allocation_reclaim: false,
           allocation_observed_at: %DateTime{} = at,
           allocation_cpu_free_milli: free,
           allocation_cpu_reclaimable_milli: reclaimable
         },
         %{elastic: %{pod_name: pod}}
       )
       when is_integer(free) do
    if fresh_allocation?(at), do: free + (reclaimable || 0), else: 0
  end

  defp cpu_room(%SandboxNode{}, _node), do: 0

  defp wait_ms(:grow_wait_ms),
    do: :tuist |> Application.get_env(__MODULE__, []) |> Keyword.get(:grow_wait_ms, @grow_wait_ms)

  defp wait_ms(:resume_deferral_wait_ms) do
    :tuist
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:resume_deferral_wait_ms, @resume_deferral_wait_ms)
  end

  defp wait_ms(:admission_grow_wait_ms) do
    :tuist |> Application.get_env(__MODULE__, []) |> Keyword.get(:admission_grow_wait_ms, @admission_grow_wait_ms)
  end

  defp round_up_to_step(bytes), do: div(bytes + @carve_out_step_bytes - 1, @carve_out_step_bytes) * @carve_out_step_bytes

  defp growable(nodes, charge) do
    nodes
    |> Enum.filter(&elastic?/1)
    |> Enum.map(&{&1, &1.elastic.memory_ceiling_bytes - @daemon_reserve_bytes - reserved_bytes(&1.name)})
    |> Enum.filter(fn {node, room} ->
      room >= charge and
        allocation_allows?(node, round_up_to_step(reserved_bytes(node.name) + charge + @daemon_reserve_bytes))
    end)
    |> Enum.sort_by(fn {node, _room} ->
      row = Repo.get(SandboxNode, node.name)
      {-(row.allocation_free_bytes || 0), -(row.allocation_memory_bytes || 0), node.name}
    end)
    |> Enum.map(fn {node, _room} -> node end)
  end

  defp reclaim_and_reserve(node, charge, reserve) do
    with :ok <- reclaim(node, charge),
         :ok <- reserve.(node) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _no_room -> {:error, :no_capacity}
    end
  end

  # Memory and room on the filesystem for the sandbox's next pause; a
  # resume also takes its disk ceiling back (`resume_disk_room?/2`).
  defp memory_room?(node, sandbox) do
    allocation_allows?(node, reserved_bytes(node.name) + charge_bytes(sandbox) + @daemon_reserve_bytes) and
      disk_space?(node, sandbox) and
      case free_bytes(node) do
        :unbounded -> true
        free -> free + reclaimable_bytes(node.name) >= charge_bytes(sandbox)
      end
  end

  # Ranking cannot change a singleton; reserve/4 still checks its capacity under
  # the node lock before writing the placement.
  defp rank([]), do: []
  defp rank([node]), do: [node]

  defp rank(nodes) do
    nodes
    |> Enum.map(&{&1, free_bytes(&1)})
    |> Enum.sort_by(fn {_node, free} -> if free == :unbounded, do: :infinity, else: free end, :desc)
    |> Enum.map(fn {node, _free} -> node end)
  end

  # Agent sandboxes are packed onto the nodes that already run the most of
  # them, ties going to the node whose grant has the most CPU no runner
  # requests. Mostly idle sandboxes burst into each other's idle cores
  # rather than beside CI jobs that keep theirs busy, and the nodes left
  # whole take runners without a daemon carving them up. Whether a node fits
  # is still decided under its lock when reserving.
  defp pack(nodes) do
    Enum.sort_by(nodes, fn %{name: node_name} ->
      cpu_free =
        case Repo.get(SandboxNode, node_name) do
          %SandboxNode{allocation_cpu_free_milli: free} when is_integer(free) -> free
          _no_grant -> 0
        end

      {-reserved_bytes(node_name), -cpu_free, node_name}
    end)
  end

  defp most_reclaimable(nodes, charge) do
    nodes
    |> Enum.map(fn node -> {node, headroom(node)} end)
    |> Enum.filter(fn {_node, headroom} -> headroom >= charge end)
    |> Enum.max_by(fn {_node, headroom} -> headroom end, fn -> nil end)
    |> case do
      {node, _headroom} -> {:ok, node}
      nil -> {:error, :no_capacity}
    end
  end

  defp headroom(node) do
    case free_bytes(node) do
      :unbounded -> :infinity
      free -> free + reclaimable_bytes(node.name)
    end
  end

  # `disk_fits` runs under the node's lock too, so two placements racing
  # for the last of a node's disk budget see each other's rows. Without
  # `grant?`, memory the Pod holds is used whatever the grant says.
  defp reserve(node, charge, apply, disk_fits, grant? \\ true) do
    fn ->
      lock(node.name)
      reserved = reserved_bytes(node.name)

      if memory_fits?(node, reserved, charge) and
           (not grant? or allocation_allows?(node, reserved + charge + @daemon_reserve_bytes)) and
           disk_fits.(), do: apply.(), else: Repo.rollback(:no_capacity)
    end
    |> Repo.transaction()
    |> case do
      {:ok, _applied} -> :ok
      {:error, :no_capacity} -> :no_capacity
      {:error, reason} -> {:error, reason}
    end
  end

  defp memory_fits?(node, reserved, charge) do
    case memory_budget_bytes(node) do
      :unbounded -> true
      budget -> budget - reserved >= charge
    end
  end

  defp lock(node_name) do
    Repo.query!("SELECT pg_advisory_xact_lock($1::integer, hashtext($2))", [
      @advisory_lock_namespace,
      host_name(node_name)
    ])
  end

  defp reclaim(node, charge) do
    needed =
      case free_bytes(node) do
        :unbounded -> 0
        free -> charge - free
      end

    freed =
      node.name
      |> reclaimable()
      |> Enum.reduce_while(0, fn sandbox, freed ->
        if freed >= needed do
          {:halt, freed}
        else
          {:cont, freed + reclaim_one(node, sandbox)}
        end
      end)

    if freed >= needed, do: :ok, else: {:error, :no_capacity}
  end

  # The reclaim may run under the lock of the sandbox it makes room for,
  # so it never waits on another sandbox's lock: one that is busy is not
  # idle anyway.
  defp reclaim_one(node, sandbox) do
    case Sandboxes.pause_idle(sandbox.id, wait: false) do
      {:ok, %Sandbox{state: :paused}} ->
        Logger.info("sandboxes: paused an idle sandbox to make room",
          sandbox_id: sandbox.id,
          node: node.name,
          freed_bytes: charge_bytes(sandbox)
        )

        charge_bytes(sandbox)

      {:ok, _skipped} ->
        0

      {:error, :locked} ->
        0

      {:error, reason} ->
        Logger.warning("sandboxes: could not pause an idle sandbox for room",
          sandbox_id: sandbox.id,
          node: node.name,
          reason: inspect(reason)
        )

        0
    end
  end

  defp set_node(sandbox, node_name) do
    sandbox |> Sandbox.update_changeset(%{node_name: node_name}) |> Repo.update!()
  end

  defp mark_resuming(sandbox) do
    case Concurrency.admit(sandbox.account_id, sandbox, fn ->
           sandbox |> Sandbox.update_changeset(%{state: :resuming}) |> Repo.update()
         end) do
      {:ok, resumed} -> resumed
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end
