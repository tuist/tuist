defmodule Tuist.Gradle.Task do
  @moduledoc """
  Ecto schema for Gradle tasks stored in ClickHouse.
  """
  use Ecto.Schema

  @primary_key false
  schema "gradle_tasks" do
    field :id, Ch, type: "UUID"
    field :gradle_build_id, Ch, type: "UUID"
    field :task_path, Ch, type: "String"
    field :task_type, Ch, type: "Nullable(String)"

    field :outcome,
          Ch,
          type: "Enum8('from_cache' = 0, 'up_to_date' = 1, 'executed' = 2, 'failed' = 3, 'skipped' = 4, 'no_source' = 5)"

    field :cacheable, Ch, type: "Bool"
    field :duration_ms, Ch, type: "UInt64"
    field :cache_key, Ch, type: "Nullable(String)"
    field :cache_artifact_size, Ch, type: "Nullable(Int64)"
    field :project_id, Ch, type: "Int64"
    field :inserted_at, Ch, type: "DateTime"
  end
end
