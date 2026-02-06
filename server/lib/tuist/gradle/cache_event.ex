defmodule Tuist.Gradle.CacheEvent do
  @moduledoc """
  Ecto schema for Gradle cache events stored in ClickHouse.
  """
  use Ecto.Schema

  @primary_key false
  schema "gradle_cache_events" do
    field :id, Ch, type: "UUID"
    field :action, Ch, type: "Enum8('upload' = 0, 'download' = 1)"
    field :cache_key, Ch, type: "String"
    field :size, Ch, type: "Int64"
    field :duration_ms, Ch, type: "UInt64"
    field :is_hit, Ch, type: "Bool"
    field :project_id, Ch, type: "Int64"
    field :account_handle, Ch, type: "String"
    field :project_handle, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime"
  end
end
