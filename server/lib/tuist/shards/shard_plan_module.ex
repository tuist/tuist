defmodule Tuist.Shards.ShardPlanModule do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "shard_plan_modules" do
    field :shard_plan_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :shard_index, Ch, type: "UInt16"
    field :module_name, Ch, type: "String"
    field :estimated_duration_ms, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
