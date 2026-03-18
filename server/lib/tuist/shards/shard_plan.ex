defmodule Tuist.Shards.ShardPlan do
  @moduledoc """
  A shard plan represents a test sharding plan for distributing tests
  across multiple CI runners. This is a ClickHouse entity.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "shard_plans" do
    field :plan_id, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
    field :shard_count, Ch, type: "Int32"
    field :granularity, Ch, type: "LowCardinality(String)", default: "module"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(shard_plan \\ %__MODULE__{}, attrs) do
    shard_plan
    |> cast(attrs, [
      :id,
      :plan_id,
      :project_id,
      :shard_count,
      :granularity,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :plan_id,
      :project_id,
      :shard_count,
      :inserted_at
    ])
    |> validate_inclusion(:granularity, ["module", "suite"])
  end
end
