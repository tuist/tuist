defmodule Atlas.Memory.Edge do
  @moduledoc """
  Directed link between two memory nodes.

  Three kinds for now (adapted from spacebot.sh):

    - `:related_to`  — symmetric semantic connection between two nodes that
      share topic but neither supersedes nor contradicts the other.
    - `:updates`     — `src` supersedes or refines `dst`. Used at recall time
      to demote the older `dst` when the newer `src` is also in scope.
    - `:contradicts` — `src` and `dst` make incompatible claims. Used at
      recall time to prefer the newer of the two.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Memory.Node

  @kinds [:related_to, :updates, :contradicts]

  schema "memory_edges" do
    field :kind, Ecto.Enum, values: @kinds
    field :weight, :float, default: 1.0

    belongs_to :src, Node, foreign_key: :src_id
    belongs_to :dst, Node, foreign_key: :dst_id

    timestamps()
  end

  def kinds, do: @kinds

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:kind, :weight])
    |> put_fk(attrs, :src_id)
    |> put_fk(attrs, :dst_id)
    |> validate_required([:kind, :weight, :src_id, :dst_id])
    |> validate_number(:weight, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_distinct_endpoints()
    |> unique_constraint([:src_id, :dst_id, :kind])
  end

  defp put_fk(changeset, attrs, key) do
    value = Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
    if value, do: put_change(changeset, key, value), else: changeset
  end

  defp validate_distinct_endpoints(changeset) do
    src = get_field(changeset, :src_id)
    dst = get_field(changeset, :dst_id)

    if src && dst && src == dst do
      add_error(changeset, :dst_id, "must differ from src_id")
    else
      changeset
    end
  end
end
