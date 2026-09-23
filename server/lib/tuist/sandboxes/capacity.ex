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

  A pause writes a full memory image beside the previous one, so a node
  must have that much free plus headroom, and the node's optional disk
  budget caps what jails hold exclusively.

  Reservations are serialized per node with a transaction-scoped
  advisory lock. The reservation is the row itself: `node_name` set on a
  creating sandbox, or the `resuming` state on a paused one, both of
  which the reserved sum counts.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  require Logger

  @mib 1024 * 1024
  # The daemon, the jailers and the Firecracker processes share the cgroup
  # with the guests.
  @daemon_reserve_bytes 512 * @mib
  # Per guest, outside its memory: the VMM process, vsock and tap buffers.
  @vm_overhead_bytes 64 * @mib
  # Room the filesystem must keep beyond the next memory image.
  @disk_headroom_bytes 1024 * @mib
  @charged_states [:creating, :resuming, :running]
  @advisory_lock_namespace 7_302

  def charge_bytes(%{memory_mb: memory_mb}) when is_integer(memory_mb), do: memory_mb * @mib + @vm_overhead_bytes

  def pause_bytes(%{memory_mb: memory_mb}) when is_integer(memory_mb), do: memory_mb * @mib

  def memory_budget_bytes(%{capacity: %{memory_bytes: total}}) when is_integer(total) and total > 0 do
    max(total - @daemon_reserve_bytes, 0)
  end

  def memory_budget_bytes(_node), do: :unbounded

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

  def disk_ok?(%{disk: %{available_bytes: available} = disk}, sandbox) when is_integer(available) do
    needed = pause_bytes(sandbox)

    within_budget =
      case disk do
        %{budget_bytes: budget, sandboxes_bytes: used} when is_integer(budget) and budget > 0 and is_integer(used) ->
          used + needed <= budget

        _no_budget ->
          true
      end

    available >= needed + @disk_headroom_bytes and within_budget
  end

  def disk_ok?(_node, _sandbox), do: true

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
    ready = ready_nodes(template)
    candidates = Enum.filter(ready, &disk_ok?(&1, sandbox))

    cond do
      ready == [] -> {:error, :no_node}
      candidates == [] -> {:error, :no_capacity}
      true -> place_on(candidates, sandbox)
    end
  end

  defp place_on(candidates, sandbox) do
    charge = charge_bytes(sandbox)
    ranked = rank(candidates)
    reserve = fn node -> reserve(node, charge, fn -> set_node(sandbox, node.name) end) end

    case Enum.find(ranked, fn node -> reserve.(node) == :ok end) do
      %{name: node_name} ->
        {:ok, node_name}

      nil ->
        with {:ok, node} <- most_reclaimable(ranked, charge),
             :ok <- reclaim(node, charge),
             :ok <- reserve.(node) do
          {:ok, node.name}
        else
          _no_room -> {:error, :no_capacity}
        end
    end
  end

  @doc """
  Reserves memory on the sandbox's own node for a resume and marks the
  row `resuming`. A node that is not connected is not budgeted here; the
  resume command reports it. Pauses idle sandboxes on the node when the
  paused one does not fit as is.
  """
  def admit(%Sandbox{state: :paused, node_name: node_name} = sandbox) when is_binary(node_name) do
    charge = charge_bytes(sandbox)

    case Nodes.lookup(node_name) do
      {:ok, _pid, info} ->
        node = Map.put(info, :name, node_name)
        reserve = fn -> reserve(node, charge, fn -> mark_resuming(sandbox) end) end

        with true <- disk_ok?(node, sandbox),
             :no_capacity <- reserve.(),
             :ok <- reclaim(node, charge),
             :ok <- reserve.() do
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
  until a pause frees memory. Sessions whose sandbox already holds memory
  and environments with no connected node at all are admissible; the
  latter fail on dispatch as before.
  """
  def admissible?(%AgentEnvironment{} = agent_environment, session_id) when is_binary(session_id) do
    case Sandboxes.get_sandbox_for_session(agent_environment.id, session_id) do
      %Sandbox{state: state} when state in @charged_states ->
        true

      %Sandbox{state: :paused, node_name: node_name} = sandbox when is_binary(node_name) ->
        case Nodes.lookup(node_name) do
          {:ok, _pid, info} -> room?(Map.put(info, :name, node_name), sandbox)
          {:error, :not_connected} -> true
        end

      _new ->
        case ready_nodes(agent_environment.template) do
          [] -> true
          nodes -> Enum.any?(nodes, &room?(&1, agent_environment))
        end
    end
  end

  defp room?(node, sandbox) do
    disk_ok?(node, sandbox) and
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

  defp reserve(node, charge, apply) do
    case memory_budget_bytes(node) do
      :unbounded ->
        apply.()
        :ok

      budget ->
        fn ->
          lock(node.name)

          if budget - reserved_bytes(node.name) >= charge do
            apply.()
          else
            Repo.rollback(:no_capacity)
          end
        end
        |> Repo.transaction()
        |> case do
          {:ok, _applied} -> :ok
          {:error, :no_capacity} -> :no_capacity
        end
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
          case Sandboxes.pause(sandbox) do
            {:ok, _paused} ->
              Logger.info("sandboxes: paused an idle sandbox to make room",
                sandbox_id: sandbox.id,
                node: node.name,
                freed_bytes: charge_bytes(sandbox)
              )

              {:cont, freed + charge_bytes(sandbox)}

            {:error, reason} ->
              Logger.warning("sandboxes: could not pause an idle sandbox for room",
                sandbox_id: sandbox.id,
                node: node.name,
                reason: inspect(reason)
              )

              {:cont, freed}
          end
        end
      end)

    if freed >= needed, do: :ok, else: {:error, :no_capacity}
  end

  defp set_node(sandbox, node_name) do
    sandbox |> Sandbox.update_changeset(%{node_name: node_name}) |> Repo.update!()
  end

  defp mark_resuming(sandbox) do
    sandbox |> Sandbox.update_changeset(%{state: :resuming}) |> Repo.update!()
  end
end
