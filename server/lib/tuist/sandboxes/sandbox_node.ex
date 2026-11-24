defmodule Tuist.Sandboxes.SandboxNode do
  @moduledoc """
  The memory limit the server last asked a sandbox node's daemon Pod for,
  when the node's carve-out is elastic, and the runners-controller's latest
  grant for the node. See `Tuist.Sandboxes.Capacity`.
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
    field :allocation_cpu_free_milli, :integer
    field :allocation_cpu_reclaimable_milli, :integer
    field :allocation_reclaim, :boolean, default: true
    field :allocation_warm_bytes, :integer
    field :allocation_sibling_memory_bytes, :integer

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
      :allocation_cpu_free_milli,
      :allocation_cpu_reclaimable_milli,
      :allocation_reclaim,
      :allocation_warm_bytes,
      :allocation_sibling_memory_bytes
    ])
    |> validate_required([:name, :pod_name, :memory_limit_bytes])
    |> validate_number(:memory_limit_bytes, greater_than: 0)
  end
end
