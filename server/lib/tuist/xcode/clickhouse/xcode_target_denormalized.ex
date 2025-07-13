defmodule Tuist.Xcode.Clickhouse.XcodeTargetDenormalized do
  @moduledoc false
  use Ecto.Schema

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
  schema "xcode_targets_denormalized" do
    field :id, :string
    field :name, :string
    field :binary_cache_hash, Ch, type: "Nullable(String)"
    field :binary_cache_hit, Ch, type: "Enum8('miss' = 0, 'local' = 1, 'remote' = 2)"
    field :binary_build_duration, Ch, type: "Nullable(UInt32)"
    field :selective_testing_hash, Ch, type: "Nullable(String)"
    field :selective_testing_hit, Ch, type: "Enum8('miss' = 0, 'local' = 1, 'remote' = 2)"
    field :xcode_project_id, :string
    field :project_name, :string
    field :project_path, :string
    field :xcode_graph_id, :string
    field :graph_name, :string
    field :command_event_id, Ch, type: "UUID"
    field :graph_binary_build_duration, Ch, type: "Nullable(UInt32)"

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end

  def normalize_enums(target) do
    %{
      target
      | binary_cache_hit: if(target.binary_cache_hit, do: String.to_atom(target.binary_cache_hit)),
        selective_testing_hit: if(target.selective_testing_hit, do: String.to_atom(target.selective_testing_hit))
    }
  end
end
