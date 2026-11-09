defmodule Tuist.Sandboxes.MacosCapacity do
  @moduledoc """
  Atomic server reservations for fixed-size macOS VMs. The host also reserves
  an execution Pod and fences every launch against CI under its launch lock.
  A resident pause retains the entire charge, including its VM slot.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  @charged [:creating, :resuming, :running]
  @mib 1024 * 1024

  def place(sandbox) do
    # A host with a booted warm VM of this shape claims it instead of
    # cold-booting, so it is tried first.
    nodes =
      Nodes.connected_nodes()
      |> Enum.filter(&ready?(&1, sandbox.template))
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

  def admit_turn(sandbox, apply) do
    with {:ok, _pid, info} <- Nodes.lookup(sandbox.node_name),
         true <- info[:generation] == sandbox.node_uid and allowed?(info) do
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
        with :ok <- Concurrency.check(environment.account_id, environment), do: placement(environment)
    end
  end

  def admissible?(environment, session_id), do: admission(environment, session_id) == :ok

  defp quota(%Sandbox{state: state}) when state in @charged, do: :ok
  defp quota(sandbox), do: Concurrency.check(sandbox.account_id, sandbox)

  defp host_admission(%Sandbox{node_name: node_name, node_uid: node_uid}) do
    status =
      case Nodes.lookup(node_name) do
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
      length(others) < min(2, granted_slots)
  end
end
