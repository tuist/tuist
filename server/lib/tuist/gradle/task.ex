defmodule Tuist.Gradle.Task do
  @moduledoc """
  Ecto schema for Gradle tasks stored in ClickHouse.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:gradle_build_id, :cacheable, :task_path, :outcome],
    sortable: [:task_path, :outcome, :duration_ms, :started_at, :cache_artifact_size],
    default_order: %{
      order_by: [:started_at],
      order_directions: [:asc]
    }
  }

  @primary_key false
  schema "gradle_tasks" do
    field :id, Ch, type: "UUID"
    field :gradle_build_id, Ch, type: "UUID"
    field :task_path, Ch, type: "String"
    field :task_type, Ch, type: "Nullable(String)"
    field :outcome, Ch, type: "LowCardinality(String)"
    field :cacheable, Ch, type: "Bool"
    field :duration_ms, Ch, type: "UInt64"
    field :cache_key, Ch, type: "Nullable(String)"
    field :cache_artifact_size, Ch, type: "Nullable(Int64)"
    field :started_at, Ch, type: "Nullable(DateTime64(6))"
    field :project_id, Ch, type: "Int64"
    field :inserted_at, Ch, type: "DateTime"
  end
end
