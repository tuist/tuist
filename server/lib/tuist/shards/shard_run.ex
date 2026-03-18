defmodule Tuist.Shards.ShardRun do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "shard_runs" do
    field :plan_id, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ch, type: "String"
    field :shard_index, Ch, type: "UInt16"
    field :status, Ch, type: "LowCardinality(String)", default: "in_progress"
    field :duration, Ch, type: "UInt64", default: 0
    field :ran_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
