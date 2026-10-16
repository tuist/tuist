defmodule Tuist.BuildEntities.Observation do
  @moduledoc """
  One execution of a build entity, stored in `build_entity_observations`.

  Rows are built by `Tuist.BuildEntities.record/1`; see
  `priv/ingest_repo/migrations/20261009130000_create_build_entity_tables.exs`
  for the storage contract.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "build_entity_observations" do
    field :project_id, Ch, type: "Int64"
    field :system, Ch, type: "LowCardinality(String)"
    field :kind, Ch, type: "LowCardinality(String)"
    field :entity_id, Ch, type: "UUID"
    field :observed_at, Ch, type: "DateTime64(6)"
    field :id, Ch, type: "UUID"
    field :name, Ch, type: "String"
    field :identity, Ch, type: "String"
    field :parent_id, Ch, type: "String"
    field :execution_id, Ch, type: "String"
    field :status, Ch, type: "LowCardinality(String)"
    field :cache_status, Ch, type: "LowCardinality(String)"
    field :duration_ms, Ch, type: "Nullable(UInt64)"
    field :git_branch, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :is_ci, Ch, type: "Nullable(Bool)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
