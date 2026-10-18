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
  (creating, running, resuming or paused) and of every errored one whose
  jail the node still reports, so sandboxes growing into their images
  later can never overrun the budget together. A pause also writes a full memory image
  beside the previous one, so the filesystem must have that much free
  plus headroom at placement and at resume.

  Reservations are serialized per node with a transaction-scoped
  advisory lock. The reservation is the row itself: `node_name` set on a
  creating sandbox, or the `resuming` state on a paused one, both of
  which the reserved sums count.

  A node whose daemon reports a memory ceiling above its floor has an
  elastic carve-out: the daemon's Pod starts at the floor, and when
  nothing fits even after pausing idle sandboxes the Pod's memory is grown
  in place, in whole GiB, up to the ceiling. The kubelet applies a growth
  that fits the node at once and defers one that does not until room
  frees, which the runners controller provides by retiring idle warm
  runners on that node; the scheduler counts the requested size either
  way, so runner Pods cannot take room a growth is waiting for. The size
  the server asked for is a `Tuist.Sandboxes.SandboxNode` row, and
  placements budget against the smaller of it and the limit the node
  reports, so a growth is used only once the daemon reports it and a
  shrink stops placements before the kubelet applies it. Grown carve-outs
  shrink back toward what their running sandboxes hold a while after
  their last growth (`shrink_carve_outs/0`), which hands the memory back
  to the runner pools.
  """

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: KubernetesClient
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxNode

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
  # A grown carve-out shrinks no sooner than this after its last growth, so
  # a burst of turns does not resize the Pod back and forth.
  @shrink_hold_seconds 180
  # How long a placement or resume waits for a growth to be reported, and
  # how long the poller's admission check does before it leaves a work item
  # queued: it must still acknowledge within the queue's five seconds.
  @grow_wait_ms 15_000
  @admission_grow_wait_ms 2_500
  # Below the new limit, so the kubelet's check that usage fits passes.
  @shrink_reclaim_margin_bytes 256 * @mib

  def charge_bytes(%{memory_mb: memory_mb}) when is_integer(memory_mb), do: memory_mb * @mib + @vm_overhead_bytes

  def pause_bytes(%{memory_mb: memory_mb}) when is_integer(memory_mb), do: memory_mb * @mib

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
  defp asked_limit(%{name: name, elastic: %{pod_name: pod_name}} = node) when is_binary(name) do
    if elastic?(node) do
      case Repo.get(SandboxNode, name) do
        %SandboxNode{pod_name: ^pod_name, memory_limit_bytes: limit} -> limit
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
          where: s.node_name == ^node_name and s.state in ^@charged_states,
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
        where: s.node_name == ^node_name and s.state == :running and is_nil(s.residency_work_id),
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
  (creating, running, resuming or paused) and of the errored ones whose
  jail it still reports. Rows rather than the report decide, because the
  report lags by up to its interval: a create in flight is not in it yet,
  and a sandbox deleted a moment ago still is.
  """
  def reserved_disk_bytes(%{name: node_name} = node) do
    reported_ids =
      for %{id: id} <- Map.get(node, :sandboxes, []), {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid

    from(s in Sandbox,
      where:
        s.node_name == ^node_name and
          (s.state in ^@placed_states or (s.state == :error and s.id in ^reported_ids)),
      select: %{workspace_gb: s.workspace_gb, memory_mb: s.memory_mb, template: s.template}
    )
    |> Repo.all()
    |> Enum.map(&disk_ceiling_bytes(&1, node))
    |> Enum.sum()
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
  Whether the filesystem has room for the sandbox's next pause, which
  writes a full memory image beside the previous one.
  """
  def disk_space?(%{disk: %{available_bytes: available}}, sandbox) when is_integer(available) do
    available >= pause_bytes(sandbox) + @disk_headroom_bytes
  end

  def disk_space?(_node, _sandbox), do: true

  def ready_nodes(template) when is_binary(template) do
    Enum.filter(Nodes.connected_nodes(), &template_ready?(&1, template))
  end

  defp template_ready?(node, template) do
    node
    |> Map.get(:templates, [])
    |> Enum.any?(fn candidate -> candidate.name == template and candidate.ready end)
  end

  @doc """
  Picks and reserves the node a new sandbox boots on: the connected node
  with the template ready, disk for the sandbox and the most free memory.
  When no node has room, idle sandboxes are paused on the node that can
  free the most. Returns `{:error, :no_node}` when no connected node has
  the template and `{:error, :no_capacity}` when none has room.
  """
  def place(%Sandbox{node_name: nil, template: template} = sandbox) do
    ready =
      Nodes.await(
        fn ->
          case ready_nodes(template) do
            [] -> {:retry, []}
            nodes -> nodes
          end
        end,
        Nodes.presence_wait_ms()
      )

    candidates = Enum.filter(ready, &(disk_space?(&1, sandbox) and disk_room?(&1, sandbox)))

    cond do
      ready == [] -> {:error, :no_node}
      candidates == [] -> {:error, :no_capacity}
      true -> place_on(candidates, sandbox)
    end
  end

  defp place_on(candidates, sandbox) do
    charge = charge_bytes(sandbox)
    ranked = rank(candidates)

    reserve = fn node ->
      reserve(node, charge, fn -> set_node(sandbox, node.name) end, fn -> disk_room?(node, sandbox) end)
    end

    case Enum.find(ranked, fn node -> reserve.(node) == :ok end) do
      %{name: node_name} ->
        {:ok, node_name}

      nil ->
        case place_by_reclaiming(ranked, charge, reserve) do
          {:ok, node_name} -> {:ok, node_name}
          {:error, :no_capacity} -> place_by_growing(ranked, charge, reserve)
        end
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

  defp place_by_growing(ranked, charge, reserve) do
    with {:ok, node} <- most_growable(ranked, charge),
         {:ok, grown} <- grow(node, charge, wait_ms(:grow_wait_ms)),
         :ok <- reserve.(grown) do
      {:ok, grown.name}
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
  def admit(%Sandbox{state: :paused, node_name: node_name} = sandbox) when is_binary(node_name) do
    charge = charge_bytes(sandbox)

    case Nodes.await_lookup(node_name) do
      {:ok, _pid, info} ->
        node = Map.put(info, :name, node_name)
        reserve = fn node -> reserve(node, charge, fn -> mark_resuming(sandbox) end) end

        with true <- disk_space?(node, sandbox),
             :no_capacity <- reserve.(node),
             {:error, :no_capacity} <- reclaim_and_reserve(node, charge, reserve),
             {:ok, grown} <- grow(node, charge, wait_ms(:grow_wait_ms)),
             :ok <- reserve.(grown) do
          {:ok, Repo.reload!(sandbox)}
        else
          :ok -> {:ok, Repo.reload!(sandbox)}
          _no_room -> {:error, :no_capacity}
        end

      {:error, :not_connected} ->
        {:ok, mark_resuming(sandbox)}
    end
  end

  @doc """
  Whether a work item for the session could be placed right now, without
  reserving anything: the poller leaves an item queued when its sandbox
  would not fit anywhere, so the queue rather than a forced stop holds it
  until a pause frees memory. When only a growth of an elastic node's
  carve-out would fit it, the growth is asked for here and the item is
  admissible if the node reports it within a couple of seconds; a growth
  the kubelet defers stays asked for, and the item, left queued, fits once
  the node has room. Sessions whose sandbox already holds memory and
  environments with no connected node at all are admissible; the latter
  fail on dispatch as before.
  """
  def admissible?(%AgentEnvironment{} = agent_environment, session_id) when is_binary(session_id) do
    case Sandboxes.get_sandbox_for_session(agent_environment.id, session_id) do
      %Sandbox{state: state} when state in @charged_states -> true
      %Sandbox{state: :paused, node_name: node_name} = sandbox when is_binary(node_name) -> resumable?(sandbox)
      _new -> placeable?(agent_environment)
    end
  end

  defp resumable?(%Sandbox{node_name: node_name} = sandbox) do
    case Nodes.lookup(node_name) do
      {:ok, _pid, info} ->
        node = Map.put(info, :name, node_name)
        memory_room?(node, sandbox) or grown_in_time?(node, sandbox)

      {:error, :not_connected} ->
        true
    end
  end

  defp placeable?(agent_environment) do
    case ready_nodes(agent_environment.template) do
      [] ->
        true

      nodes ->
        with_disk = Enum.filter(nodes, &disk_room?(&1, agent_environment))
        Enum.any?(with_disk, &memory_room?(&1, agent_environment)) or grown_in_time?(with_disk, agent_environment)
    end
  end

  defp grown_in_time?(nodes, sized) when is_list(nodes) do
    case nodes |> Enum.filter(&disk_space?(&1, sized)) |> most_growable(charge_bytes(sized)) do
      {:ok, node} -> grown_in_time?(node, sized)
      {:error, :no_capacity} -> false
    end
  end

  defp grown_in_time?(node, sized) do
    disk_space?(node, sized) and match?({:ok, _node}, grow(node, charge_bytes(sized), wait_ms(:admission_grow_wait_ms)))
  end

  @doc """
  Grows an elastic node's carve-out so `charge` more bytes fit on top of
  what its sandboxes hold, rounded up to whole GiB and capped at the
  node's ceiling, and waits up to `wait_ms` for the daemon to report the
  new limit. Returns `{:ok, node}` with the node's fresh report,
  `{:pending, limit}` when the kubelet has not applied the growth in time
  (it stays asked for and applies once the node has room), or
  `{:error, reason}` when the ceiling cannot hold it or the resize failed.
  """
  def grow(%{name: node_name} = node, charge, wait_ms) when is_integer(charge) and is_integer(wait_ms) do
    if elastic?(node) do
      with {:ok, limit} <- ask_for_growth(node, charge),
           :ok <- resize(node, limit) do
        await_limit(node_name, limit, wait_ms)
      end
    else
      {:error, :no_capacity}
    end
  end

  defp ask_for_growth(%{name: node_name, elastic: elastic} = node, charge) do
    fn ->
      lock(node_name)
      needed = reserved_bytes(node_name) + charge + @daemon_reserve_bytes
      if needed > elastic.memory_ceiling_bytes, do: Repo.rollback(:no_capacity)

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

  defp await_limit(node_name, limit, wait_ms) do
    Nodes.await(
      fn ->
        case Nodes.lookup(node_name) do
          {:ok, _pid, info} ->
            node = Map.put(info, :name, node_name)
            if (reported_limit(node) || 0) >= limit, do: {:ok, node}, else: {:retry, {:pending, limit}}

          {:error, :not_connected} ->
            {:retry, {:pending, limit}}
        end
      end,
      wait_ms
    )
  end

  defp resize(%{name: node_name, elastic: %{pod_name: pod_name}}, limit) do
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
  hold, never below the floor, once a few minutes have passed since its
  last growth, and retries a shrink the kubelet has not applied yet. Run
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
  def shrink(%{name: node_name} = node) do
    case lower_limit(node) do
      {:ok, limit} ->
        reclaim_cgroup(node_name, limit)

        with :ok <- resize(node, limit) do
          Logger.info("sandboxes: shrank a node's carve-out", node: node_name, memory_bytes: limit)
        end

        {:ok, limit}

      :unchanged ->
        :unchanged
    end
  end

  defp lower_limit(%{name: node_name, elastic: elastic} = node) do
    fn ->
      lock(node_name)

      with %SandboxNode{pod_name: pod_name} = row <- Repo.get(SandboxNode, node_name),
           true <- pod_name == elastic.pod_name,
           false <- held?(row) do
        needed = reserved_bytes(node_name) + @daemon_reserve_bytes

        target =
          needed |> round_up_to_step() |> max(elastic.memory_floor_bytes) |> min(row.memory_limit_bytes)

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

  defp held?(%SandboxNode{grown_at: nil}), do: false

  defp held?(%SandboxNode{grown_at: grown_at}) do
    DateTime.diff(DateTime.utc_now(), grown_at, :second) < @shrink_hold_seconds
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

  defp wait_ms(:grow_wait_ms),
    do: :tuist |> Application.get_env(__MODULE__, []) |> Keyword.get(:grow_wait_ms, @grow_wait_ms)

  defp wait_ms(:admission_grow_wait_ms) do
    :tuist |> Application.get_env(__MODULE__, []) |> Keyword.get(:admission_grow_wait_ms, @admission_grow_wait_ms)
  end

  defp round_up_to_step(bytes), do: div(bytes + @carve_out_step_bytes - 1, @carve_out_step_bytes) * @carve_out_step_bytes

  defp most_growable(nodes, charge) do
    nodes
    |> Enum.filter(&elastic?/1)
    |> Enum.map(&{&1, &1.elastic.memory_ceiling_bytes - @daemon_reserve_bytes - reserved_bytes(&1.name)})
    |> Enum.filter(fn {_node, room} -> room >= charge end)
    |> Enum.max_by(fn {_node, room} -> room end, fn -> nil end)
    |> case do
      {node, _room} -> {:ok, node}
      nil -> {:error, :no_capacity}
    end
  end

  defp reclaim_and_reserve(node, charge, reserve) do
    with :ok <- reclaim(node, charge),
         :ok <- reserve.(node) do
      :ok
    else
      _no_room -> {:error, :no_capacity}
    end
  end

  # A paused sandbox's disk is already reserved on its node, so resuming
  # it only needs memory and room for its next pause.
  defp memory_room?(node, sandbox) do
    disk_space?(node, sandbox) and
      case free_bytes(node) do
        :unbounded -> true
        free -> free + reclaimable_bytes(node.name) >= charge_bytes(sandbox)
      end
  end

  defp rank(nodes) do
    nodes
    |> Enum.map(&{&1, free_bytes(&1)})
    |> Enum.sort_by(fn {_node, free} -> if free == :unbounded, do: :infinity, else: free end, :desc)
    |> Enum.map(fn {node, _free} -> node end)
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
  # for the last of a node's disk budget see each other's rows.
  defp reserve(node, charge, apply, disk_fits \\ fn -> true end) do
    fn ->
      lock(node.name)

      memory_fits =
        case memory_budget_bytes(node) do
          :unbounded -> true
          budget -> budget - reserved_bytes(node.name) >= charge
        end

      if memory_fits and disk_fits.(), do: apply.(), else: Repo.rollback(:no_capacity)
    end
    |> Repo.transaction()
    |> case do
      {:ok, _applied} -> :ok
      {:error, :no_capacity} -> :no_capacity
    end
  end

  defp lock(node_name) do
    Repo.query!("SELECT pg_advisory_xact_lock($1::integer, hashtext($2))", [@advisory_lock_namespace, node_name])
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
    sandbox |> Sandbox.update_changeset(%{state: :resuming}) |> Repo.update!()
  end
end
