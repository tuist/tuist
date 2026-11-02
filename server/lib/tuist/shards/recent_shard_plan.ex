defmodule Tuist.Shards.RecentShardPlan do
  @moduledoc """
  A shard plan created in the last day: the fields uploads need (the plan ID for its reference
  and its storage target). Upload requests read it instead of the ClickHouse plan row, which
  replicas may not have yet.
  """

  use Ecto.Schema

  @primary_key {:plan_id, Ecto.UUID, autogenerate: false}
  schema "recent_shard_plans" do
    field :project_id, :integer
    field :reference, :string
    field :storage_target, :string, default: ""
    field :inserted_at, :utc_datetime_usec
  end
end
