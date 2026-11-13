defmodule Tuist.Sandboxes.MacosCapacity do
  @moduledoc """
  Atomic server reservations for fixed-size macOS VMs. The host also reserves
  an execution Pod and fences every launch against CI under its launch lock.
  A resident pause retains the entire charge, including its VM slot.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  @charged [:creating, :resuming, :running]
  @on_disk [:creating, :resuming, :running, :paused]
  @mib 1024 * 1024
  @free_disk_reserve_bytes 20 * 1024 * @mib

  def place(sandbox, node_filter \\ fn _node -> true end) do
    # A host with a booted warm VM of this shape claims it instead of
    # cold-booting, so it is tried first.
    nodes =
      Nodes.connected_nodes()
      |> Enum.filter(&(ready?(&1, sandbox.template) and node_filter.(&1)))
      |> Enum.sort_by(&(not warm?(&1, sandbox)))

    Enum.reduce_while(nodes, {:error, :no_capacity}, fn node, _acc ->
      case reserve(sandbox, node, :creating) do
        {:ok, _sandbox} -> {:halt, {:ok, node.name}}
        {:error, _reason} -> {:cont, {:error, :no_capacity}}
      end
    end)
  end

  def admit(sandbox) do
    with {:ok, _pid, info} <- Nodes.lookup(sandbox.node_name),
         true <- info[:generation] == sandbox.node_uid do
      reserve(sandbox, Map.put(info, :name, sandbox.node_name), :resuming)
    else
      _ -> {:error, :no_capacity}
    end
  end

  # A turn on a running VM takes no capacity the VM does not already hold,
  # so it needs no grant: CI and sandboxes are served first come, first
  # served, and CI demand arriving later does not take a running VM's place.
  def admit_turn(sandbox, apply) do
    with {:ok, _pid, info} <- Nodes.lookup(sandbox.node_name),
         true <- info[:generation] == sandbox.node_uid do
      apply.()
    else
      _ -> {:error, :no_capacity}
    end
  end

  @doc """
  `:ok` when a work item for the session could start now, otherwise
  `{:error, reason}` saying why, for the logs: the account's quota, or
  `{node, reason}` for the host of the session's sandbox, or for a new
  sandbox `{:no_node, %{node => reason}}` with each connected macOS host's
  first failing check (`:no_template`, `:template_not_ready`, `:no_grant`,
  `:grant_mismatch`, `:grant_stale`, `:grant_denied`, `:no_room`).
  """
  def admission(environment, session_id) do
    case Sandboxes.get_sandbox_for_session(environment.id, session_id) do
      %Sandbox{} = sandbox ->
        with :ok <- quota(sandbox), do: host_admission(sandbox)

      nil ->
        with :ok <- Capacity.quota(environment.account_id, environment), do: placement(environment)
    end
  end

  def admissible?(environment, session_id), do: admission(environment, session_id) == :ok

  defp quota(%Sandbox{state: state}) when state in @charged, do: :ok
  defp quota(sandbox), do: Capacity.quota(sandbox.account_id, sandbox)

  # Only a paused sandbox asks the host for new capacity; a running one
  # already holds it.
  defp host_admission(%Sandbox{node_name: node_name, node_uid: node_uid, state: state}) do
    status =
      case Nodes.lookup(node_name) do
        {:ok, _pid, %{generation: ^node_uid}} when state == :running -> :ok
        {:ok, _pid, %{generation: ^node_uid} = info} -> grant_status(info)
        {:ok, _pid, _info} -> :node_replaced
        {:error, reason} -> reason
      end

    if status == :ok, do: :ok, else: {:error, {node_name, status}}
  end

  defp placement(environment) do
    statuses =
      for node <- Nodes.connected_nodes(), node[:platform] == "darwin", into: %{} do
        {node.name, host_status(node, environment)}
      end

    cond do
      statuses == %{} -> {:error, :no_macos_node_connected}
      Enum.any?(statuses, fn {_name, status} -> status == :ok end) -> :ok
      true -> {:error, {:no_node, statuses}}
    end
  end

  defp host_status(node, environment) do
    with :ok <- template_status(node, environment.template),
         :ok <- grant_status(node) do
      if room?(node, environment), do: :ok, else: :no_room
    end
  end

  defp template_status(node, template) do
    case Enum.find(Map.get(node, :templates, []), &(&1.name == template)) do
      nil -> :no_template
      %{ready: true} -> :ok
      _building -> :template_not_ready
    end
  end

  defp ready?(node, template) do
    node[:platform] == "darwin" and allowed?(node) and template_status(node, template) == :ok
  end

  defp warm?(node, sandbox) do
    shape = "#{sandbox.vcpus}x#{sandbox.memory_mb}"
    Enum.any?(Map.get(node, :templates, []), &(&1.name == sandbox.template and shape in Map.get(&1, :warm, [])))
  end

  def allowed?(node), do: grant_status(node) == :ok

  # `:ok` for a fresh grant that allows native work on this host and its
  # current control Pod; otherwise why not.
  defp grant_status(%{platform: "darwin", generation: generation, control_uid: control, admission: grant}) do
    with %{"node_uid" => ^generation, "control_uid" => ^control, "observed_at" => at} <- grant,
         {:ok, observed, _offset} <- DateTime.from_iso8601(at) do
      age = DateTime.diff(DateTime.utc_now(), observed, :millisecond)

      cond do
        age < -1000 or age >= 15_000 -> :grant_stale
        grant["allow"] != true -> :grant_denied
        true -> :ok
      end
    else
      %{"node_uid" => _} -> :grant_mismatch
      _ -> :no_grant
    end
  end

  defp grant_status(_node), do: :no_grant

  defp reserve(sandbox, node, state) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1::integer, hashtext($2))", [7302, node.name])
      current = Repo.get!(Sandbox, sandbox.id)

      if current.state not in [:creating, :paused, :resuming] or not allowed?(node) or not room?(node, current),
        do: Repo.rollback(:no_capacity)

      if current.node_name && (current.node_name != node.name or current.node_uid != node.generation),
        do: Repo.rollback(:owner_changed)

      update_reservation(current, node, state)
    end)
  end

  defp update_reservation(sandbox, node, state) do
    update = fn ->
      sandbox
      |> Sandbox.update_changeset(%{node_name: node.name, node_uid: node.generation, state: state, resident: true})
      |> Repo.update()
    end

    # Creation already acquired the account reservation before placement. A
    # paused VM must acquire it again, even when its host retained the process.
    result = if sandbox.state == :paused, do: Concurrency.admit(sandbox.account_id, sandbox, update), else: update.()

    case result do
      {:ok, reserved} -> reserved
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp room?(node, sandbox) do
    id = Map.get(sandbox, :id)
    held = Repo.all(from s in Sandbox, where: s.node_name == ^node.name and (s.state in ^@charged or s.resident))
    others = Enum.reject(held, &(&1.id == id))
    memory = Enum.reduce(others, sandbox.memory_mb, &(&1.memory_mb + &2)) * @mib
    cpus = Enum.reduce(others, sandbox.vcpus, &(&1.vcpus + &2))

    grant = Map.get(node, :admission, %{})
    granted_memory = grant["memory_bytes"]
    granted_cpu = grant["cpu_milli"]
    granted_slots = grant["slots"]
    node_memory = get_in(node, [:capacity, :memory_bytes])
    node_cpus = get_in(node, [:capacity, :cpus])

    Enum.all?([granted_memory, granted_cpu, granted_slots, node_memory, node_cpus], &is_integer/1) and
      memory <= min(node_memory, granted_memory) and cpus * 1000 <= min(node_cpus * 1000, granted_cpu) and
      length(others) < min(2, granted_slots) and (resident_pause?(sandbox) or disk_room?(node, sandbox))
  end

  # A VM paused in memory resumes without touching the disk, which the
  # host does not check for it either.
  defp resident_pause?(%Sandbox{state: :paused, resident: true}), do: true
  defp resident_pause?(_sandbox), do: false

  # The host's final check (`diskRoom` in tart-kubelet), from its report:
  # every VM it holds, evicted ones included, reserves its whole root disk
  # and two memory images against half the filesystem, and a launch leaves
  # two memory images and 20 GiB free. Rows rather than the report decide
  # which VMs it holds, as in `Capacity.reserved_disk_bytes/1`: a create in
  # flight is not in the report yet. Errored rows count while the host
  # still reports them. A host that reports no budget (an older
  # tart-kubelet) is not budgeted here; its own check still applies.
  defp disk_room?(%{disk: %{budget_bytes: budget, available_bytes: available}} = node, sandbox)
       when is_integer(budget) and budget > 0 and is_integer(available) do
    id = Map.get(sandbox, :id)

    reported =
      for %{id: reported_id} <- Map.get(node, :sandboxes, []), {:ok, uuid} <- [Ecto.UUID.cast(reported_id)], do: uuid

    rootfs = rootfs_bytes(node, sandbox.template)

    reserved =
      from(s in Sandbox,
        where: s.node_name == ^node.name and s.state in ^@on_disk,
        or_where: s.node_name == ^node.name and s.state == :error and s.id in ^reported,
        select: %{id: s.id, memory_mb: s.memory_mb}
      )
      |> Repo.all()
      |> Enum.reject(&(&1.id == id))
      |> Enum.map(&disk_ceiling_bytes(rootfs, &1.memory_mb))
      |> Enum.sum()

    reserved + disk_ceiling_bytes(rootfs, sandbox.memory_mb) <= budget and
      available >= sandbox.memory_mb * 2 * @mib + @free_disk_reserve_bytes
  end

  defp disk_room?(_node, _sandbox), do: true

  defp disk_ceiling_bytes(rootfs, memory_mb), do: rootfs + memory_mb * 2 * @mib + 128 * @mib

  defp rootfs_bytes(node, template) do
    case Enum.find(Map.get(node, :templates, []), &(&1.name == template)) do
      %{rootfs_bytes: bytes} when is_integer(bytes) -> bytes
      _template -> 0
    end
  end
end
