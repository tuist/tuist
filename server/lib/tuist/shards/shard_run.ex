defmodule Tuist.Shards.ShardRun do
  @moduledoc false
  use Ecto.Schema

  def query do
    Ecto.Queryable.to_query({"shard_run_summaries", __MODULE__})
  end

  @primary_key false
  schema "shard_runs" do
    field :shard_plan_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ch, type: "String"
    field :shard_index, Ch, type: "UInt16"
    field :status, Ch, type: "LowCardinality(String)"
    field :duration, Ch, type: "UInt64", default: 0
    field :ran_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
