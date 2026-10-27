defmodule Tuist.Sandboxes.SandboxNode do
  @moduledoc """
  The memory limit the server last asked a sandbox node's daemon Pod for,
  when the node's carve-out is elastic. See `Tuist.Sandboxes.Capacity`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:name, :string, autogenerate: false}
  schema "sandbox_nodes" do
    field :pod_name, :string
    field :memory_limit_bytes, :integer
    field :grown_at, :utc_datetime
    field :allocation_observed_at, :utc_datetime_usec
    field :allocation_memory_bytes, :integer
    field :allocation_free_bytes, :integer
    field :allocation_reclaim, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :name,
      :pod_name,
      :memory_limit_bytes,
      :grown_at,
      :allocation_observed_at,
      :allocation_memory_bytes,
      :allocation_free_bytes,
      :allocation_reclaim
    ])
    |> validate_required([:name, :pod_name, :memory_limit_bytes])
    |> validate_number(:memory_limit_bytes, greater_than: 0)
  end
end
