defmodule Tuist.Cache.ModuleCacheEvent do
  @moduledoc """
  Ecto schema for module cache events stored in ClickHouse.
  """
  use Ecto.Schema

  @primary_key false
  schema "module_cache_events" do
    field :id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :run_id, Ch, type: "String"
    field :source, Ch, type: "Enum8('disk' = 0, 's3' = 1)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
