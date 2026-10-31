defmodule Tuist.Shards.ShardPlanRoute do
  @moduledoc """
  The upload routing of a recently created shard plan: its ID for the plan's reference and its
  storage target. Upload requests read it instead of the ClickHouse plan row, which replicas
  may not have yet.
  """

  use Ecto.Schema

  @primary_key {:plan_id, Ecto.UUID, autogenerate: false}
  schema "shard_plan_routes" do
    field :project_id, :integer
    field :reference, :string
    field :storage_target, :string, default: ""
    field :inserted_at, :utc_datetime_usec
  end
end
