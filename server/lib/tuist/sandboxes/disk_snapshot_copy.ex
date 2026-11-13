defmodule Tuist.Sandboxes.DiskSnapshotCopy do
  @moduledoc """
  A copy of a disk snapshot on a node other than the one that saved it,
  downloaded from the snapshot's archive (`copy_disks`) so sandboxes of a
  popular project snapshot can be cloned there too. The node names it by
  the snapshot's id, like the snapshot's own copy. It reserves the same
  ceiling on its node and is deleted with its snapshot.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Sandboxes.DiskSnapshot

  @states [:copying, :ready]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sandbox_disk_snapshot_copies" do
    field :node_name, :string
    field :state, Ecto.Enum, values: @states, default: :copying
    field :last_used_at, :utc_datetime

    belongs_to :disk_snapshot, DiskSnapshot, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(copy, attrs) do
    copy
    |> cast(attrs, [:disk_snapshot_id, :node_name, :last_used_at])
    |> validate_required([:disk_snapshot_id, :node_name, :last_used_at])
    |> foreign_key_constraint(:disk_snapshot_id)
    |> unique_constraint([:disk_snapshot_id, :node_name])
  end
end
