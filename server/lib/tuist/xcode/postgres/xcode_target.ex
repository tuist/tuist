defmodule Tuist.Xcode.Postgres.XcodeTarget do
  @moduledoc """
  Xcode graph target
  """
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}

  @derive {
    Flop.Schema,
    filterable: [:name],
    sortable: [:name, :binary_cache_hit, :selective_testing_hit],
    default_order: %{
      order_by: [:name],
      order_directions: [:asc]
    }
  }

  schema "xcode_targets" do
    field :name, :string
    field :binary_cache_hash, :string
    field :binary_build_duration, :integer
    field :binary_cache_hit, Ecto.Enum, values: [miss: 0, local: 1, remote: 2]
    field :selective_testing_hash, :string
    field :selective_testing_hit, Ecto.Enum, values: [miss: 0, local: 1, remote: 2]

    belongs_to :xcode_project, Tuist.Xcode.Postgres.XcodeProject, type: UUIDv7

    timestamps(type: :utc_datetime)
  end

  def changeset(xcode_project_id, xcode_target) do
    changeset = %{
      id: UUIDv7.generate(),
      name: xcode_target["name"],
      xcode_project_id: xcode_project_id,
      inserted_at: DateTime.utc_now(:second),
      updated_at: DateTime.utc_now(:second)
    }

    changeset =
      if is_nil(xcode_target["binary_cache_metadata"]) do
        changeset
      else
        changeset
        |> Map.put(:binary_cache_hash, xcode_target["binary_cache_metadata"]["hash"])
        |> Map.put(
          :binary_cache_hit,
          to_hit_value(xcode_target["binary_cache_metadata"]["hit"])
        )
        |> Map.put(
          :binary_build_duration,
          xcode_target["binary_cache_metadata"]["build_duration"]
        )
      end

    changeset =
      if is_nil(xcode_target["selective_testing_metadata"]) do
        changeset
      else
        changeset
        |> Map.put(:selective_testing_hash, xcode_target["selective_testing_metadata"]["hash"])
        |> Map.put(
          :selective_testing_hit,
          String.to_atom(xcode_target["selective_testing_metadata"]["hit"])
        )
      end

    changeset
  end

  defp to_hit_value(value), do: Tuist.Xcode.normalize_hit_value(value)
end
