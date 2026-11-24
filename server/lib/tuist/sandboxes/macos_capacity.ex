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
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshotCopy
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  require Logger

  @charged [:creating, :resuming, :running]
  @on_disk [:creating, :resuming, :running, :paused]
  @mib 1024 * 1024
  @free_disk_reserve_bytes 20 * 1024 * @mib

  @doc """
  Reserves the first macOS host that takes the sandbox. `claims_warm: false`
  is for a create that cannot claim a warm VM (a restore): the warm VM keeps
  one of the host's slots, so hosts without one are tried first.
  """
  def place(sandbox, node_filter \\ fn _node -> true end, opts \\ []) do
    darwin = Enum.filter(Nodes.connected_nodes(), &(&1[:platform] == "darwin"))
    claims_warm = Keyword.get(opts, :claims_warm, true)

    # A host with a booted warm VM of this shape claims it instead of
    # cold-booting, so it is tried first.
    nodes =
      darwin
      |> Enum.filter(&(ready?(&1, sandbox.template) and node_filter.(&1)))
      |> Enum.sort_by(&(warm?(&1, sandbox) != claims_warm))

    {result, refused} =
      Enum.reduce_while(nodes, {{:error, :no_capacity}, %{}}, fn node, {_result, refused} ->
        case reserve(sandbox, node, :creating) do
          {:ok, _sandbox} -> {:halt, {{:ok, node.name}, refused}}
          {:error, reason} -> {:cont, {{:error, :no_capacity}, Map.put(refused, node.name, reason)}}
        end
      end)

    log_placement(sandbox, darwin, node_filter, result, refused)
    result
  end

  # One line per macOS placement naming every connected host, whether it
  # held a warm VM of the shape, and why it was or was not chosen, so a
  # create that boots cold beside a warm VM says why.
  defp log_placement(sandbox, darwin, node_filter, result, refused) do
    chosen = with {:ok, name} <- result, do: name

    hosts =
      darwin
      |> Enum.sort_by(& &1.name)
      |> Enum.map_join(" ", fn node ->
        warm = if warm?(node, sandbox), do: "warm:", else: ""

        "#{node.name |> String.split("-") |> List.last()}=#{warm}#{host_reason(node, sandbox, node_filter, chosen, refused)}"
      end)

    Logger.info("sandboxes: macOS placement",
      sandbox_id: sandbox.id,
      shape: "#{sandbox.vcpus}x#{sandbox.memory_mb}",
      node: chosen,
      hosts: hosts
    )
  end

  defp host_reason(%{name: chosen}, _sandbox, _node_filter, chosen, _refused), do: "chosen"

  defp host_reason(node, sandbox, node_filter, _chosen, refused) do
    cond do
      Map.has_key?(refused, node.name) -> "refused_#{refused[node.name]}_#{room_status(node, sandbox)}"
      not node_filter.(node) -> "excluded"
      (status = template_status(node, sandbox.template)) != :ok -> status
      (status = grant_status(node)) != :ok -> status
      true -> "not_tried"
    end
  end

  # A paused VM resumes warm only on its own host, so a refusal names why
  # that host can't take it now (`{:host_busy, why}`), not that no host
  # could. The caller then moves the session off (`Archives.move_off/1`).
  def admit(sandbox) do
    case Nodes.lookup(sandbox.node_name) do
      {:ok, _pid, %{generation: generation} = info} when generation == sandbox.node_uid ->
        node = Map.put(info, :name, sandbox.node_name)

        case grant_status(node) do
          :ok -> sandbox |> reserve(node, :resuming) |> host_full()
          :grant_denied -> {:error, {:host_busy, :ci}}
          _stale_or_missing -> {:error, {:host_busy, :no_grant}}
        end

      {:ok, _pid, _info} ->
        {:error, {:host_busy, :replaced}}

      {:error, _reason} ->
        {:error, {:host_busy, :not_connected}}
    end
  end

  defp host_full({:error, :no_capacity}), do: {:error, {:host_busy, :full}}
  defp host_full(result), do: result

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
      # An archived sandbox has no host; it restores wherever a new one would go.
      %Sandbox{state: :archived} = sandbox ->
        with :ok <- quota(sandbox), do: placement(environment)

      %Sandbox{state: state, node_name: node_name} = sandbox when state != :error or is_binary(node_name) ->
        with :ok <- quota(sandbox), do: host_admission(sandbox)

      # Nothing, or an errored one without a node, which is replaced
      # (`Router.find_or_create_sandbox/3`).
      _new ->
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

  @doc """
  Whether CI holds a host reservation on the connected macOS host: its
  fresh grant denies sandboxes, so a session paused there cannot resume
  until the reservation ends (`Tuist.Sandboxes.Archives.move_off_node/1`).
  A stale or missing grant says nothing about CI.
  """
  def ci_reserved?(node_name) do
    case Nodes.lookup(node_name) do
      {:ok, _pid, info} -> grant_status(info) == :grant_denied
      {:error, _reason} -> false
    end
  end

  @doc """
  Whether the host can restore an archived sandbox: it archives and
  restores disks (`archives` in its hello) and has the template. The
  archived disk is a delta on the image it was cloned from, which a host
  running another image of the template pulls by digest first.
  """
  def restores?(node, %{template: template}) do
    Map.get(node, :archives) == true and Enum.any?(Map.get(node, :templates, []), &(&1.name == template))
  end

  @doc """
  Whether the host's template runs the image an archived sandbox was
  cloned from, so its restore pulls nothing.
  """
  def runs_image?(node, %{template: template, template_tag: tag}) do
    Enum.any?(Map.get(node, :templates, []), &(&1.name == template and &1.tag == tag))
  end

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
      # tart-kubelet forwards an empty grant when its Node has no grant
      # annotation, so an empty `node_uid` means no grant, not another Node's.
      %{"node_uid" => uid} when uid not in [nil, ""] -> :grant_mismatch
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

  defp room?(node, sandbox), do: room_status(node, sandbox) == :ok

  defp room_status(node, sandbox) do
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

    cond do
      not Enum.all?([granted_memory, granted_cpu, granted_slots, node_memory, node_cpus], &is_integer/1) -> :no_report
      memory > min(node_memory, granted_memory) -> :no_memory
      cpus * 1000 > min(node_cpus * 1000, granted_cpu) -> :no_cpu
      length(others) + slots(sandbox) > min(2, granted_slots) -> :no_slot
      true -> disk_status(node, sandbox)
    end
  end

  defp disk_status(node, sandbox) do
    if resident_pause?(sandbox) or disk_room?(node, sandbox), do: :ok, else: :no_disk
  end

  # A Claude Code snapshot build (`Tuist.Sandboxes.ClaudeCodeSnapshots`),
  # whose builder has the build's id, holds its slot for up to an hour and
  # serves no session, so it runs only on a host it leaves a granted slot
  # free on: an idle host, while CI has not claimed its slots.
  defp slots(%Sandbox{id: id}) when is_binary(id) do
    if Repo.exists?(from(d in DiskSnapshot, where: d.id == ^id and d.state == :building)), do: 2, else: 1
  end

  defp slots(_sandbox), do: 1

  # A VM paused in memory resumes without touching the disk, which the
  # host does not check for it either.
  defp resident_pause?(%Sandbox{state: :paused, resident: true}), do: true
  defp resident_pause?(_sandbox), do: false

  # The host's final check (`diskRoom` in tart-kubelet), from its report:
  # every VM it holds, evicted ones included, reserves its whole root disk
  # and two memory images against half the filesystem, and a launch leaves
  # two memory images and 20 GiB free, after what its disk snapshots hold
  # (`disk.snapshots_bytes`, which only the host measures; a save made since
  # its last report is still caught by the host's own check, and the create
  # moves on to the next host). Rows rather than the report decide
  # which VMs it holds, as in `Capacity.reserved_disk_bytes/1`: a create in
  # flight is not in the report yet. Errored rows count while the host
  # still reports them. A host that reports no budget (an older
  # tart-kubelet) is not budgeted here; its own check still applies.
  defp disk_room?(%{disk: %{budget_bytes: budget, available_bytes: available}} = node, sandbox)
       when is_integer(budget) and budget > 0 and is_integer(available) do
    rootfs = rootfs_bytes(node, sandbox.template)

    reserved_disk_bytes(node, sandbox.template, Map.get(sandbox, :id)) + disk_ceiling_bytes(rootfs, sandbox.memory_mb) <=
      budget and available >= sandbox.memory_mb * 2 * @mib + @free_disk_reserve_bytes
  end

  defp disk_room?(_node, _sandbox), do: true

  @doc """
  Hosts that can take a copy of a macOS disk snapshot: connected, serving
  its template and restoring archives. A host whose template moved on to a
  newer image pulls the one the snapshot was saved from, which its overlay
  sits on, as an archived session's restore does. The grant is not needed:
  a copy takes disk, not a VM slot.
  """
  def snapshot_hosts(%DiskSnapshot{} = snapshot) do
    Enum.filter(Nodes.connected_nodes(), &(&1[:platform] == "darwin" and restores?(&1, snapshot)))
  end

  @doc """
  Records a copy of `snapshot` on `node` with `insert` when the host's disk
  budget holds the snapshot's measured bytes on top of its VMs, its
  snapshots and the copies already downloading to it, under the host's
  lock. The host checks again before downloading.
  """
  def reserve_snapshot_copy(node, %DiskSnapshot{disk_bytes: bytes} = snapshot, insert)
      when is_integer(bytes) and is_function(insert, 0) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1::integer, hashtext($2))", [7302, node.name])

      if snapshot_room?(node, snapshot.template, bytes) do
        case insert.() do
          {:ok, copy} -> copy
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        Repo.rollback(:no_capacity)
      end
    end)
  end

  def reserve_snapshot_copy(_node, _snapshot, _insert), do: {:error, :no_capacity}

  defp snapshot_room?(%{disk: %{budget_bytes: budget, available_bytes: available}} = node, template, bytes)
       when is_integer(budget) and budget > 0 and is_integer(available) do
    downloading =
      Repo.one(
        from(c in DiskSnapshotCopy,
          join: s in assoc(c, :disk_snapshot),
          where: c.node_name == ^node.name and c.state == :copying,
          select: type(coalesce(sum(s.disk_bytes), 0), :integer)
        )
      )

    reserved_disk_bytes(node, template, nil) + downloading + bytes <= budget and
      available >= bytes + @free_disk_reserve_bytes
  end

  defp snapshot_room?(_node, _template, _bytes), do: true

  # The VMs the host holds and the snapshots it reported.
  defp reserved_disk_bytes(node, template, id) do
    reported =
      for %{id: reported_id} <- Map.get(node, :sandboxes, []), {:ok, uuid} <- [Ecto.UUID.cast(reported_id)], do: uuid

    rootfs = rootfs_bytes(node, template)

    vms =
      from(s in Sandbox,
        where: s.node_name == ^node.name and s.state in ^@on_disk,
        or_where: s.node_name == ^node.name and s.state == :error and s.id in ^reported,
        select: %{id: s.id, memory_mb: s.memory_mb}
      )
      |> Repo.all()
      |> Enum.reject(&(&1.id == id))
      |> Enum.map(&disk_ceiling_bytes(rootfs, &1.memory_mb))
      |> Enum.sum()

    vms + (Map.get(node.disk, :snapshots_bytes) || 0)
  end

  defp disk_ceiling_bytes(rootfs, memory_mb), do: rootfs + memory_mb * 2 * @mib + 128 * @mib

  defp rootfs_bytes(node, template) do
    case Enum.find(Map.get(node, :templates, []), &(&1.name == template)) do
      %{rootfs_bytes: bytes} when is_integer(bytes) -> bytes
      _template -> 0
    end
  end
end
