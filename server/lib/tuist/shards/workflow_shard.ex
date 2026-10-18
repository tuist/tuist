defmodule Tuist.Shards.WorkflowShard do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "shard_workflow_shards" do
    belongs_to :workflow, Tuist.Shards.Workflow, type: Ecto.UUID, primary_key: true
    field :shard_index, :integer, primary_key: true
    field :assignment, :map
    field :status, :string
    field :duration, :integer, default: 0
    field :ran_at, :utc_datetime_usec
    field :reported_at, :utc_datetime_usec
  end
end
