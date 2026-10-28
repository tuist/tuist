defmodule Tuist.Sandboxes.MacosCapacity do
  @moduledoc """
  Atomic server reservations for fixed-size macOS VMs. The host also reserves
  an execution Pod and fences every launch against CI under its launch lock.
  A resident pause retains the entire charge, including its VM slot.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  @charged [:creating, :resuming, :running]
  @mib 1024 * 1024

  def place(sandbox) do
    nodes = Enum.filter(Nodes.connected_nodes(), &ready?(&1, sandbox.template))

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
    with true <- Sandboxes.platform_enabled?(sandbox),
         {:ok, _pid, info} <- Nodes.lookup(sandbox.node_name),
         true <- info[:generation] == sandbox.node_uid and allowed?(info) do
      apply.()
    else
      _ -> {:error, :no_capacity}
    end
  end

  def admissible?(environment, session_id) do
    if Sandboxes.platform_enabled?(environment) do
      case Sandboxes.get_sandbox_for_session(environment.id, session_id) do
        %Sandbox{} = sandbox ->
          case Nodes.lookup(sandbox.node_name) do
            {:ok, _pid, info} -> info[:generation] == sandbox.node_uid and allowed?(info)
            _ -> false
          end

        nil ->
          Enum.any?(Nodes.connected_nodes(), &(ready?(&1, environment.template) and room?(&1, environment)))
      end
    else
      false
    end
  end

  defp ready?(node, template) do
    node[:platform] == "darwin" and allowed?(node) and
      Enum.any?(Map.get(node, :templates, []), &(&1.name == template and &1.ready))
  end

  def allowed?(%{platform: "darwin", generation: generation, control_uid: control, admission: grant}) do
    with %{"allow" => true, "node_uid" => ^generation, "control_uid" => ^control, "observed_at" => at} <- grant,
         {:ok, observed, _offset} <- DateTime.from_iso8601(at) do
      age = DateTime.diff(DateTime.utc_now(), observed, :millisecond)
      age >= -1000 and age < 15_000
    else
      _ -> false
    end
  end

  def allowed?(_node), do: false

  defp reserve(sandbox, node, state) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1::integer, hashtext($2))", [7302, node.name])
      current = Repo.get!(Sandbox, sandbox.id)

      if current.state not in [:creating, :paused, :resuming] or not Sandboxes.platform_enabled?(current) or
           not allowed?(node) or not room?(node, current),
         do: Repo.rollback(:no_capacity)

      if current.node_name && (current.node_name != node.name or current.node_uid != node.generation),
        do: Repo.rollback(:owner_changed)

      current
      |> Sandbox.update_changeset(%{node_name: node.name, node_uid: node.generation, state: state, resident: true})
      |> Repo.update!()
    end)
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
