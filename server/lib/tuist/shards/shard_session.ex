defmodule Tuist.Shards.ShardSession do
  @moduledoc """
  A shard session represents a test sharding plan for distributing tests
  across multiple CI runners. This is a ClickHouse entity.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "shard_sessions" do
    field :session_id, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
    field :shard_count, Ch, type: "Int32"
    field :granularity, Ch, type: "LowCardinality(String)", default: "module"
    field :shard_assignments, Ch, type: "String", default: "[]"
    field :upload_completed, Ch, type: "UInt8", default: 0
    field :bundle_object_key, Ch, type: "String", default: ""
    field :xctestrun_object_key, Ch, type: "String", default: ""
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(shard_session \\ %__MODULE__{}, attrs) do
    shard_session
    |> cast(attrs, [
      :id,
      :session_id,
      :project_id,
      :shard_count,
      :granularity,
      :shard_assignments,
      :upload_completed,
      :bundle_object_key,
      :xctestrun_object_key,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :session_id,
      :project_id,
      :shard_count,
      :inserted_at
    ])
    |> validate_inclusion(:granularity, ["module", "suite"])
  end

  def decode_shard_assignments(%__MODULE__{shard_assignments: json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, assignments} -> assignments
      {:error, _} -> []
    end
  end

  def decode_shard_assignments(_), do: []

  def encode_shard_assignments(assignments) when is_list(assignments) do
    Jason.encode!(assignments)
  end
end
