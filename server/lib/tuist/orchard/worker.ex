defmodule Tuist.Orchard.Worker do
  @moduledoc """
  Mac mini host running `orchard worker` + Tart. Registers itself with
  the controller, heartbeats periodically, and accepts VM scheduling
  via the watch RPC WebSocket.

  The JSON shape returned to clients matches the upstream
  `pkg/resource/v1.Worker` Go struct so existing Cirrus tooling works
  unchanged.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @valid_runtimes ~w(tart vetu)
  @valid_archs ~w(arm64 amd64)

  schema "orchard_workers" do
    field :name, :string
    field :machine_id, :string
    field :arch, :string, default: "arm64"
    field :runtime, :string, default: "tart"
    field :last_seen_at, :utc_datetime_usec
    field :scheduling_paused, :boolean, default: false
    field :resources, :map, default: %{}
    field :labels, :map, default: %{}
    field :default_cpu, :integer, default: 4
    field :default_memory, :integer, default: 8192
    field :version, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def create_changeset(worker, attrs) do
    worker
    |> cast(attrs, [
      :name,
      :machine_id,
      :arch,
      :runtime,
      :last_seen_at,
      :resources,
      :labels,
      :default_cpu,
      :default_memory
    ])
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> validate_inclusion(:arch, @valid_archs)
    |> validate_inclusion(:runtime, @valid_runtimes)
    |> unique_constraint(:name)
  end

  @doc """
  Mirrors upstream's PUT /v1/workers/:name semantics: clients can only
  bump LastSeen + flip SchedulingPaused. Capacity changes go through
  the (re-)create path so we can verify machine_id ownership.
  """
  def heartbeat_changeset(worker, attrs) do
    cast(worker, attrs, [:last_seen_at, :scheduling_paused, :resources, :labels])
  end

  def offline?(%__MODULE__{last_seen_at: nil}, _timeout), do: true

  def offline?(%__MODULE__{last_seen_at: last_seen}, timeout_seconds) when is_integer(timeout_seconds) do
    DateTime.diff(DateTime.utc_now(), last_seen, :second) > timeout_seconds
  end
end
