defmodule Tuist.Mix.CacheEvent do
  @moduledoc "A dependency-cache lookup or bypass reported by an instrumented Mix build."
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "mix_dependency_cache_events" do
    field :project_id, Ch, type: "Int64"
    field :build_id, Ch, type: "UUID"
    field :dependency, Ch, type: "String"
    field :outcome, Ch, type: "LowCardinality(String)"
    field :reason, Ch, type: "LowCardinality(String)"
    field :key, Ch, type: "String"
    field :duration_ms, Ch, type: "UInt32"
    field :saved_duration_ms, Ch, type: "Nullable(UInt32)"
    field :is_ci, Ch, type: "Bool"
    field :mix_env, Ch, type: "LowCardinality(String)"
    field :git_branch, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime('UTC')"
    field :read_bytes, Ch, type: "Nullable(UInt64)"
    field :write_bytes, Ch, type: "Nullable(UInt64)"
    field :read_duration_us, Ch, type: "Nullable(UInt64)"
    field :write_duration_us, Ch, type: "Nullable(UInt64)"
    field :read_source, Ch, type: "Nullable(String)"
    field :write_source, Ch, type: "Nullable(String)"
  end
end
