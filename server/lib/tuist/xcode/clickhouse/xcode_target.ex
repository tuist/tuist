defmodule Tuist.Xcode.Clickhouse.XcodeTarget do
  @moduledoc false
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false

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
    field :id, :string
    field :name, :string
    field :binary_cache_hash, Ch, type: "Nullable(String)"
    field :binary_cache_hit, Ch, type: "Enum8('miss' = 0, 'local' = 1, 'remote' = 2)"
    field :binary_build_duration, Ch, type: "Nullable(UInt32)"
    field :selective_testing_hash, Ch, type: "Nullable(String)"
    field :selective_testing_hit, Ch, type: "Enum8('miss' = 0, 'local' = 1, 'remote' = 2)"
    field :xcode_project_id, Ch, type: "UUID"
    field :command_event_id, Ch, type: "UUID"

    belongs_to :command_event, Tuist.CommandEvents.Clickhouse.Event,
      foreign_key: :command_event_id,
      references: :id,
      define_field: false

    belongs_to :xcode_project, Tuist.Xcode.Clickhouse.XcodeProject,
      foreign_key: :xcode_project_id,
      references: :id,
      define_field: false

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end

  def changeset(command_event_id, xcode_project_id, xcode_target, inserted_at \\ nil) do
    changeset = %{
      id: UUIDv7.generate(),
      name: xcode_target["name"],
      command_event_id: command_event_id,
      xcode_project_id: xcode_project_id,
      binary_cache_hash: nil,
      binary_cache_hit: hit_enum_to_int(:miss),
      binary_build_duration: nil,
      selective_testing_hash: nil,
      selective_testing_hit: hit_enum_to_int(:miss),
      inserted_at: inserted_at || NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }

    changeset =
      if is_nil(xcode_target["binary_cache_metadata"]) do
        changeset
      else
        changeset
        |> Map.put(:binary_cache_hash, xcode_target["binary_cache_metadata"]["hash"])
        |> Map.put(
          :binary_cache_hit,
          hit_enum_to_int(hit_value_to_enum(xcode_target["binary_cache_metadata"]["hit"], :miss))
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
          hit_enum_to_int(hit_value_to_enum(xcode_target["selective_testing_metadata"]["hit"], :miss))
        )
      end

    changeset
  end

  def normalize_enums(target) do
    %{
      target
      | binary_cache_hit: if(target.binary_cache_hit, do: String.to_atom(target.binary_cache_hit)),
        selective_testing_hit: if(target.selective_testing_hit, do: String.to_atom(target.selective_testing_hit))
    }
  end

  defp hit_value_to_enum(metadata, _default) when is_nil(metadata), do: :miss
  defp hit_value_to_enum(hit_value, _default), do: Tuist.Xcode.normalize_hit_value(hit_value)

  defp hit_enum_to_int(:miss), do: 0
  defp hit_enum_to_int(:local), do: 1
  defp hit_enum_to_int(:remote), do: 2
  defp hit_enum_to_int(_), do: 0
end
