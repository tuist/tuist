defmodule Tuist.Orchard.VM do
  @moduledoc """
  Tart VM resource. The VK provider creates one of these per Pod;
  Cirrus's `orchard worker` daemon picks them up via the watch RPC and
  brings the local Tart state in sync.

  Lifecycle:

      pending  ─────► (scheduler picks worker, sets worker_name) ─────►
      pending  ─────► (worker boots tart VM, posts state event) ─────►
      running  ─────► (worker reports failure or VM exits) ───────────►
      failed/stopped

  Status transitions are driven by worker events; the controller never
  flips status on its own except on terminal-state cleanup.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @statuses ~w(pending running failed stopping stopped)
  @restart_policies ~w(Never OnFailure Always)

  schema "orchard_vms" do
    field :name, :string
    field :uid, :binary_id
    field :image, :string
    field :image_pull_policy, :string, default: "if-not-present"
    field :cpu, :integer, default: 0
    field :memory, :integer, default: 0
    field :disk_size, :integer, default: 0
    field :headless, :boolean, default: true
    field :nested, :boolean, default: false
    field :startup_script, :string
    field :user_data, :string
    field :resources, :map, default: %{}
    field :labels, :map, default: %{}
    field :restart_policy, :string, default: "Never"
    field :status, :string, default: "pending"
    field :status_message, :string
    field :worker_name, :string
    field :assigned_cpu, :integer, default: 0
    field :assigned_memory, :integer, default: 0
    field :username, :string, default: "admin"
    field :password, :string, default: "admin"
    field :version, :integer, default: 0
    field :conditions, {:array, :map}, default: []
    field :restart_count, :integer, default: 0
    field :restarted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  @doc """
  Initial creation. Status defaults to `pending`; the scheduler picks
  it up and assigns a worker.
  """
  def create_changeset(vm, attrs) do
    vm
    |> cast(attrs, [
      :name,
      :image,
      :image_pull_policy,
      :cpu,
      :memory,
      :disk_size,
      :headless,
      :nested,
      :startup_script,
      :user_data,
      :resources,
      :labels,
      :restart_policy,
      :username,
      :password
    ])
    |> validate_required([:name, :image])
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> validate_inclusion(:restart_policy, @restart_policies)
    |> unique_constraint(:name)
    |> put_initial_conditions()
    |> put_uid()
  end

  defp put_uid(changeset) do
    case get_field(changeset, :uid) do
      nil -> put_change(changeset, :uid, Ecto.UUID.generate())
      _ -> changeset
    end
  end

  @doc """
  Worker-side update: reports status + assigned cpu/memory back to the
  controller. The controller never overwrites these from API client
  PUTs (that's `update_spec_changeset`).
  """
  def update_state_changeset(vm, attrs) do
    vm
    |> cast(attrs, [:status, :status_message, :conditions, :restart_count, :restarted_at])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Spec update from a client. Only fields that aren't worker-owned can
  be changed mid-flight.
  """
  def update_spec_changeset(vm, attrs) do
    vm
    |> cast(attrs, [:cpu, :memory, :disk_size, :resources, :labels, :restart_policy])
    |> validate_inclusion(:restart_policy, @restart_policies)
  end

  @doc """
  Scheduler-side update: sets worker_name + assigned resources.
  """
  def schedule_changeset(vm, worker, assigned_cpu, assigned_memory) do
    now = DateTime.utc_now()

    vm
    |> cast(%{}, [])
    |> put_change(:worker_name, worker.name)
    |> put_change(:assigned_cpu, assigned_cpu)
    |> put_change(:assigned_memory, assigned_memory)
    |> put_change(:conditions, [
      %{
        "type" => "Scheduled",
        "state" => "True",
        "lastTransitionTime" => DateTime.to_iso8601(now)
      }
    ])
  end

  def terminal?(%__MODULE__{status: status}) when status in ["failed", "stopped"], do: true
  def terminal?(_), do: false

  defp put_initial_conditions(changeset) do
    put_change(changeset, :conditions, [
      %{"type" => "Scheduled", "state" => "False"}
    ])
  end
end
