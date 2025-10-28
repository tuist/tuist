defmodule Tuist.Runs.CacheableTask do
  @moduledoc """
  A cacheable task represents a cache hit or miss for a compilation task in a build run.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:build_run_id, :type, :status], sortable: [:inserted_at, :key]
  }

  @primary_key false
  schema "cacheable_tasks" do
    field :type, Ch, type: "Enum8('clang' = 0, 'swift' = 1)"
    field :status, Ch, type: "Enum8('hit_local' = 0, 'hit_remote' = 1, 'miss' = 2)"
    field :key, Ch, type: "String"
    field :build_run_id, Ch, type: "UUID"
    field :inserted_at, Ch, type: "DateTime"
  end

  def changeset(build_run_id, attrs) do
    %{
      build_run_id: build_run_id,
      type: to_string(attrs.type),
      status: to_string(attrs.status),
      key: attrs.key
    }
  end
end
